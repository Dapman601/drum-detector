import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../core/theme.dart';
import '../models/drum_hit.dart';
import '../providers/pipeline_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/realtime_effects_overlay.dart';
import '../widgets/stat_card.dart';

class ResultsScreen extends ConsumerStatefulWidget {
  const ResultsScreen({super.key});

  @override
  ConsumerState<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends ConsumerState<ResultsScreen> {
  Player? _player;
  VideoController? _videoController;
  String? _videoError;
  bool _ready = false;

  // For syncing hit overlay + timeline with playback position
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _playingSub;
  Timer? _effectTimer;

  // Stopwatch approach: wall-clock interpolation for smooth effect triggering.
  // media_kit updates position at ~10Hz; the stopwatch fills the gaps.
  final Stopwatch _stopwatch = Stopwatch();
  Duration _syncPosition = Duration.zero; // player position at last sync
  int _syncCounter = 0; // re-sync every N ticks

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initVideo());
  }

  Future<void> _initVideo() async {
    final state = ref.read(pipelineProvider);
    // Play the ORIGINAL video (not FFmpeg-processed) to avoid black screen bug.
    // Visual effects are applied as Flutter widget overlays in real time.
    final path = state.videoPath;
    if (path == null) {
      setState(() => _videoError = 'No video path');
      return;
    }

    debugPrint('[ResultsScreen] Playing original video: $path');

    final file = File(path);
    if (!file.existsSync()) {
      debugPrint('[ResultsScreen] ERROR: File not found');
      setState(() => _videoError = 'File not found: $path');
      return;
    }
    debugPrint('[ResultsScreen] File exists, size: ${file.lengthSync()} bytes');

    try {
      _player = Player(
        configuration: const PlayerConfiguration(
          logLevel: MPVLogLevel.v,
        ),
      );
      _videoController = VideoController(
        _player!,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: true,
          width: 1280,
          height: 720,
        ),
      );

      _player!.stream.error.listen((error) {
        debugPrint('[ResultsScreen] Player error stream: $error');
      });
      _player!.stream.log.listen((log) {
        debugPrint('[mpv/${log.prefix}] ${log.level}: ${log.text}');
      });
      _player!.stream.width.listen((w) {
        debugPrint('[ResultsScreen] Video width: $w');
      });
      _player!.stream.height.listen((h) {
        debugPrint('[ResultsScreen] Video height: $h');
      });

      _positionSub = _player!.stream.position.listen((pos) {
        // Update sync point for stopwatch interpolation.
        _syncPosition = pos;
        _stopwatch.reset();
        _stopwatch.start();
        if (mounted && !_playing) setState(() => _position = pos);
      });
      _durationSub = _player!.stream.duration.listen((dur) {
        debugPrint('[ResultsScreen] Duration: $dur');
        if (mounted) setState(() => _duration = dur);
      });
      _playingSub = _player!.stream.playing.listen((playing) {
        if (mounted) {
          if (playing) {
            // Starting playback: sync stopwatch to current player position.
            _syncPosition = _player!.state.position;
            _stopwatch.reset();
            _stopwatch.start();
          } else {
            // Paused: stop the stopwatch, snap to player position.
            _stopwatch.stop();
            _position = _player!.state.position;
          }
          setState(() => _playing = playing);
        }
      });

      debugPrint('[ResultsScreen] Opening file (S/W rendering): $path');
      await _player!.open(Media(path), play: false);

      // Wait for media to initialize
      await Future.delayed(const Duration(milliseconds: 500));

      debugPrint('[ResultsScreen] Media opened, ready=true');
      // Stopwatch-interpolated position at ~30fps for smooth effect triggering.
      // Instead of reading player.state.position (which updates at ~10Hz),
      // we compute: syncPosition + stopwatch.elapsed for continuous updates.
      _effectTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
        if (_player != null && _playing && mounted) {
          // Interpolate position using wall-clock stopwatch.
          final interpolated = _syncPosition + _stopwatch.elapsed;
          // Clamp to duration to avoid overshooting.
          final clamped = _duration.inMilliseconds > 0
              ? (interpolated.inMilliseconds > _duration.inMilliseconds
                  ? _duration
                  : interpolated)
              : interpolated;
          if (clamped != _position) {
            setState(() => _position = clamped);
          }

          // Re-sync from player every ~500ms (15 ticks) to prevent drift.
          _syncCounter++;
          if (_syncCounter >= 15) {
            _syncCounter = 0;
            final actual = _player!.state.position;
            final drift = (interpolated.inMilliseconds - actual.inMilliseconds).abs();
            if (drift > 100) {
              // Drift > 100ms — hard re-sync.
              _syncPosition = actual;
              _stopwatch.reset();
              _stopwatch.start();
            }
          }
        }
      });
      if (mounted) setState(() => _ready = true);
    } catch (e, st) {
      debugPrint('[ResultsScreen] Video player error: $e\n$st');
      if (mounted) {
        setState(() => _videoError = 'Video player error: $e');
      }
    }
  }

  @override
  void dispose() {
    _effectTimer?.cancel();
    _stopwatch.stop();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_player == null) return;
    _player!.playOrPause();
  }

  /// Re-sync stopwatch when user seeks via timeline.
  void _onSeek(double seconds) {
    final dur = Duration(milliseconds: (seconds * 1000).round());
    _player?.seek(dur);
    // Immediately update sync point so stopwatch tracks from new position.
    _syncPosition = dur;
    _stopwatch.reset();
    if (_playing) _stopwatch.start();
    setState(() => _position = dur);
  }

  Future<void> _exportWithEffects() async {
    final notifier = ref.read(pipelineProvider.notifier);
    try {
      final outputPath = await notifier.exportWithEffects();
      if (outputPath != null && mounted) {
        if (Platform.isAndroid || Platform.isIOS) {
          // Mobile: share the exported video
          await Share.shareXFiles([XFile(outputPath)]);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Video exported with effects')),
            );
          }
        } else {
          // Desktop: prompt save dialog
          final result = await FilePicker.platform.saveFile(
            dialogTitle: 'Save processed video',
            fileName: 'processed_video.mp4',
            type: FileType.video,
          );
          if (result != null) {
            await File(outputPath).copy(result);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Video exported with effects')),
              );
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pipelineProvider);
    final settings = ref.watch(settingsProvider);
    final report = state.report;
    final theme = Theme.of(context);

    if (report == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Results')),
        body: const Center(child: Text('No results available')),
      );
    }

    final positionSec = _position.inMilliseconds / 1000.0;
    final hits = state.hits;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Results'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            ref.read(pipelineProvider.notifier).reset();
            Navigator.pushReplacementNamed(context, '/');
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'Detection Report',
            onPressed: () => Navigator.pushNamed(context, '/report'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Video player with real-time effects overlay
              if (_ready && _videoController != null)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.55,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: RealtimeEffectsOverlay(
                      hits: hits,
                      positionSeconds: positionSec,
                      isPlaying: _playing,
                      kickEffect: settings.kickEffect,
                      snareEffect: settings.snareEffect,
                      child: Video(
                        controller: _videoController!,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                )
              else if (_videoError != null)
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _videoError!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.red[300],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                )
              else
                const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                ),

              const SizedBox(height: 4),

              // Play/pause controls
              if (_ready)
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _playing ? Icons.pause_circle : Icons.play_circle,
                        size: 32,
                      ),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _togglePlayPause,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const Spacer(),
                    // Open in external player (desktop only)
                    if (state.videoPath != null && Platform.isWindows)
                      TextButton.icon(
                        onPressed: () async {
                          await Process.start(
                            'cmd', ['/c', 'start', '', state.videoPath!],
                          );
                        },
                        icon: const Icon(Icons.open_in_new, size: 14),
                        label: const Text('External Player'),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 4),

              // Detection timeline
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Detection Timeline',
                          style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      _MediaKitTimeline(
                        hits: report.allHits,
                        durationSeconds: report.durationSeconds,
                        positionSeconds: positionSec,
                        onSeek: _onSeek,
                      ),
                      Row(
                        children: [
                          _LegendDot(color: AppTheme.kickColor, label: 'Kick'),
                          const SizedBox(width: 16),
                          _LegendDot(
                              color: AppTheme.snareColor, label: 'Snare'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Combined stats row
              Row(
                children: [
                  Expanded(
                    child: StatCard(
                      label: 'Kicks',
                      count: report.kicks.length,
                      color: AppTheme.kickColor,
                      icon: Icons.speaker,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatCard(
                      label: 'Snares',
                      count: report.snares.length,
                      color: AppTheme.snareColor,
                      icon: Icons.music_note,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Duration / FPS / Total — compact inline
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _InfoItem(
                        label: 'Duration',
                        value:
                            '${report.durationSeconds.toStringAsFixed(1)}s',
                      ),
                      _InfoItem(
                        label: 'FPS',
                        value: report.fps.toStringAsFixed(1),
                      ),
                      _InfoItem(
                        label: 'Total Hits',
                        value: report.totalHits.toString(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Action buttons — stacked vertically for mobile
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: state.isExporting ? null : _exportWithEffects,
                  icon: state.isExporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.movie_creation),
                  label: Text(
                      state.isExporting ? 'Exporting...' : 'Export with Effects'),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        if (state.videoPath != null) {
                          Share.shareXFiles([
                            XFile(state.videoPath!),
                          ]);
                        }
                      },
                      icon: const Icon(Icons.share),
                      label: const Text('Share'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        ref.read(pipelineProvider.notifier).reset();
                        Navigator.pushReplacementNamed(context, '/');
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('New Video'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Timeline widget that works with media_kit position (no VideoPlayerController).
class _MediaKitTimeline extends StatelessWidget {
  final List<DrumHit> hits;
  final double durationSeconds;
  final double positionSeconds;
  final ValueChanged<double>? onSeek;

  const _MediaKitTimeline({
    required this.hits,
    required this.durationSeconds,
    required this.positionSeconds,
    this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: GestureDetector(
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
            playheadSeconds: positionSeconds,
          ),
          size: Size.infinite,
        ),
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

    final barRect = Rect.fromLTWH(0, 16, size.width, 24);
    canvas.drawRRect(
      RRect.fromRectAndRadius(barRect, const Radius.circular(4)),
      bgPaint,
    );

    for (final hit in hits) {
      final x = (hit.time / durationSeconds) * size.width;
      final color =
          hit.type == DrumType.kick ? AppTheme.kickColor : AppTheme.snareColor;
      final markerPaint = Paint()
        ..color = color.withOpacity(0.8)
        ..strokeWidth = 2;
      canvas.drawLine(Offset(x, 12), Offset(x, 44), markerPaint);
    }

    final playheadX = (playheadSeconds / durationSeconds) * size.width;
    final playheadPaint = Paint()
      ..color = AppTheme.playheadColor
      ..strokeWidth = 2.5;
    canvas.drawLine(Offset(playheadX, 8), Offset(playheadX, 48), playheadPaint);

    final trianglePath = Path()
      ..moveTo(playheadX - 5, 8)
      ..lineTo(playheadX + 5, 8)
      ..lineTo(playheadX, 14)
      ..close();
    canvas.drawPath(trianglePath, Paint()..color = AppTheme.playheadColor);
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.playheadSeconds != playheadSeconds ||
      old.hits != hits ||
      old.durationSeconds != durationSeconds;
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;

  const _InfoItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        Text(label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                )),
      ],
    );
  }
}
