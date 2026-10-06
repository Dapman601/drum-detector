import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';
import 'ffmpeg_service.dart';

/// Extracts mono PCM audio from a video file using FFmpeg.
class AudioExtractor {
  /// Extract audio from [videoPath] to a 22050 Hz mono WAV file.
  /// Returns the path to the extracted WAV and the raw Float32 samples.
  Future<AudioExtractionResult> extract(String videoPath) async {
    final tempDir = await getTemporaryDirectory();
    final wavPath = '${tempDir.path}/extracted_audio_${DateTime.now().millisecondsSinceEpoch}.wav';

    await FFmpegService.executeOrThrow([
      '-y', '-i', videoPath,
      '-vn', '-ac', '1', '-ar', '${AudioConstants.sampleRate}',
      '-sample_fmt', 's16', '-f', 'wav', wavPath,
    ]);

    // Read WAV file and parse PCM samples
    final wavFile = File(wavPath);
    final bytes = await wavFile.readAsBytes();
    final samples = _parseWavSamples(bytes);

    return AudioExtractionResult(
      wavPath: wavPath,
      samples: samples,
      sampleRate: AudioConstants.sampleRate,
    );
  }

  /// Parse 16-bit PCM samples from a WAV file's raw bytes.
  Float32List _parseWavSamples(Uint8List wavBytes) {
    // Find the 'data' chunk in the WAV header
    int dataOffset = -1;
    int dataSize = 0;
    for (int i = 0; i < wavBytes.length - 8; i++) {
      if (wavBytes[i] == 0x64 && // 'd'
          wavBytes[i + 1] == 0x61 && // 'a'
          wavBytes[i + 2] == 0x74 && // 't'
          wavBytes[i + 3] == 0x61) {
        // 'a'
        dataSize = wavBytes.buffer.asByteData().getUint32(i + 4, Endian.little);
        dataOffset = i + 8;
        break;
      }
    }

    if (dataOffset < 0) {
      throw Exception('Invalid WAV file: data chunk not found');
    }

    final numSamples = dataSize ~/ 2; // 16-bit = 2 bytes per sample
    final samples = Float32List(numSamples);
    final byteData = wavBytes.buffer.asByteData();

    for (int i = 0; i < numSamples; i++) {
      final offset = dataOffset + i * 2;
      if (offset + 1 >= wavBytes.length) break;
      final int16 = byteData.getInt16(offset, Endian.little);
      samples[i] = int16 / 32768.0; // Normalize to [-1.0, 1.0]
    }

    return samples;
  }

  /// Extract audio at a custom sample rate.
  Future<Float32List> extractAtRate(String videoPath, int targetRate) async {
    final tempDir = await getTemporaryDirectory();
    final wavPath =
        '${tempDir.path}/extracted_${targetRate}_${DateTime.now().millisecondsSinceEpoch}.wav';

    await FFmpegService.executeOrThrow([
      '-y', '-i', videoPath,
      '-vn', '-ac', '1', '-ar', '$targetRate',
      '-sample_fmt', 's16', '-f', 'wav', wavPath,
    ]);

    final wavFile = File(wavPath);
    final bytes = await wavFile.readAsBytes();
    final samples = _parseWavSamples(bytes);

    try {
      await wavFile.delete();
    } catch (_) {}

    return samples;
  }
}

class AudioExtractionResult {
  final String wavPath;
  final Float32List samples;
  final int sampleRate;

  const AudioExtractionResult({
    required this.wavPath,
    required this.samples,
    required this.sampleRate,
  });

  double get durationSeconds => samples.length / sampleRate;
}
