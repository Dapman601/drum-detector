import 'dart:math';

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../models/drum_hit.dart';

/// Real-time visual effects overlay that syncs to video playback position.
///
/// Instead of FFmpeg-baked effects (which hit the black screen bug),
/// this widget applies visual effects as Flutter widget overlays
/// synchronized to the player's current position.
///
/// Wraps the video widget in a [Stack] and applies transforms + overlays
/// for each active hit within the effect window.
class RealtimeEffectsOverlay extends StatefulWidget {
  /// The video widget to overlay effects on.
  final Widget child;

  /// All detected hits, sorted by time.
  final List<DrumHit> hits;

  /// Current playback position in seconds.
  final double positionSeconds;

  /// Whether the video is currently playing.
  final bool isPlaying;

  /// Which kick effect to display.
  final KickEffect kickEffect;

  /// Which snare effect to display.
  final SnareEffect snareEffect;

  const RealtimeEffectsOverlay({
    super.key,
    required this.child,
    required this.hits,
    required this.positionSeconds,
    required this.isPlaying,
    this.kickEffect = KickEffect.zoomPunch,
    this.snareEffect = SnareEffect.flashInvert,
  });

  @override
  State<RealtimeEffectsOverlay> createState() => _RealtimeEffectsOverlayState();
}

