import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

/// Extracts 28-dimensional feature vectors from audio windows for drum
/// classification, matching the Python `feature_extractor.py` pipeline.
///
/// Feature layout (28 total):
///  0     spectral_centroid
///  1     spectral_rolloff (85 %)
///  2     spectral_bandwidth
///  3     spectral_flatness
///  4     zero_crossing_rate
///  5     rms_energy
///  6     attack_time (ms)
///  7-19  mfcc_1 … mfcc_13
///  20    low_band_energy   (20-300 Hz)
///  21    mid_band_energy   (300-2000 Hz)
///  22    high_band_energy  (2000-8000 Hz)
///  23    hihat_band_energy (8000-16000 Hz)
///  24    low_to_total_ratio
///  25    high_to_total_ratio
///  26    spectral_flux
///  27    crest_factor
class FeatureExtractor {
  static const int _nFft = 2048;
  static const int _hopLength = 512;
  static const int _nMfcc = 13;
  static const int _nMels = 40; // for MFCC mel filterbank

  // Frequency bands (Hz)
  static const _lowBand = (20.0, 300.0);
  static const _midBand = (300.0, 2000.0);
  static const _highBand = (2000.0, 8000.0);
  static const _hihatBand = (8000.0, 16000.0);

  late final FFT _fft;
  late final List<List<double>> _melFilterbank;
  late final Float64List _hannWindow;
  late final List<List<double>> _dctMatrix; // [_nMfcc][_nMels]

  FeatureExtractor() {
    _fft = FFT(_nFft);
    _hannWindow = _buildHannWindow(_nFft);
    _melFilterbank = _buildMelFilterbank(
      nMels: _nMels,
      nFft: _nFft,
      sampleRate: 22050,
      fMin: 20.0,
      fMax: 11025.0,
    );
    _dctMatrix = _buildDctMatrix(_nMfcc, _nMels);
  }

  /// Extract 28-dim feature vector from a mono audio window.
  ///
  /// [audioWindow] raw PCM float samples (typically 50 ms @ 22050 Hz ≈ 1102 samples).
  /// [sampleRate] sample rate in Hz.
  List<double> extract(Float32List audioWindow, int sampleRate) {
    // Normalise to [-1, 1]
    final audio = Float64List(audioWindow.length);
    double maxAbs = 0.0;
    for (int i = 0; i < audioWindow.length; i++) {
      final v = audioWindow[i].abs();
      if (v > maxAbs) maxAbs = v;
    }
    if (maxAbs > 0) {
      for (int i = 0; i < audioWindow.length; i++) {
        audio[i] = audioWindow[i] / maxAbs;
      }
    }

    // --- Compute power spectrum (single frame, zero-padded to nFft) ---
    final windowed = Float64List(_nFft);
    final copyLen = math.min(audio.length, _nFft);
    for (int i = 0; i < copyLen; i++) {
      windowed[i] = audio[i] * _hannWindow[i];
    }
    final spectrum = _fft.realFft(windowed);
    final nBins = _nFft ~/ 2 + 1;
    final power = Float64List(nBins);
    for (int j = 0; j < nBins; j++) {
      final re = spectrum[j].x;
      final im = spectrum[j].y;
      power[j] = re * re + im * im;
    }

    final features = <double>[];

    // ---- 1-4: Spectral features ----
    features.add(_spectralCentroid(power, sampleRate));
    features.add(_spectralRolloff(power, sampleRate, 0.85));
    features.add(_spectralBandwidth(power, sampleRate, features[0]));
    features.add(_spectralFlatness(power));

    // ---- 5: Zero crossing rate ----
    features.add(_zeroCrossingRate(audio));

    // ---- 6: RMS energy ----
    features.add(_rmsEnergy(audio));

    // ---- 7: Attack time (ms) ----
    features.add(_attackTime(audio, sampleRate));

    // ---- 8-20: MFCCs (13) ----
    final mfccs = _computeMfccs(power);
    features.addAll(mfccs);

    // ---- 21-24: Band energies (FFT-based bandpass) ----
    final lowE = _bandEnergy(power, sampleRate, _lowBand.$1, _lowBand.$2);
    final midE = _bandEnergy(power, sampleRate, _midBand.$1, _midBand.$2);
    final highE = _bandEnergy(power, sampleRate, _highBand.$1, _highBand.$2);
    final hihatE = _bandEnergy(power, sampleRate, _hihatBand.$1, _hihatBand.$2);
    features.add(lowE);
    features.add(midE);
    features.add(highE);
    features.add(hihatE);

    // ---- 25-26: Band ratios ----
    final totalE = lowE + midE + highE + hihatE + 1e-10;
    features.add(lowE / totalE);
    features.add(highE / totalE);

    // ---- 27: Spectral flux ----
    features.add(_spectralFlux(audio, sampleRate));

    // ---- 28: Crest factor ----
    features.add(_crestFactor(audio));

    return features;
  }

