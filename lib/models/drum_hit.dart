/// A single detected drum hit.
class DrumHit {
  final double time; // seconds
  final DrumType type;
  final double confidence; // 0.0–1.0
  final int frame; // video frame number

  const DrumHit({
    required this.time,
    required this.type,
    required this.confidence,
    required this.frame,
  });

  Map<String, dynamic> toJson() => {
        'time': time,
        'type': type.name,
        'confidence': confidence,
        'frame': frame,
      };

  factory DrumHit.fromJson(Map<String, dynamic> json) => DrumHit(
        time: (json['time'] as num).toDouble(),
        type: DrumType.values.byName(json['type'] as String),
        confidence: (json['confidence'] as num).toDouble(),
        frame: json['frame'] as int,
      );

  @override
  String toString() =>
      'DrumHit(${type.name} @ ${time.toStringAsFixed(3)}s, '
      'conf=${confidence.toStringAsFixed(2)}, frame=$frame)';
}

enum DrumType { kick, snare }
