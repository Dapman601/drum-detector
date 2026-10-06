import 'package:flutter/material.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';

import '../core/constants.dart';

/// Multi-stage progress bar with phase labels.
class PipelineProgressIndicator extends StatelessWidget {
  final PipelineStage stage;
  final double progress;
  final String message;

  const PipelineProgressIndicator({
    super.key,
    required this.stage,
    required this.progress,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Stage chips
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: _stages.map((s) {
            final isCurrent = s == stage;
            final isDone = s.index < stage.index;
            return Chip(
              label: Text(
                s.label,
                style: TextStyle(
                  fontSize: 11,
                  color: isCurrent
                      ? theme.colorScheme.onPrimary
                      : isDone
                          ? theme.colorScheme.onSurface.withOpacity(0.6)
                          : theme.colorScheme.onSurface.withOpacity(0.3),
                ),
              ),
              backgroundColor: isCurrent
                  ? theme.colorScheme.primary
                  : isDone
                      ? theme.colorScheme.primary.withOpacity(0.2)
                      : theme.colorScheme.surface,
              side: BorderSide.none,
              visualDensity: VisualDensity.compact,
            );
          }).toList(),
        ),
        const SizedBox(height: 20),

        // Progress bar
        LinearPercentIndicator(
          percent: progress.clamp(0.0, 1.0),
          lineHeight: 8,
          barRadius: const Radius.circular(4),
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          progressColor: theme.colorScheme.primary,
          animation: true,
          animateFromLastPercent: true,
          animationDuration: 300,
          padding: EdgeInsets.zero,
        ),
        const SizedBox(height: 12),

        // Percentage + message
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${(progress * 100).toStringAsFixed(0)}%',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Flexible(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static const _stages = [
    PipelineStage.extractingAudio,
    PipelineStage.computingSpectrogram,
    PipelineStage.detectingOnsets,
    PipelineStage.classifyingHits,
    PipelineStage.applyingEffects,
    PipelineStage.generatingReport,
  ];
}
