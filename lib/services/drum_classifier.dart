import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../core/constants.dart';
import '../models/drum_hit.dart';
import '../models/processing_settings.dart';

/// TFLite-based drum classifier using v4 CNN on mel spectrogram patches.
///
/// Pipeline per onset:
///   1. Extract 15-frame mel patch centered on onset
///   2. CNN classifies as kick/snare/neither (3-class)
///   3. Reject if neither is argmax
///   4. Reject if margin over neither is too small
///   5. Reject if confidence below threshold
class DrumClassifier {
  Interpreter? _cnnInterpreter;

  /// Global mel normalization parameters loaded from mel_norm_params.json.
  double _melMean = 0.0;
  double _melStd = 1.0;

  /// Pre-load the TFLite C library so the interpreter can find it.
  static void _preloadTfLiteDll() {
    if (!Platform.isWindows) return;

    const dllName = 'libtensorflowlite_c-win.dll';
    final exeDir = File(Platform.resolvedExecutable).parent.path;

    for (final candidate in [
      '$exeDir\\$dllName',
      '$exeDir\\blobs\\$dllName',
    ]) {
      if (File(candidate).existsSync()) {
        try {
          DynamicLibrary.open(candidate);
          debugPrint('[DrumClassifier] Loaded TFLite DLL from: $candidate');
          return;
        } catch (e) {
          debugPrint('[DrumClassifier] Failed to load $candidate: $e');
        }
      }
    }
    debugPrint(
        '[DrumClassifier] TFLite DLL not found next to exe, relying on system PATH');
  }

  /// Load TFLite CNN model and mel normalization parameters.
  Future<void> load() async {
    _preloadTfLiteDll();

    // Load CNN model
    _cnnInterpreter = await _loadModel('drum_classifier.tflite');
    _validateCnnShape();

    // Load mel normalization parameters
    await _loadMelNormParams();
  }

  Future<Interpreter> _loadModel(String filename) async {
    try {
      return await Interpreter.fromAsset('models/$filename');
    } catch (_) {
      final data = await rootBundle.load('assets/models/$filename');
      final tempDir = await getTemporaryDirectory();
      final modelFile = File('${tempDir.path}/$filename');
      await modelFile.writeAsBytes(data.buffer.asUint8List());
      return Interpreter.fromFile(modelFile);
    }
  }

  /// Load global mel mean/std from bundled JSON asset.
  Future<void> _loadMelNormParams() async {
    try {
      final jsonStr =
          await rootBundle.loadString('assets/models/mel_norm_params.json');
      final params = json.decode(jsonStr) as Map<String, dynamic>;
      _melMean = (params['mean'] as num).toDouble();
      _melStd = (params['std'] as num).toDouble();
      debugPrint(
          '[DrumClassifier] Mel norm loaded: mean=$_melMean, std=$_melStd');
    } catch (e) {
      debugPrint(
          '[DrumClassifier] WARNING: Could not load mel_norm_params.json: $e');
      debugPrint('[DrumClassifier] Using default mean=0.0, std=1.0');
    }
  }

  /// Validate that the CNN model has the expected tensor shapes.
  void _validateCnnShape() {
    final interp = _cnnInterpreter!;
    final inputTensor = interp.getInputTensor(0);
    final outputTensor = interp.getOutputTensor(0);

    debugPrint('[DrumClassifier] CNN input: ${inputTensor.shape}');
    debugPrint('[DrumClassifier] CNN output: ${outputTensor.shape}');

    final expectedInput = [1, AudioConstants.cnnContextFrames, AudioConstants.nMels, 1];
    const expectedOutput = [1, 3];

    if (inputTensor.shape.length != expectedInput.length ||
        !_shapeMatches(inputTensor.shape, expectedInput)) {
      throw StateError(
        'CNN input shape mismatch: '
        'expected $expectedInput, got ${inputTensor.shape}',
      );
    }
    if (outputTensor.shape.length != expectedOutput.length ||
        !_shapeMatches(outputTensor.shape, expectedOutput)) {
      throw StateError(
        'CNN output shape mismatch: '
        'expected $expectedOutput, got ${outputTensor.shape}',
      );
    }
  }

  bool _shapeMatches(List<int> actual, List<int> expected) {
    for (int i = 0; i < expected.length; i++) {
      if (actual[i] != expected[i]) return false;
    }
    return true;
  }

