import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../models/detection_report.dart';
import '../models/drum_hit.dart';
import '../services/pipeline.dart';
import 'settings_provider.dart';

/// State for the processing pipeline.
class PipelineState {
  final PipelineStage stage;
  final double progress; // 0.0–1.0
  final String message;
  final String? videoPath; // input video (original)
  final String? outputVideoPath; // FFmpeg-processed video (only after export)
  final DetectionReport? report;
  final List<DrumHit> hits; // detected hits for real-time overlay
  final String? error;
  final bool isExporting;

  const PipelineState({
    this.stage = PipelineStage.idle,
    this.progress = 0.0,
    this.message = '',
    this.videoPath,
    this.outputVideoPath,
    this.report,
    this.hits = const [],
    this.error,
    this.isExporting = false,
  });

  bool get isProcessing =>
      stage != PipelineStage.idle &&
      stage != PipelineStage.complete &&
      stage != PipelineStage.error;

  bool get isComplete => stage == PipelineStage.complete;
  bool get hasError => stage == PipelineStage.error;

  PipelineState copyWith({
    PipelineStage? stage,
    double? progress,
    String? message,
    String? videoPath,
    String? outputVideoPath,
    DetectionReport? report,
    List<DrumHit>? hits,
    String? error,
    bool? isExporting,
  }) {
    return PipelineState(
      stage: stage ?? this.stage,
      progress: progress ?? this.progress,
      message: message ?? this.message,
      videoPath: videoPath ?? this.videoPath,
      outputVideoPath: outputVideoPath ?? this.outputVideoPath,
      report: report ?? this.report,
      hits: hits ?? this.hits,
      error: error ?? this.error,
      isExporting: isExporting ?? this.isExporting,
    );
  }
}

class PipelineNotifier extends StateNotifier<PipelineState> {
  final Ref _ref;

  PipelineNotifier(this._ref) : super(const PipelineState());

  /// Start processing a video file.
  ///
  /// Uses skipEffects=true by default so we get detection results fast
  /// and can show real-time visual effects on the original video.
  Future<void> process(String videoPath) async {
    state = PipelineState(
      stage: PipelineStage.extractingAudio,
      videoPath: videoPath,
      message: 'Starting...',
    );

    final settings = _ref.read(settingsProvider);
    final pipeline = Pipeline();

    try {
      final result = await pipeline.run(
        videoPath: videoPath,
        settings: settings,
        skipEffects: true,
        onProgress: (stage, progress, message) {
          if (mounted) {
            state = state.copyWith(
              stage: stage,
              progress: progress,
              message: message,
            );
          }
        },
      );

      if (mounted) {
        state = state.copyWith(
          stage: PipelineStage.complete,
          progress: 1.0,
          message: 'Processing complete',
          outputVideoPath: result.outputVideoPath,
          report: result.report,
          hits: result.hits,
        );
      }
    } catch (e) {
      if (mounted) {
        state = state.copyWith(
          stage: PipelineStage.error,
          error: e.toString(),
          message: 'Error: $e',
        );
      }
    }
  }

  /// Export the video with FFmpeg-baked effects.
  ///
  /// This runs the slow FFmpeg pass on-demand when the user clicks Export.
  Future<String?> exportWithEffects() async {
    final videoPath = state.videoPath;
    final hits = state.hits;

    // Write diagnostic log to project folder for debugging
    debugPrint('[Export] videoPath=$videoPath, hits=${hits.length}');
    if (videoPath == null) return null;
    if (hits.isEmpty) {
      debugPrint('[Export] ERROR: hits list is empty!');
      throw Exception('No drum hits detected — nothing to export');
    }

    state = state.copyWith(isExporting: true);

    try {
      final settings = _ref.read(settingsProvider);
      final pipeline = Pipeline();
      final outputPath = await pipeline.applyEffects(
        videoPath: videoPath,
        hits: hits,
        settings: settings,
      );

      if (mounted) {
        state = state.copyWith(
          outputVideoPath: outputPath,
          isExporting: false,
        );
      }
      return outputPath;
    } catch (e) {
      if (mounted) {
        state = state.copyWith(isExporting: false);
      }
      rethrow;
    }
  }

  /// Reset to idle state for processing another video.
  void reset() {
    state = const PipelineState();
  }
}

final pipelineProvider =
    StateNotifierProvider<PipelineNotifier, PipelineState>(
  (ref) => PipelineNotifier(ref),
);