class _RealtimeEffectsOverlayState extends State<RealtimeEffectsOverlay>
    with SingleTickerProviderStateMixin {
  /// Effect window duration in seconds (~100ms = ~3 frames at 30fps).
  static const _effectWindowSec = effectDurationSec;

  @override
  Widget build(BuildContext context) {
    // Find active hits within the effect window of current position.
    final activeKick = _findActiveHit(DrumType.kick);
    final activeSnare = _findActiveHit(DrumType.snare);

    // Calculate effect intensity (1.0 at onset, decays to 0.0).
    final kickIntensity = activeKick != null
        ? _calcIntensity(activeKick)
        : 0.0;
    final snareIntensity = activeSnare != null
        ? _calcIntensity(activeSnare)
        : 0.0;

    Widget result = widget.child;

    // Apply kick effect transforms
    if (kickIntensity > 0) {
      result = _applyKickEffect(result, kickIntensity);
    }

    // Apply snare effect transforms
    if (snareIntensity > 0) {
      result = _applySnareEffect(result, snareIntensity);
    }

    // Build the overlay stack with labels and visual indicators
    return ClipRect(
      child: Stack(
        children: [
          result,

          // Kick overlay effects (flash, border)
          if (kickIntensity > 0) ..._buildKickOverlays(kickIntensity),

          // Snare overlay effects (tint, flash)
          if (snareIntensity > 0) ..._buildSnareOverlays(snareIntensity),

          // Hit labels
          if (kickIntensity > 0)
            Positioned(
              left: 12,
              bottom: 48,
              child: _HitLabel(
                text: 'KICK',
                color: const Color(0xFFEF4444),
                opacity: kickIntensity,
              ),
            ),
          if (snareIntensity > 0)
            Positioned(
              right: 12,
              bottom: 48,
              child: _HitLabel(
                text: 'SNARE',
                color: const Color(0xFF3B82F6),
                opacity: snareIntensity,
              ),
            ),
        ],
      ),
    );
  }

  /// Find the most recent active hit of a given type within the effect window.
  DrumHit? _findActiveHit(DrumType type) {
    final pos = widget.positionSeconds;

    // Binary search for efficiency with large hit lists.
    int lo = 0, hi = widget.hits.length - 1;
    DrumHit? best;

    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      if (widget.hits[mid].time <= pos) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }

    // Check hits near the current position.
    for (int i = max(0, hi - 2); i < min(widget.hits.length, hi + 4); i++) {
      final hit = widget.hits[i];
      if (hit.type != type) continue;
      final diff = pos - hit.time;
      if (diff >= 0 && diff < _effectWindowSec) {
        if (best == null || hit.time > best.time) {
          best = hit;
        }
      }
    }

    return best;
  }

  /// Calculate effect intensity: 1.0 at onset, linear decay to 0.0.
  double _calcIntensity(DrumHit hit) {
    final elapsed = widget.positionSeconds - hit.time;
    if (elapsed < 0 || elapsed >= _effectWindowSec) return 0.0;
    return 1.0 - (elapsed / _effectWindowSec);
  }

  /// Apply kick transform effect to the video widget.
  Widget _applyKickEffect(Widget child, double intensity) {
    switch (widget.kickEffect) {
      case KickEffect.zoomPunch:
        // Scale 1.0 → 1.08 → 1.0 based on intensity
        final scale = 1.0 + (0.08 * intensity);
        return Transform.scale(scale: scale, child: child);

      case KickEffect.flashWhite:
        // No transform needed, overlay handles the flash
        return child;

      case KickEffect.borderPulse:
        // No transform needed, overlay handles the border
        return child;

      case KickEffect.chromaticAberration:
        // Chromatic aberration: shift the whole video slightly + overlays
        // simulate RGB fringing
        final shift = 6.0 * intensity;
        return Transform.translate(
          offset: Offset(shift, 0),
          child: child,
        );

      case KickEffect.screenSlam:
        // Video slams down then bounces back
        final drop = 20.0 * intensity;
        final scale = 1.0 + (0.05 * intensity);
        return Transform.translate(
          offset: Offset(0, drop),
          child: Transform.scale(scale: scale, child: child),
        );

      case KickEffect.redFlash:
        // No transform — overlay handles the red tint
        return child;

      case KickEffect.vignetteSslam:
        // Slight scale-in to emphasize vignette
        final scale = 1.0 + (0.03 * intensity);
        return Transform.scale(scale: scale, child: child);

      case KickEffect.saturationKill:
        // No transform — overlay handles grayscale
        return child;

      case KickEffect.strobeDark:
        // No transform — overlay handles strobe
        return child;

      case KickEffect.gammaPunch:
        // Slight zoom for impact
        final scale = 1.0 + (0.04 * intensity);
        return Transform.scale(scale: scale, child: child);
    }
  }

  /// Apply snare transform effect to the video widget.
  Widget _applySnareEffect(Widget child, double intensity) {
    switch (widget.snareEffect) {
      case SnareEffect.flashInvert:
        // No transform — overlay handles inversion
        return child;

      case SnareEffect.shake:
        // Random ±20px offset that decays
        final rng = Random(
            (widget.positionSeconds * 1000).toInt());
        final dx = (rng.nextDouble() * 2 - 1) * 20 * intensity;
        final dy = (rng.nextDouble() * 2 - 1) * 20 * intensity;
        return Transform.translate(offset: Offset(dx, dy), child: child);

      case SnareEffect.colorTint:
        // No transform needed, overlay handles the tint
        return child;

      case SnareEffect.hardStrobe:
        // No transform needed, overlay handles the strobe
        return child;

      case SnareEffect.horizontalGlitch:
        // Horizontal shift + handled by overlays
        final rng = Random((widget.positionSeconds * 1000).toInt());
        final dx = (rng.nextDouble() * 2 - 1) * 12 * intensity;
        return Transform.translate(
          offset: Offset(dx, 0),
          child: child,
        );

      case SnareEffect.screenPop:
        // Opposite of screen slam: video pops UP + slight scale down
        final lift = -25.0 * intensity;
        final scale = 1.0 - (0.04 * intensity);
        return Transform.translate(
          offset: Offset(0, lift),
          child: Transform.scale(scale: scale, child: child),
        );

      case SnareEffect.burst:
        // Hard scale punch on impact
        final scale = 1.0 + (0.12 * intensity);
        return Transform.scale(scale: scale, child: child);

      case SnareEffect.whiteFlash:
        // No transform — overlay handles bright flash
        return child;

      case SnareEffect.blueTint:
        // No transform — overlay handles blue tint
        return child;

      case SnareEffect.sharpenBlast:
        // Slight zoom for sharpness emphasis
        final scale = 1.0 + (0.06 * intensity);
        return Transform.scale(scale: scale, child: child);

      case SnareEffect.solarize:
        // No transform — overlay handles psychedelic look
        return child;

      case SnareEffect.hueSpin:
        // No transform — overlay handles hue rotation
        return child;
    }
  }

  /// Build kick-specific overlay widgets.
  List<Widget> _buildKickOverlays(double intensity) {
    switch (widget.kickEffect) {
      case KickEffect.zoomPunch:
        // Zoom is handled by Transform.scale, no overlay needed
        return [];

      case KickEffect.flashWhite:
        return [
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Colors.white.withOpacity(0.5 * intensity),
              ),
            ),
          ),
        ];

      case KickEffect.borderPulse:
        return [
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withOpacity(intensity),
                    width: 6,
                  ),
                ),
              ),
            ),
          ),
        ];

      case KickEffect.chromaticAberration:
        // RGB fringe overlays: red on left edge, cyan on right edge
        final fringe = 10.0 * intensity;
        return [
          // Red fringe — left side
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: fringe * 4,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.red.withOpacity(0.6 * intensity),
                      Colors.red.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Cyan fringe — right side
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: fringe * 4,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.cyanAccent.withOpacity(0.0),
                      Colors.cyanAccent.withOpacity(0.6 * intensity),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Full contrast/saturation boost overlay
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Colors.white.withOpacity(0.1 * intensity),
              ),
            ),
          ),
        ];

      case KickEffect.screenSlam:
        // Dark flash + red bottom edge on slam impact
        return [
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Colors.black.withOpacity(0.35 * intensity),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 8,
            child: IgnorePointer(
              child: Container(
                color: Colors.redAccent.withOpacity(0.7 * intensity),
              ),
            ),
          ),
        ];

      case KickEffect.redFlash:
        // Dark red tint overlay
        return [
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: const Color(0xFFCC0000).withOpacity(0.4 * intensity),
              ),
            ),
          ),
        ];

      case KickEffect.vignetteSslam:
        // Radial gradient: dark edges, transparent center
        return [
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.7 * intensity),
                    ],
                    stops: const [0.3, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ];

      case KickEffect.saturationKill:
        // Grayscale overlay using color matrix
        return [
          Positioned.fill(
            child: IgnorePointer(
              child: ColorFiltered(
                colorFilter: ColorFilter.matrix(<double>[
                  // Desaturation matrix blended with identity
                  1 - 0.7 * intensity, 0.7 * intensity * 0.3, 0.7 * intensity * 0.1, 0, 0,
                  0.7 * intensity * 0.3, 1 - 0.7 * intensity, 0.7 * intensity * 0.1, 0, 0,
                  0.7 * intensity * 0.3, 0.7 * intensity * 0.3, 1 - 0.4 * intensity, 0, 0,
                  0, 0, 0, 1, 0,
                ]),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
          // Slight dark overlay for impact
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Colors.black.withOpacity(0.15 * intensity),
              ),
            ),
          ),
        ];

      case KickEffect.strobeDark:
        // Flickering dark overlay (alternates based on position)
        final flicker = ((widget.positionSeconds * 30).toInt() % 2 == 0)
            ? intensity
            : intensity * 0.3;
        return [
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Colors.black.withOpacity(0.5 * flicker),
              ),
            ),
          ),
        ];

      case KickEffect.gammaPunch:
        // Washed-out bright overlay (overexposure feel)
        return [
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Colors.white.withOpacity(0.45 * intensity),
              ),
            ),
          ),
        ];
    }
  }

  /// Build snare-specific overlay widgets.
  List<Widget> _buildSnareOverlays(double intensity) {
    switch (widget.snareEffect) {
      case SnareEffect.flashInvert:
        return [
          Positioned.fill(
            child: IgnorePointer(
              child: ColorFiltered(
                colorFilter: ColorFilter.matrix(<double>[
                  // Inversion matrix blended with identity based on intensity
                  1 - 2 * intensity, 0, 0, 0, 255 * intensity,
                  0, 1 - 2 * intensity, 0, 0, 255 * intensity,
                  0, 0, 1 - 2 * intensity, 0, 255 * intensity,
                  0, 0, 0, 1, 0,
                ]),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
          // Semi-transparent color flash as visible alternative
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Colors.white.withOpacity(0.3 * intensity),
              ),
            ),
          ),
        ];

      case SnareEffect.shake:
        // Shake is handled by Transform.translate, no overlay needed
        return [];

      case SnareEffect.colorTint:
        return [
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: const Color(0xFF00BCD4) // Cyan tint
                    .withOpacity(0.3 * intensity),
              ),
            ),
          ),
        ];

      case SnareEffect.hardStrobe:
        // Full bright white flash at high opacity
        return [
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Colors.white.withOpacity(0.7 * intensity),
              ),
            ),
          ),
        ];

      case SnareEffect.horizontalGlitch:
        // Glitch scanline bars + color distortion overlay
        final rng = Random((widget.positionSeconds * 1000).toInt());
        return [
          // Random horizontal glitch bars
          for (int i = 0; i < 5; i++)
            if (rng.nextDouble() > 0.3)
              Positioned(
                left: 0,
                right: 0,
                top: rng.nextDouble() * 300,
                height: 4 + rng.nextDouble() * 12,
                child: IgnorePointer(
                  child: Container(
                    color: (i.isEven ? Colors.cyanAccent : Colors.white)
                        .withOpacity(0.5 * intensity),
                  ),
                ),
              ),
          // Full cyan tint
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: const Color(0xFF00FFFF).withOpacity(0.15 * intensity),
              ),
            ),
          ),
        ];

      case SnareEffect.screenPop:
        // Bright flash + blue top edge glow
        return [
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Colors.white.withOpacity(0.25 * intensity),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 8,
            child: IgnorePointer(
              child: Container(
                color: const Color(0xFF3B82F6).withOpacity(0.8 * intensity),
              ),
            ),
          ),
        ];

      case SnareEffect.burst:
        // Radial shockwave expanding from center
        final progress = 1.0 - intensity;
        return [
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Colors.white.withOpacity(0.55 * intensity),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(
                  width: progress * 1200,
                  height: progress * 1200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(intensity),
                      width: 6 + (1 - progress) * 14,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(
                  width: 100 + progress * 400,
                  height: 100 + progress * 400,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withOpacity(intensity * 0.8),
                        const Color(0xFF3B82F6).withOpacity(intensity * 0.3),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.4, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ];

      case SnareEffect.whiteFlash:
        // Bright white flash
        return [
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Colors.white.withOpacity(0.6 * intensity),
              ),
            ),
          ),
        ];

      case SnareEffect.blueTint:
        // Cool blue tint overlay
        return [
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: const Color(0xFF1E90FF).withOpacity(0.4 * intensity),
              ),
            ),
          ),
        ];

      case SnareEffect.sharpenBlast:
        // Sharp white flash + bright edge highlight
        return [
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Colors.white.withOpacity(0.35 * intensity),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withOpacity(0.8 * intensity),
                    width: 3,
                  ),
                ),
              ),
            ),
          ),
        ];

      case SnareEffect.solarize:
        // Psychedelic warm overlay (yellow-magenta)
        return [
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.yellow.withOpacity(0.3 * intensity),
                      Colors.purpleAccent.withOpacity(0.3 * intensity),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Colors.white.withOpacity(0.2 * intensity),
              ),
            ),
          ),
        ];

      case SnareEffect.hueSpin:
        // Rotating hue: green-magenta overlay
        return [
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: Colors.green.withOpacity(0.3 * intensity),
              ),
            ),
          ),
        ];
    }
  }
}

/// Animated hit label that fades with intensity.
class _HitLabel extends StatelessWidget {
  final String text;
  final Color color;
  final double opacity;

  const _HitLabel({
    required this.text,
    required this.color,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.85),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.4),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}
