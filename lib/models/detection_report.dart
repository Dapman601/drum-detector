import 'dart:convert';
import 'drum_hit.dart';

/// Full detection report for a processed video.
class DetectionReport {
  final String inputFile;
  final String outputFile;
  final double durationSeconds;
  final double fps;
  final List<DrumHit> kicks;
  final List<DrumHit> snares;
  final Map<String, dynamic> settings;

  const DetectionReport({
    required this.inputFile,
    required this.outputFile,
    required this.durationSeconds,
    required this.fps,
    required this.kicks,
    required this.snares,
    this.settings = const {},
  });

  List<DrumHit> get allHits => [...kicks, ...snares]..sort((a, b) => a.time.compareTo(b.time));

  int get totalHits => kicks.length + snares.length;

  Map<String, dynamic> toJson() => {
        'input_file': inputFile,
        'output_file': outputFile,
        'duration_seconds': durationSeconds,
        'fps': fps,
        'detections': {
          'kicks': kicks.map((h) => h.toJson()).toList(),
          'snares': snares.map((h) => h.toJson()).toList(),
        },
        'settings': settings,
      };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());
}
