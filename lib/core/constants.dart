/// Audio processing constants matching the Python pipeline.
class AudioConstants {
  static const int sampleRate = 22050;
  static const int hopLength = 512;
  static const int nFft = 2048;
  static const int nMels = 40;
  static const double fMin = 20.0;
  static const double fMax = 11025.0; // sampleRate / 2

  /// Number of spectrogram frames per classification window (~100ms).
  static const int classificationWindowFrames = 8;

  /// CNN v4 context window: 15 mel frames centered on onset (~348ms).
  static const int cnnContextFrames = 15;
  static const int cnnContextHalf = 7;
}

/// Detection thresholds (defaults, user-adjustable).
/// Matched to Python backend values for consistency.
class DetectionDefaults {
  static const double kickThreshold = 0.65;
  static const double snareThreshold = 0.65;
  static const double onsetThresholdMultiplier = 3.5;
  static const double onsetThresholdOffset = 0.10;
  static const int minHitGapMs = 50;
  static const int onsetMedianWindowFrames = 11;

  /// Max onsets per second of audio (caps total candidates).
  static const double maxOnsetsPerSecond = 6.0;

  /// Minimum margin between winning drum class and "neither" probability.
  /// v4 CNN is trained with guitar/vocal negatives — lower margin is safe.
  static const double neitherMargin = 0.25;
}

/// Visual effect options.
enum KickEffect {
  zoomPunch, flashWhite, borderPulse, chromaticAberration, screenSlam,
  redFlash, vignetteSslam, saturationKill, strobeDark, gammaPunch,
}

enum SnareEffect {
  flashInvert, shake, colorTint, hardStrobe, horizontalGlitch, screenPop, burst,
  whiteFlash, blueTint, sharpenBlast, solarize, hueSpin,
}

/// Effect duration in seconds (~7 frames at 30fps).
const double effectDurationSec = 0.25;

/// Pipeline stage labels for progress display.
enum PipelineStage {
  idle('Idle'),
  extractingAudio('Extracting audio...'),
  computingSpectrogram('Computing spectrogram...'),
  detectingOnsets('Detecting onsets...'),
  classifyingHits('Classifying drum hits...'),
  applyingEffects('Applying video effects...'),
  generatingReport('Generating report...'),
  complete('Complete'),
  error('Error');

  final String label;
  const PipelineStage(this.label);
}
