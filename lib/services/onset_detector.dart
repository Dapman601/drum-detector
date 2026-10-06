import 'dart:math' as math;

import '../core/constants.dart';

/// Spectral flux onset detection from a mel spectrogram.
///
/// Algorithm:
///   1. Compute spectral flux: sum of positive frame-to-frame differences
///   2. Adaptive threshold: local median + offset
///   3. Peak picking with minimum gap
class OnsetDetector {
  /// Detect onset times (in seconds) from a mel spectrogram.
  ///
  /// [melFrames] is a list of mel spectrogram frames, each with nMels values.
  /// Returns onset times in seconds.
  List<double> detect(List<List<double>> melFrames) {
    if (melFrames.length < 2) return [];

    // Step 1: Compute spectral flux
    final flux = _spectralFlux(melFrames);

    // Step 2: Absolute flux floor (25th percentile of non-zero values).
    // Prevents weak vocal/guitar transients from triggering in quiet sections.
    final fluxFloor = _fluxFloor(flux);

    // Step 3: Adaptive threshold
    final threshold = _adaptiveThreshold(flux);

    // Step 4: Peak picking (with floor)
    var onsetFrames = _pickPeaks(flux, threshold, fluxFloor);

    // Step 5: Cap onset count — keep only the strongest peaks.
    final durationSec = melFrames.length * AudioConstants.hopLength /
        AudioConstants.sampleRate;
    final maxOnsets = math.max(
        30, (durationSec * DetectionDefaults.maxOnsetsPerSecond).round());
    final rawCount = onsetFrames.length;
    if (onsetFrames.length > maxOnsets) {
      onsetFrames.sort((a, b) => flux[b].compareTo(flux[a]));
      onsetFrames = onsetFrames.sublist(0, maxOnsets);
      onsetFrames.sort();
    }

    // Use print (not debugPrint) because this runs inside compute() isolate
    print('[OnsetDetector] Spectral flux stats: '
        'max=${flux.reduce(math.max).toStringAsFixed(4)}, '
        'mean=${(flux.reduce((a, b) => a + b) / flux.length).toStringAsFixed(4)}, '
        'floor=${fluxFloor.toStringAsFixed(4)}');
    print('[OnsetDetector] Detected $rawCount raw onsets, capped to '
        '${onsetFrames.length} (max=$maxOnsets) from ${melFrames.length} frames '
        '(multiplier=${DetectionDefaults.onsetThresholdMultiplier}, '
        'offset=${DetectionDefaults.onsetThresholdOffset}, '
        'minGap=${DetectionDefaults.minHitGapMs}ms, '
        'maxPerSec=${DetectionDefaults.maxOnsetsPerSecond})');

    // Convert frame indices to seconds
    final hopDuration = AudioConstants.hopLength / AudioConstants.sampleRate;
    return onsetFrames.map((f) => f * hopDuration).toList();
  }

  /// Compute spectral flux: sum of positive differences between consecutive frames.
  List<double> _spectralFlux(List<List<double>> frames) {
    final flux = List<double>.filled(frames.length, 0.0);
    for (int i = 1; i < frames.length; i++) {
      double sum = 0.0;
      for (int j = 0; j < frames[i].length; j++) {
        final diff = frames[i][j] - frames[i - 1][j];
        if (diff > 0) sum += diff;
      }
      flux[i] = sum;
    }
    return flux;
  }

  /// Compute 50th percentile (median) of non-zero spectral flux values.
  /// Serves as an absolute floor — any onset below this is rejected
  /// regardless of the adaptive threshold. Adapts to recording volume.
  double _fluxFloor(List<double> flux) {
    final nonZero = flux.where((v) => v > 0).toList()..sort();
    if (nonZero.isEmpty) return 0.0;
    final idx = (nonZero.length * 0.50).floor().clamp(0, nonZero.length - 1);
    return nonZero[idx];
  }

  /// Adaptive threshold using local median + multiplier + offset.
  List<double> _adaptiveThreshold(List<double> flux) {
    final windowSize = DetectionDefaults.onsetMedianWindowFrames;
    final multiplier = DetectionDefaults.onsetThresholdMultiplier;
    final offset = DetectionDefaults.onsetThresholdOffset;
    final threshold = List<double>.filled(flux.length, 0.0);

    for (int i = 0; i < flux.length; i++) {
      final start = math.max(0, i - windowSize);
      final end = math.min(flux.length, i + windowSize + 1);
      final window = flux.sublist(start, end).toList()..sort();
      final median = window[window.length ~/ 2];
      threshold[i] = median * multiplier + offset;
    }

    return threshold;
  }

  /// Pick peaks that exceed the threshold with minimum gap enforcement.
  /// [floor] is the absolute minimum flux value (25th percentile).
  List<int> _pickPeaks(List<double> flux, List<double> threshold, double floor) {
    final minGapFrames = (DetectionDefaults.minHitGapMs / 1000.0 *
            AudioConstants.sampleRate /
            AudioConstants.hopLength)
        .round();

    final peaks = <int>[];

    for (int i = 1; i < flux.length - 1; i++) {
      // Must exceed absolute flux floor (rejects weak transients)
      if (flux[i] < floor) continue;

      // Must exceed adaptive threshold
      if (flux[i] <= threshold[i]) continue;

      // Must be a local maximum
      if (flux[i] <= flux[i - 1] || flux[i] <= flux[i + 1]) continue;

      // Enforce minimum gap
      if (peaks.isNotEmpty && (i - peaks.last) < minGapFrames) continue;

      peaks.add(i);
    }

    return peaks;
  }
}