  // --------------- Spectral features ---------------

  double _spectralCentroid(Float64List power, int sr) {
    final nBins = power.length;
    double numSum = 0.0, denSum = 0.0;
    for (int j = 0; j < nBins; j++) {
      final freq = j * sr / _nFft;
      numSum += freq * power[j];
      denSum += power[j];
    }
    return denSum > 0 ? numSum / denSum : 0.0;
  }

  double _spectralRolloff(Float64List power, int sr, double rollPercent) {
    double total = 0.0;
    for (final p in power) {
      total += p;
    }
    final threshold = rollPercent * total;
    double cumulative = 0.0;
    for (int j = 0; j < power.length; j++) {
      cumulative += power[j];
      if (cumulative >= threshold) {
        return j * sr / _nFft;
      }
    }
    return sr / 2.0;
  }

  double _spectralBandwidth(Float64List power, int sr, double centroid) {
    double numSum = 0.0, denSum = 0.0;
    for (int j = 0; j < power.length; j++) {
      final freq = j * sr / _nFft;
      final diff = freq - centroid;
      numSum += diff * diff * power[j];
      denSum += power[j];
    }
    return denSum > 0 ? math.sqrt(numSum / denSum) : 0.0;
  }

  double _spectralFlatness(Float64List power) {
    final n = power.length;
    double logSum = 0.0, arithSum = 0.0;
    int count = 0;
    for (int j = 0; j < n; j++) {
      final p = power[j] + 1e-10;
      logSum += math.log(p);
      arithSum += p;
      count++;
    }
    if (count == 0 || arithSum == 0) return 0.0;
    final geometricMean = math.exp(logSum / count);
    final arithmeticMean = arithSum / count;
    return geometricMean / arithmeticMean;
  }

  // --------------- Temporal features ---------------

  double _zeroCrossingRate(Float64List audio) {
    if (audio.length < 2) return 0.0;
    int crossings = 0;
    for (int i = 1; i < audio.length; i++) {
      if ((audio[i] >= 0) != (audio[i - 1] >= 0)) crossings++;
    }
    return crossings / (audio.length - 1);
  }

  double _rmsEnergy(Float64List audio) {
    if (audio.isEmpty) return 0.0;
    double sum = 0.0;
    for (final s in audio) {
      sum += s * s;
    }
    return math.sqrt(sum / audio.length);
  }

  double _attackTime(Float64List audio, int sr) {
    // Amplitude envelope
    final envelope = Float64List(audio.length);
    for (int i = 0; i < audio.length; i++) {
      envelope[i] = audio[i].abs();
    }

    // Smooth envelope
    int windowSize = math.min(audio.length ~/ 20, 100);
    if (windowSize > 1) {
      final smoothed = Float64List(audio.length);
      final halfW = windowSize ~/ 2;
      for (int i = 0; i < audio.length; i++) {
        double sum = 0.0;
        int count = 0;
        for (int j = math.max(0, i - halfW);
            j < math.min(audio.length, i + halfW + 1);
            j++) {
          sum += envelope[j];
          count++;
        }
        smoothed[i] = sum / count;
      }
      for (int i = 0; i < audio.length; i++) {
        envelope[i] = smoothed[i];
      }
    }

    // Find peak
    int peakIdx = 0;
    double peakVal = 0.0;
    for (int i = 0; i < envelope.length; i++) {
      if (envelope[i] > peakVal) {
        peakVal = envelope[i];
        peakIdx = i;
      }
    }

    // Find onset (10% of peak before peak)
    final threshold = 0.1 * peakVal;
    int onsetIdx = 0;
    for (int i = 0; i < peakIdx; i++) {
      if (envelope[i] > threshold) {
        onsetIdx = i;
        break;
      }
    }

    return ((peakIdx - onsetIdx) / sr) * 1000.0;
  }

  // --------------- MFCCs ---------------

  /// Compute 13 MFCCs from the power spectrum of a single frame.
  List<double> _computeMfccs(Float64List power) {
    // Apply mel filterbank → log → DCT
    final nBins = power.length;
    final melEnergies = Float64List(_nMels);
    for (int m = 0; m < _nMels; m++) {
      double sum = 0.0;
      for (int j = 0; j < nBins && j < _melFilterbank[m].length; j++) {
        sum += _melFilterbank[m][j] * power[j];
      }
      melEnergies[m] = math.log(sum + 1e-9);
    }

    // DCT-II to get MFCCs
    final mfccs = List<double>.filled(_nMfcc, 0.0);
    for (int k = 0; k < _nMfcc; k++) {
      double sum = 0.0;
      for (int n = 0; n < _nMels; n++) {
        sum += _dctMatrix[k][n] * melEnergies[n];
      }
      mfccs[k] = sum;
    }
    return mfccs;
  }

