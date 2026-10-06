import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../models/detection_report.dart';
import '../models/drum_hit.dart';
import '../models/processing_settings.dart';
import 'audio_extractor.dart';
import 'drum_classifier.dart';
import 'mel_spectrogram.dart';
import 'onset_detector.dart';
import 'video_effects.dart';

/// Top-level function for compute() — runs mel spectrogram + onset detection
/// in a background isolate. Must be top-level (not a closure or instance method).
Map<String, dynamic> _computeSpectrogramAndOnsets(Float32List samples) {
  final melService = MelSpectrogramService();
  final onsetDetector = OnsetDetector();

  final melFrames = melService.compute(samples);
  final onsetTimes = onsetDetector.detect(melFrames);

  return {
    'melFrames': melFrames,
    'onsetTimes': onsetTimes,
  };
}

/// Orchestrates the full detection + effects pipeline with progress callbacks.
class Pipeline {
  final AudioExtractor _audioExtractor = AudioExtractor();
  final DrumClassifier _classifier = DrumClassifier();
  final VideoEffectsService _effectsService = VideoEffectsService();

  /// Run the full pipeline on [videoPath] with [settings].
  ///
  /// When [skipEffects] is true, skip the FFmpeg video effects step.
  /// This reduces processing time by ~60% and returns detection results
  /// immediately. FFmpeg baking can be done later via [applyEffects].
  ///
  /// [onProgress] is called with (stage, progressFraction, message).
  Future<PipelineResult> run({
    required String videoPath,
    required ProcessingSettings settings,
    required void Function(PipelineStage stage, double progress, String message)
        onProgress,
    bool skipEffects = true,
  }) async {
    // Load classifier model
    await _classifier.load();

    // Get video info
    onProgress(PipelineStage.extractingAudio, 0.0, 'Reading video info...');
    final videoInfo = await _effectsService.getVideoInfo(videoPath);
    final fps = videoInfo.fps;

    // Step 1: Extract audio (0–15%)
    onProgress(PipelineStage.extractingAudio, 0.02, 'Extracting audio...');
    final audioResult = await _audioExtractor.extract(videoPath);
    onProgress(PipelineStage.extractingAudio, 0.15,
        'Audio extracted: ${audioResult.durationSeconds.toStringAsFixed(1)}s');

    // Step 2+3: Compute mel spectrogram + detect onsets in background isolate (15–40%)
    onProgress(PipelineStage.computingSpectrogram, 0.15,
        'Computing spectrogram & detecting onsets...');
    final isolateResult = await compute(
      _computeSpectrogramAndOnsets,
      audioResult.samples,
    );
    final melFrames = isolateResult['melFrames'] as List<List<double>>;
    final onsetTimes = isolateResult['onsetTimes'] as List<double>;
    onProgress(PipelineStage.detectingOnsets, 0.40,
        '${melFrames.length} frames, ${onsetTimes.length} onsets');

    // Step 4: Classify each onset using CNN on mel patches (40–70%)
    onProgress(PipelineStage.classifyingHits, 0.40, 'Classifying drum hits...');
    final hits = _classifier.classify(
      melFrames: melFrames,
      onsetTimes: onsetTimes,
      fps: fps,
      settings: settings,
    );
    final kicks = hits.where((h) => h.type == DrumType.kick).toList();
    final snares = hits.where((h) => h.type == DrumType.snare).toList();
    onProgress(PipelineStage.classifyingHits, 0.70,
        '${kicks.length} kicks, ${snares.length} snares');

    String? outputPath;

    if (!skipEffects) {
      // Step 5: Apply video effects (70–95%)
      onProgress(PipelineStage.applyingEffects, 0.70, 'Building effects...');
      outputPath = await _effectsService.apply(
        inputPath: videoPath,
        hits: hits,
        settings: settings,
        width: videoInfo.width,
        height: videoInfo.height,
        fps: fps,
      );
      onProgress(PipelineStage.applyingEffects, 0.95, 'Effects applied');
    } else {
      onProgress(PipelineStage.applyingEffects, 0.95,
          'Skipped (real-time effects mode)');
    }

    // Step 6: Generate report (95–100%)
    onProgress(PipelineStage.generatingReport, 0.95, 'Generating report...');
    final report = DetectionReport(
      inputFile: videoPath,
      outputFile: outputPath ?? videoPath,
      durationSeconds: audioResult.durationSeconds,
      fps: fps,
      kicks: kicks,
      snares: snares,
      settings: {
        'kick_threshold': settings.kickThreshold,
        'snare_threshold': settings.snareThreshold,
        'kick_effect': settings.kickEffect.name,
        'snare_effect': settings.snareEffect.name,
      },
    );
    onProgress(PipelineStage.complete, 1.0, 'Done');

    // Cleanup temp WAV
    try {
      await File(audioResult.wavPath).delete();
    } catch (_) {}

    _classifier.dispose();

    return PipelineResult(
      outputVideoPath: outputPath,
      report: report,
      hits: hits,
    );
  }

  /// Apply FFmpeg effects to a video on-demand (for export).
  Future<String> applyEffects({
    required String videoPath,
    required List<DrumHit> hits,
    required ProcessingSettings settings,
  }) async {
    final videoInfo = await _effectsService.getVideoInfo(videoPath);
    return _effectsService.apply(
      inputPath: videoPath,
      hits: hits,
      settings: settings,
      width: videoInfo.width,
      height: videoInfo.height,
      fps: videoInfo.fps,
    );
  }
}

class PipelineResult {
  final String? outputVideoPath;
  final DetectionReport report;
  final List<DrumHit> hits;

  const PipelineResult({
    required this.outputVideoPath,
    required this.report,
    required this.hits,
  });
}
