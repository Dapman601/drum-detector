import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../providers/pipeline_provider.dart';
import '../widgets/progress_indicator.dart';

class ProcessingScreen extends ConsumerWidget {
  const ProcessingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pipelineProvider);
    final theme = Theme.of(context);

    // Auto-navigate on completion
    ref.listen<PipelineState>(pipelineProvider, (prev, next) {
      if (next.isComplete) {
        Navigator.pushReplacementNamed(context, '/results');
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Processing'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated icon
              Icon(
                _stageIcon(state.stage),
                size: 64,
                color: state.hasError
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
              const SizedBox(height: 32),

              // Progress
              if (!state.hasError)
                PipelineProgressIndicator(
                  stage: state.stage,
                  progress: state.progress,
                  message: state.message,
                ),

              // Error display
              if (state.hasError) ...[
                Text(
                  'Processing Failed',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    state.error ?? 'Unknown error',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    ref.read(pipelineProvider.notifier).reset();
                    Navigator.pushReplacementNamed(context, '/');
                  },
                  child: const Text('Back to Home'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData _stageIcon(PipelineStage stage) {
    switch (stage) {
      case PipelineStage.extractingAudio:
        return Icons.audio_file;
      case PipelineStage.computingSpectrogram:
        return Icons.graphic_eq;
      case PipelineStage.detectingOnsets:
        return Icons.search;
      case PipelineStage.classifyingHits:
        return Icons.psychology;
      case PipelineStage.applyingEffects:
        return Icons.auto_fix_high;
      case PipelineStage.generatingReport:
        return Icons.summarize;
      case PipelineStage.complete:
        return Icons.check_circle;
      case PipelineStage.error:
        return Icons.error;
      default:
        return Icons.hourglass_empty;
    }
  }
}
