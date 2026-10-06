import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/drum_hit.dart';
import '../providers/pipeline_provider.dart';

class ReportScreen extends ConsumerWidget {
  const ReportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pipelineProvider);
    final report = state.report;
    final theme = Theme.of(context);

    if (report == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Report')),
        body: const Center(child: Text('No report available')),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Detection Report'),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Kicks (${report.kicks.length})'),
              Tab(text: 'Snares (${report.snares.length})'),
            ],
            indicatorColor: theme.colorScheme.primary,
          ),
        ),
        body: TabBarView(
          children: [
            _HitList(
              hits: report.kicks,
              color: AppTheme.kickColor,
            ),
            _HitList(
              hits: report.snares,
              color: AppTheme.snareColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _HitList extends StatelessWidget {
  final List<DrumHit> hits;
  final Color color;

  const _HitList({required this.hits, required this.color});

  @override
  Widget build(BuildContext context) {
    if (hits.isEmpty) {
      return const Center(child: Text('No detections'));
    }

    final theme = Theme.of(context);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: hits.length,
      itemBuilder: (context, index) {
        final hit = hits[index];
        final minutes = (hit.time / 60).floor();
        final seconds = hit.time % 60;

        return ListTile(
          leading: Container(
            width: 8,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          title: Text(
            '$minutes:${seconds.toStringAsFixed(3).padLeft(6, '0')}',
            style: theme.textTheme.bodyLarge?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: Text('Frame ${hit.frame}'),
          trailing: SizedBox(
            width: 120,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: hit.confidence,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(
                        color.withOpacity(0.8),
                      ),
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(hit.confidence * 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