  // --------------- Band energy (FFT-based) ---------------

  /// Sum of power spectrum bins within [lowHz, highHz].
  double _bandEnergy(Float64List power, int sr, double lowHz, double highHz) {
    final binLow = (lowHz * _nFft / sr).floor();
    final binHigh = (highHz * _nFft / sr).ceil();
    double energy = 0.0;
    for (int j = math.max(0, binLow);
        j < math.min(power.length, binHigh);
        j++) {
      energy += power[j];
    }
    return energy;
  }

  // --------------- Spectral flux ---------------

  double _spectralFlux(Float64List audio, int sr) {
    // Compute STFT and sum positive spectral differences across frames
    final nBins = _nFft ~/ 2 + 1;
    final nFrames = ((audio.length - _nFft) / _hopLength).floor() + 1;
    if (nFrames < 2) return 0.0;

    Float64List? prevMag;
    double totalFlux = 0.0;
    int fluxFrames = 0;

    for (int i = 0; i < nFrames; i++) {
      final start = i * _hopLength;
      if (start + _nFft > audio.length) break;

      final windowed = Float64List(_nFft);
      for (int j = 0; j < _nFft; j++) {
        windowed[j] = audio[start + j] * _hannWindow[j];
      }
      final spec = _fft.realFft(windowed);

      final mag = Float64List(nBins);
      for (int j = 0; j < nBins; j++) {
        mag[j] = math.sqrt(spec[j].x * spec[j].x + spec[j].y * spec[j].y);
      }

      if (prevMag != null) {
        double frameFlux = 0.0;
        for (int j = 0; j < nBins; j++) {
          final diff = mag[j] - prevMag[j];
          if (diff > 0) frameFlux += diff;
        }
        totalFlux += frameFlux;
        fluxFrames++;
      }
      prevMag = mag;
    }

    return fluxFrames > 0 ? totalFlux / fluxFrames : 0.0;
  }

  // --------------- Crest factor ---------------

  double _crestFactor(Float64List audio) {
    double peak = 0.0;
    double sumSq = 0.0;
    for (final s in audio) {
      final a = s.abs();
      if (a > peak) peak = a;
      sumSq += s * s;
    }
    final rms = audio.isNotEmpty ? math.sqrt(sumSq / audio.length) : 0.0;
    return rms > 0 ? peak / rms : 0.0;
  }

  // --------------- Build helpers ---------------

  static Float64List _buildHannWindow(int length) {
    final w = Float64List(length);
    for (int i = 0; i < length; i++) {
      w[i] = 0.5 * (1 - math.cos(2 * math.pi * i / (length - 1)));
    }
    return w;
  }

  static List<List<double>> _buildMelFilterbank({
    required int nMels,
    required int nFft,
    required int sampleRate,
    required double fMin,
    required double fMax,
  }) {
    final nBins = nFft ~/ 2 + 1;

    double hzToMel(double hz) =>
        2595.0 * math.log(1.0 + hz / 700.0) / math.ln10;
    double melToHz(double mel) =>
        700.0 * (math.pow(10.0, mel / 2595.0) - 1.0);

    final melMin = hzToMel(fMin);
    final melMax = hzToMel(fMax);

    final melPoints = List<double>.generate(
      nMels + 2,
      (i) => melMin + i * (melMax - melMin) / (nMels + 1),
    );

    final binIndices = melPoints.map((mel) {
      final hz = melToHz(mel);
      return ((nFft + 1) * hz / sampleRate).floor();
    }).toList();

    return List<List<double>>.generate(nMels, (m) {
      final row = List<double>.filled(nBins, 0.0);
      final left = binIndices[m];
      final center = binIndices[m + 1];
      final right = binIndices[m + 2];

      for (int j = left; j < center && j < nBins; j++) {
        if (center != left) row[j] = (j - left) / (center - left);
      }
      for (int j = center; j < right && j < nBins; j++) {
        if (right != center) row[j] = (right - j) / (right - center);
      }
      return row;
    });
  }

  /// Build DCT-II matrix [nMfcc × nMels].
  static List<List<double>> _buildDctMatrix(int nMfcc, int nMels) {
    return List<List<double>>.generate(nMfcc, (k) {
      return List<double>.generate(nMels, (n) {
        return math.cos(math.pi * k * (n + 0.5) / nMels);
      });
    });
  }
}
