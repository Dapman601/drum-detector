import '../core/constants.dart';

/// User-adjustable processing settings.
class ProcessingSettings {
  final double kickThreshold;
  final double snareThreshold;
  final KickEffect kickEffect;
  final SnareEffect snareEffect;

  const ProcessingSettings({
    this.kickThreshold = DetectionDefaults.kickThreshold,
    this.snareThreshold = DetectionDefaults.snareThreshold,
    this.kickEffect = KickEffect.screenSlam,
    this.snareEffect = SnareEffect.burst,
  });

  ProcessingSettings copyWith({
    double? kickThreshold,
    double? snareThreshold,
    KickEffect? kickEffect,
    SnareEffect? snareEffect,
  }) {
    return ProcessingSettings(
      kickThreshold: kickThreshold ?? this.kickThreshold,
      snareThreshold: snareThreshold ?? this.snareThreshold,
      kickEffect: kickEffect ?? this.kickEffect,
      snareEffect: snareEffect ?? this.snareEffect,
    );
  }
}