  /// Classify onsets using CNN inference on mel spectrogram patches.
  ///
  /// [melFrames]: pre-computed log-mel spectrogram frames (40 bands each).
  /// [onsetTimes]: detected onset times in seconds.
  /// [fps]: video frame rate.
  /// [settings]: detection thresholds.
  List<DrumHit> classify({
    required List<List<double>> melFrames,
    required List<double> onsetTimes,
    required double fps,
    required ProcessingSettings settings,
  }) {
    if (_cnnInterpreter == null) {
      throw StateError('Model not loaded. Call load() first.');
    }

    final nMelFrames = melFrames.length;
    final hits = <DrumHit>[];

    debugPrint('[DrumClassifier] Classifying ${onsetTimes.length} onsets '
        '(kickThresh=${settings.kickThreshold}, snareThresh=${settings.snareThreshold}) '
        'using v4 CNN (${AudioConstants.cnnContextFrames}-frame) on $nMelFrames mel frames');

    int rejectedNeither = 0;
    int rejectedMargin = 0;
    int rejectedBelowThreshold = 0;

    for (final onsetTime in onsetTimes) {
      // Convert onset time to mel frame index
      final onsetFrame = (onsetTime * AudioConstants.sampleRate /
              AudioConstants.hopLength)
          .round();

      // Extract 15-frame patch centered on onset, with boundary shifting
      var start = onsetFrame - AudioConstants.cnnContextHalf;
      var end = onsetFrame + AudioConstants.cnnContextHalf + 1;

      if (start < 0) {
        start = 0;
        end = AudioConstants.cnnContextFrames;
      }
      if (end > nMelFrames) {
        end = nMelFrames;
        start = (end - AudioConstants.cnnContextFrames)
            .clamp(0, nMelFrames);
      }

      // Build patch [15, 40, 1] with normalization
      final patch = List.generate(
        AudioConstants.cnnContextFrames,
        (t) {
          final frameIdx = start + t;
          if (frameIdx >= 0 && frameIdx < nMelFrames) {
            return List.generate(AudioConstants.nMels, (m) {
              final val = melFrames[frameIdx][m];
              return [(val - _melMean) / (_melStd + 1e-8)];
            });
          } else {
            final silenceNorm =
                ((-20.7232) - _melMean) / (_melStd + 1e-8);
            return List.generate(
                AudioConstants.nMels, (_) => [silenceNorm]);
          }
        },
      );

      // CNN inference — input [1, 15, 40, 1], output [1, 3]
      final input = [patch];
      final output = List.generate(1, (_) => List.filled(3, 0.0));
      _cnnInterpreter!.run(input, output);

      final kickProb = output[0][0];
      final snareProb = output[0][1];
      final neitherProb = output[0][2];

      // Layer 1: Reject if "neither" is the argmax
      if (neitherProb >= kickProb && neitherProb >= snareProb) {
        rejectedNeither++;
        continue;
      }

      // Layer 2: Reject if margin over "neither" is too small
      final winnerProb = math.max(kickProb, snareProb);
      if ((winnerProb - neitherProb) < DetectionDefaults.neitherMargin) {
        rejectedMargin++;
        continue;
      }

      // Layer 3: Confidence threshold
      if (kickProb > snareProb && kickProb >= settings.kickThreshold) {
        hits.add(DrumHit(
          time: onsetTime,
          type: DrumType.kick,
          confidence: kickProb,
          frame: (onsetTime * fps).round(),
        ));
      } else if (snareProb > kickProb && snareProb >= settings.snareThreshold) {
        hits.add(DrumHit(
          time: onsetTime,
          type: DrumType.snare,
          confidence: snareProb,
          frame: (onsetTime * fps).round(),
        ));
      } else {
        rejectedBelowThreshold++;
      }
    }

    debugPrint('[DrumClassifier] Results: ${hits.length} hits accepted, '
        'rejected: '
        '$rejectedNeither neither-argmax, '
        '$rejectedMargin margin<${DetectionDefaults.neitherMargin}, '
        '$rejectedBelowThreshold below-threshold');

    final deduped = _deduplicate(hits);

    final finalKicks = deduped.where((h) => h.type == DrumType.kick).toList();
    final finalSnares =
        deduped.where((h) => h.type == DrumType.snare).toList();

    final result = [...finalKicks, ...finalSnares]
      ..sort((a, b) => a.time.compareTo(b.time));
    debugPrint('[DrumClassifier] Final: ${finalKicks.length} kicks, '
        '${finalSnares.length} snares');

    return result;
  }

  /// Remove duplicate hits within the minimum gap, per drum type.
  List<DrumHit> _deduplicate(List<DrumHit> hits) {
    if (hits.isEmpty) return hits;

    final minGapSec = DetectionDefaults.minHitGapMs / 1000.0;

    final kicks = hits.where((h) => h.type == DrumType.kick).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    final snares = hits.where((h) => h.type == DrumType.snare).toList()
      ..sort((a, b) => a.time.compareTo(b.time));

    List<DrumHit> dedup(List<DrumHit> typed) {
      if (typed.isEmpty) return typed;
      final result = <DrumHit>[typed.first];
      for (int i = 1; i < typed.length; i++) {
        if (typed[i].time - result.last.time >= minGapSec) {
          result.add(typed[i]);
        } else if (typed[i].confidence > result.last.confidence) {
          result[result.length - 1] = typed[i];
        }
      }
      return result;
    }

    final dedupedKicks = dedup(kicks);
    final dedupedSnares = dedup(snares);

    return [...dedupedKicks, ...dedupedSnares]
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  void dispose() {
    _cnnInterpreter?.close();
    _cnnInterpreter = null;
  }
}
