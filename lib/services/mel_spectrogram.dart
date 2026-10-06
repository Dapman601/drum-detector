import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

import '../core/constants.dart';

/// Computes log-mel spectrograms from raw audio samples using Dart FFT.
class MelSpectrogramService {
  late final List<List<double>> _melFilterbank;
  late final FFT _fft;

  MelSpectrogramService() {
    _fft = FFT(AudioConstants.nFft);
    _melFilterbank = _buildMelFilterbank(
      nMels: AudioConstants.nMels,
      nFft: AudioConstants.nFft,
      sampleRate: AudioConstants.sampleRate,
      fMin: AudioConstants.fMin,
      fMax: AudioConstants.fMax,
    );
  }

  /// Compute log-mel spectrogram from raw PCM float samples.
  /// Returns a list of frames, each frame is a list of [nMels] values.
  List<List<double>> compute(Float32List samples) {
    final hopLength = AudioConstants.hopLength;
    final nFft = AudioConstants.nFft;
    final nFrames = ((samples.length - nFft) / hopLength).floor() + 1;

    if (nFrames <= 0) return [];

    final frames = <List<double>>[];
    final window = _hannWindow(nFft);

    for (int i = 0; i < nFrames; i++) {
      final start = i * hopLength;
      final end = start + nFft;
      if (end > samples.length) break;

      // Apply Hann window
      final windowed = Float64List(nFft);
      for (int j = 0; j < nFft; j++) {
        windowed[j] = samples[start + j] * window[j];
      }

      // Compute FFT
      final spectrum = _fft.realFft(windowed);

      // Compute power spectrum (magnitude squared)
      final nBins = nFft ~/ 2 + 1;
      final power = Float64List(nBins);
      for (int j = 0; j < nBins; j++) {
        final real = spectrum[j].x;
        final imag = spectrum[j].y;
        power[j] = real * real + imag * imag;
      }

      // Apply mel filterbank
      final melFrame = List<double>.filled(AudioConstants.nMels, 0.0);
      for (int m = 0; m < AudioConstants.nMels; m++) {
        double sum = 0.0;
        for (int j = 0; j < nBins; j++) {
          sum += _melFilterbank[m][j] * power[j];
        }
        // Log-mel
        melFrame[m] = math.log(sum + 1e-9);
      }

      frames.add(melFrame);
    }

    return frames;
  }

  /// Build a mel filterbank matrix: [nMels][nFft/2+1].
  static List<List<double>> _buildMelFilterbank({
    required int nMels,
    required int nFft,
    required int sampleRate,
    required double fMin,
    required double fMax,
  }) {
    final nBins = nFft ~/ 2 + 1;

    // Convert Hz to Mel
    double hzToMel(double hz) => 2595.0 * math.log(1.0 + hz / 700.0) / math.ln10;
    double melToHz(double mel) => 700.0 * (math.pow(10.0, mel / 2595.0) - 1.0);

    final melMin = hzToMel(fMin);
    final melMax = hzToMel(fMax);

    // Linearly spaced mel points
    final melPoints = List<double>.generate(
      nMels + 2,
      (i) => melMin + i * (melMax - melMin) / (nMels + 1),
    );

    // Convert back to Hz then to FFT bin indices
    final binIndices = melPoints.map((mel) {
      final hz = melToHz(mel);
      return ((nFft + 1) * hz / sampleRate).floor();
    }).toList();

    // Build triangular filters
    final filterbank = List<List<double>>.generate(nMels, (m) {
      final row = List<double>.filled(nBins, 0.0);
      final left = binIndices[m];
      final center = binIndices[m + 1];
      final right = binIndices[m + 2];

      for (int j = left; j < center && j < nBins; j++) {
        if (center != left) {
          row[j] = (j - left) / (center - left);
        }
      }
      for (int j = center; j < right && j < nBins; j++) {
        if (right != center) {
          row[j] = (right - j) / (right - center);
        }
      }
      return row;
    });

    return filterbank;
  }

  /// Generate a Hann window of given length.
  static Float64List _hannWindow(int length) {
    final window = Float64List(length);
    for (int i = 0; i < length; i++) {
      window[i] = 0.5 * (1 - math.cos(2 * math.pi * i / (length - 1)));
    }
    return window;
  }
}
