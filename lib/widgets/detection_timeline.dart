import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/drum_hit.dart';

/// Horizontal timeline showing kick (red) and snare (blue) markers
/// with a playhead synced to the video player.
class DetectionTimeline extends StatelessWidget {
  final List<DrumHit> hits;
  final double durationSeconds;
  final double playheadSeconds;
  final ValueChanged<double>? onSeek;

  const DetectionTimeline({
    super.key,
    required this.hits,
    required this.durationSeconds,
    this.playheadSeconds = 0,
    this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: _buildTimeline(context, playheadSeconds),
    );
  }

  Widget _buildTimeline(BuildContext context, double playheadSec) {
    return GestureDetector(
      onTapDown: (details) {
        if (onSeek != null && durationSeconds > 0) {
          final box = context.findRenderObject() as RenderBox;
          final fraction = details.localPosition.dx / box.size.width;
          onSeek!(fraction.clamp(0.0, 1.0) * durationSeconds);
        }
      },
      child: CustomPaint(
        painter: _TimelinePainter(
          hits: hits,
          durationSeconds: durationSeconds,
          playheadSeconds: playheadSec,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  final List<DrumHit> hits;
  final double durationSeconds;
  final double playheadSeconds;

  _TimelinePainter({
    required this.hits,
    required this.durationSeconds,
    required this.playheadSeconds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (durationSeconds <= 0) return;

    final bgPaint = Paint()
      ..color = const Color(0xFF1A1A2E)
      ..style = PaintingStyle.fill;

    // Background bar
    final barRect = Rect.fromLTWH(0, 16, size.width, 24);
    canvas.drawRRect(
      RRect.fromRectAndRadius(barRect, const Radius.circular(4)),
      bgPaint,
    );

    // Hit markers
    for (final hit in hits) {
      final x = (hit.time / durationSeconds) * size.width;
      final color =
          hit.type == DrumType.kick ? AppTheme.kickColor : AppTheme.snareColor;
      final markerPaint = Paint()
        ..color = color.withOpacity(0.8)
        ..strokeWidth = 2;
      canvas.drawLine(
        Offset(x, 12),
        Offset(x, 44),
        markerPaint,
      );
    }

    // Playhead
    final playheadX = (playheadSeconds / durationSeconds) * size.width;
    final playheadPaint = Paint()
      ..color = AppTheme.playheadColor
      ..strokeWidth = 2.5;
    canvas.drawLine(
      Offset(playheadX, 8),
      Offset(playheadX, 48),
      playheadPaint,
    );

    // Playhead triangle
    final trianglePath = Path()
      ..moveTo(playheadX - 5, 8)
      ..lineTo(playheadX + 5, 8)
      ..lineTo(playheadX, 14)
      ..close();
    canvas.drawPath(
      trianglePath,
      Paint()..color = AppTheme.playheadColor,
    );
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.playheadSeconds != playheadSeconds ||
      old.hits != hits ||
      old.durationSeconds != durationSeconds;
}
