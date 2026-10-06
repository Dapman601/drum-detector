import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/pipeline_provider.dart';
import '../widgets/settings_panel.dart';
import '../widgets/upload_zone.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _selectedPath;

  void _startProcessing() {
    if (_selectedPath == null) return;

    ref.read(pipelineProvider.notifier).process(_selectedPath!);
    Navigator.pushNamed(context, '/processing');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Drum Detector'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Text(
                'Audio-Reactive Video Analysis',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Detect drum hits and apply visual effects',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Upload zone
              UploadZone(
                selectedPath: _selectedPath,
                onFilePicked: (path) => setState(() => _selectedPath = path),
              ),
              const SizedBox(height: 24),

              // Effect settings
              const SettingsPanel(),
              const SizedBox(height: 16),

              // Process button
              ElevatedButton.icon(
                onPressed: _selectedPath != null ? _startProcessing : null,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Process Video'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
