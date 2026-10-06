import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

/// Platform-aware FFmpeg execution.
///
/// On mobile (Android/iOS): uses FFmpegKit plugin.
/// On desktop (Windows/Linux/macOS): uses bundled or system ffmpeg binary via Process.run.
class FFmpegService {
  static String? _ffmpegPath;

  static bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  /// Find the ffmpeg executable path (desktop only).
  static String get ffmpegPath {
    if (_ffmpegPath != null) return _ffmpegPath!;

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // Look for bundled ffmpeg next to the executable
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final bundled = File('$exeDir/blobs/ffmpeg.exe');
      if (bundled.existsSync()) {
        _ffmpegPath = bundled.path;
        return _ffmpegPath!;
      }
      // Try blobs without .exe (linux/mac)
      final bundledUnix = File('$exeDir/blobs/ffmpeg');
      if (bundledUnix.existsSync()) {
        _ffmpegPath = bundledUnix.path;
        return _ffmpegPath!;
      }
      // Fall back to system PATH
      _ffmpegPath = 'ffmpeg';
      return _ffmpegPath!;
    }

    _ffmpegPath = 'ffmpeg';
    return _ffmpegPath!;
  }

  /// Execute an FFmpeg command and return the result.
  /// [args] is the list of arguments (not including 'ffmpeg' itself).
  static Future<FFmpegResult> execute(List<String> args) async {
    if (_isMobile) {
      return _executeMobile(args);
    }
    return _executeDesktop(args);
  }

  /// Mobile: use FFmpegKit plugin.
  static Future<FFmpegResult> _executeMobile(List<String> args) async {
    final command = args.map((a) {
      // Quote args that contain spaces
      if (a.contains(' ') || a.contains("'")) {
        return '"${a.replaceAll('"', r'\"')}"';
      }
      return a;
    }).join(' ');

    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    final output = await session.getOutput() ?? '';
    final logs = await session.getAllLogsAsString() ?? '';

    return FFmpegResult(
      exitCode: ReturnCode.isSuccess(returnCode) ? 0 : (returnCode?.getValue() ?? -1),
      stdout: output,
      stderr: logs,
    );
  }

  /// Desktop: use Process.run with bundled or system ffmpeg.
  static Future<FFmpegResult> _executeDesktop(List<String> args) async {
    final result = await Process.run(ffmpegPath, args);

    return FFmpegResult(
      exitCode: result.exitCode,
      stdout: result.stdout as String,
      stderr: result.stderr as String,
    );
  }

  /// Execute and throw on failure.
  static Future<FFmpegResult> executeOrThrow(List<String> args) async {
    final result = await execute(args);
    if (result.exitCode != 0) {
      throw Exception('FFmpeg failed (exit ${result.exitCode}): ${result.stderr}');
    }
    return result;
  }
}

class FFmpegResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const FFmpegResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  bool get isSuccess => exitCode == 0;
  String get allOutput => '$stdout\n$stderr';
}
