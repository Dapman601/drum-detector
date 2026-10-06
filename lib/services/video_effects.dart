import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';
import '../models/drum_hit.dart';
import '../models/processing_settings.dart';
import 'ffmpeg_service.dart';

/// Builds and executes FFmpeg filter_complex commands to apply visual effects
/// at drum hit timestamps.
///
/// Dispatches on the user-selected kick/snare effect enums to generate the
/// correct FFmpeg filter graph.
class VideoEffectsService {
  Future<String> apply({
    required String inputPath,
    required List<DrumHit> hits,
    required ProcessingSettings settings,
    required int width,
    required int height,
    required double fps,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final outputPath = '${tempDir.path}${Platform.pathSeparator}processed_$ts.mp4';

    if (hits.isEmpty) {
      await FFmpegService.executeOrThrow([
        '-y', '-i', inputPath, '-c', 'copy', outputPath,
      ]);
      return outputPath;
    }

    final kicks = hits.where((h) => h.type == DrumType.kick).toList();
    final snares = hits.where((h) => h.type == DrumType.snare).toList();

    final filterComplex = _buildFilter(kicks, snares, settings, fps, width, height);

    // Always use -filter_complex_script (file-based) because inline
    // -filter_complex mangles commas inside between() expressions on Windows.
    final scriptFile = File('${tempDir.path}${Platform.pathSeparator}filter_$ts.txt');
    await scriptFile.writeAsString(filterComplex);
    debugPrint('[VideoEffects] Hits: ${hits.length} total, ${kicks.length} kicks, ${snares.length} snares');
    debugPrint('[VideoEffects] Filter (${filterComplex.length} chars): $filterComplex');

    try {
      // Use libx264 on all platforms — h264_mediacodec on Android can
      // produce green output with certain pixel formats from filter chains.
      final result = await FFmpegService.execute([
        '-y', '-i', inputPath,
        '-filter_complex_script', scriptFile.path,
        '-map', '[vout]', '-map', '0:a?',
        '-c:v', 'libx264', '-preset', 'fast', '-crf', '23', '-pix_fmt', 'yuv420p',
        '-movflags', '+faststart',
        '-c:a', 'copy',
        outputPath,
      ]);
      debugPrint('[VideoEffects] FFmpeg exit: ${result.exitCode}');
      if (result.exitCode != 0) {
        debugPrint('[VideoEffects] FFmpeg stderr: ${result.stderr}');
        throw Exception('FFmpeg failed (exit ${result.exitCode}): ${result.stderr}');
      }
    } finally {
      try { await scriptFile.delete(); } catch (_) {}
    }

    return outputPath;
  }

  /// Build the FFmpeg filter graph based on selected effects.
  String _buildFilter(
    List<DrumHit> kicks,
    List<DrumHit> snares,
    ProcessingSettings settings,
    double fps,
    int width,
    int height,
  ) {
    final parts = <String>[];
    final dur = effectDurationSec;

    String t3(double v) => v.toStringAsFixed(3);

    // Build a combined enable expression for a list of hits
    String enableExpr(List<DrumHit> hits) {
      return hits.map((h) {
        return 'between(t,${t3(h.time)},${t3(h.time + dur)})';
      }).join('+');
    }

    // --- Kick effect ---
    if (kicks.isNotEmpty) {
      switch (settings.kickEffect) {
        case KickEffect.flashWhite:
          // Brightness flash using eq filter
          final terms = kicks.map((k) {
            return 'if(between(t,${t3(k.time)},${t3(k.time + dur)}),0.4,0)';
          }).join('+');
          parts.add("eq=brightness='$terms':eval=frame");
          break;

        case KickEffect.zoomPunch:
          // 5% zoom via crop (smaller center region) + scale back to original.
          // When a kick is active, crop to 95% of frame (centered), then scale
          // back up — this creates a zoom-in punch effect.
          final en = enableExpr(kicks);
          // Crop width/height: when active use 95%, otherwise 100%
          final cw = "if($en,iw*0.95,iw)";
          final ch = "if($en,ih*0.95,ih)";
          parts.add("crop=w='$cw':h='$ch':x='(iw-ow)/2':y='(ih-oh)/2'");
          parts.add("scale=$width:$height");
          break;

        case KickEffect.borderPulse:
          // White border using drawbox
          final en = enableExpr(kicks);
          const bw = 6;
          parts.add("drawbox=x=0:y=0:w=iw:h=$bw:color=white:enable='$en'");
          parts.add("drawbox=x=0:y=ih-$bw:w=iw:h=$bw:color=white:enable='$en'");
          parts.add("drawbox=x=0:y=0:w=$bw:h=ih:color=white:enable='$en'");
          parts.add("drawbox=x=iw-$bw:y=0:w=$bw:h=ih:color=white:enable='$en'");
          break;

        case KickEffect.chromaticAberration:
          // Approximate chromatic aberration: saturate + contrast boost on hit
          final en = enableExpr(kicks);
          parts.add("hue=s='if($en,3,1)'");
          parts.add("eq=contrast='if($en,1.3,1)':eval=frame");
          break;

        case KickEffect.screenSlam:
          // Screen slam: dark punch (negative brightness + contrast boost)
          final terms = kicks.map((k) {
            return 'if(between(t,${t3(k.time)},${t3(k.time + dur)}),0.5,0)';
          }).join('+');
          parts.add("eq=brightness='-$terms':contrast='1+$terms*1.5':eval=frame");
          break;

        case KickEffect.redFlash:
          // Red flash: darken + shift hue toward red + boost saturation
          final terms = kicks.map((k) {
            return 'if(between(t,${t3(k.time)},${t3(k.time + dur)}),1,0)';
          }).join('+');
          parts.add("eq=brightness='-$terms*0.25':eval=frame");
          parts.add("hue=H='$terms*(-30)':s='1+$terms*2'");
          break;

        case KickEffect.vignetteSslam:
          // Vignette slam: heavy vignette darkening edges on impact
          final terms = kicks.map((k) {
            return 'if(between(t,${t3(k.time)},${t3(k.time + dur)}),1,0)';
          }).join('+');
          parts.add("vignette='PI/5+$terms*PI/3':eval=frame");
          break;

        case KickEffect.saturationKill:
          // Desaturate to grayscale on kick
          final terms = kicks.map((k) {
            return 'if(between(t,${t3(k.time)},${t3(k.time + dur)}),1,0)';
          }).join('+');
          parts.add("eq=saturation='1-$terms*0.95':eval=frame");
          break;

        case KickEffect.strobeDark:
          // Rapid dark strobe: flickers dark on alternating frames
          final terms = kicks.map((k) {
            return 'if(between(t,${t3(k.time)},${t3(k.time + dur)}),1,0)';
          }).join('+');
          parts.add("eq=brightness='-$terms*0.6*mod(floor(n/2)\\,2)':contrast='1+$terms*0.3':eval=frame");
          break;

        case KickEffect.gammaPunch:
          // Gamma punch: washed-out overexposed look on impact
          final terms = kicks.map((k) {
            return 'if(between(t,${t3(k.time)},${t3(k.time + dur)}),1,0)';
          }).join('+');
          parts.add("eq=gamma='1+$terms*2.5':brightness='$terms*0.15':eval=frame");
          break;
      }
    }

    // --- Snare effect ---
    if (snares.isNotEmpty) {
      switch (settings.snareEffect) {
        case SnareEffect.flashInvert:
          // Color inversion using negate
          final en = enableExpr(snares);
          parts.add("negate=enable='$en'");
          break;

        case SnareEffect.shake:
          // Shake via crop+scale with alternating pixel offset
          const offsetPx = 8;
          final en = enableExpr(snares);
          final xExpr = "if($en,$offsetPx*(mod(n\\,2)*2-1),0)";
          final yExpr = "if($en,$offsetPx*(mod(n\\,3)-1),0)";
          parts.add(
            "crop=iw-${offsetPx * 2}:ih-${offsetPx * 2}"
            ":$offsetPx+$xExpr:$offsetPx+$yExpr"
          );
          parts.add("scale=$width:$height");
          break;

        case SnareEffect.colorTint:
          // Cyan tint using colorbalance
          final en = enableExpr(snares);
          const tintAmount = 0.3;
          parts.add(
            "colorbalance="
            "rm='-if($en,$tintAmount,0)'"
            ":gm='if($en,$tintAmount,0)'"
            ":bm='if($en,$tintAmount,0)'"
          );
          break;

        case SnareEffect.hardStrobe:
          // Intense white flash using eq brightness + gamma
          final terms = snares.map((s) {
            return 'if(between(t,${t3(s.time)},${t3(s.time + dur)}),0.7,0)';
          }).join('+');
          parts.add("eq=brightness='$terms':gamma='1+$terms':eval=frame");
          break;

        case SnareEffect.horizontalGlitch:
          // Glitch: negate + hue shift on hit
          final en = enableExpr(snares);
          parts.add("negate=enable='$en'");
          parts.add("hue=h='if($en,90,0)'");
          break;

        case SnareEffect.screenPop:
          // Screen pop: brightness flash on hit
          final terms = snares.map((s) {
            return 'if(between(t,${t3(s.time)},${t3(s.time + dur)}),0.3,0)';
          }).join('+');
          parts.add("eq=brightness='$terms':eval=frame");
          break;

        case SnareEffect.burst:
          // Burst: color inversion on snare hits (very distinct from kick)
          final en = enableExpr(snares);
          parts.add("negate=enable='$en'");
          break;

        case SnareEffect.whiteFlash:
          // Bright white flash on snare
          final terms = snares.map((s) {
            return 'if(between(t,${t3(s.time)},${t3(s.time + dur)}),0.6,0)';
          }).join('+');
          parts.add("eq=brightness='$terms':eval=frame");
          break;

        case SnareEffect.blueTint:
          // Cool blue/cyan hue shift on snare
          final terms = snares.map((s) {
            return 'if(between(t,${t3(s.time)},${t3(s.time + dur)}),1,0)';
          }).join('+');
          parts.add("hue=H='$terms*200':s='1+$terms*1.5'");
          parts.add("eq=brightness='$terms*0.15':eval=frame");
          break;

        case SnareEffect.sharpenBlast:
          // Sharpen + brightness pop on snare
          final en = enableExpr(snares);
          final terms = snares.map((s) {
            return 'if(between(t,${t3(s.time)},${t3(s.time + dur)}),0.3,0)';
          }).join('+');
          parts.add("unsharp=7:7:3:enable='$en'");
          parts.add("eq=brightness='$terms':contrast='1+$terms':eval=frame");
          break;

        case SnareEffect.solarize:
          // Solarize: extreme gamma distortion creates psychedelic look
          final terms = snares.map((s) {
            return 'if(between(t,${t3(s.time)},${t3(s.time + dur)}),1,0)';
          }).join('+');
          parts.add("eq=gamma='1+$terms*4':saturation='1+$terms*2':eval=frame");
          break;

        case SnareEffect.hueSpin:
          // 180-degree hue rotation on snare hits
          final terms = snares.map((s) {
            return 'if(between(t,${t3(s.time)},${t3(s.time + dur)}),1,0)';
          }).join('+');
          parts.add("hue=H='$terms*180':s='1+$terms'");
          break;
      }
    }

    if (parts.isEmpty) return '[0:v]null[vout]';

    // On mobile, cap at 1080p to prevent OOM on large videos (e.g. 4K AV1).
    // On desktop, just ensure even dimensions for H.264.
    if (Platform.isAndroid || Platform.isIOS) {
      parts.add("scale='min(iw,1920)':'min(ih,1080)':force_original_aspect_ratio=decrease");
    }
    // Ensure even dimensions (H.264 requires mod-2 width/height)
    parts.add("scale='trunc(iw/2)*2':'trunc(ih/2)*2'");

    // Force yuv420p output — effects like negate, hue, colorbalance can
    // promote pixel format to yuv444p/gbrap, causing green video output
    // when the encoder receives uninitialized chroma planes.
    parts.add("format=yuv420p");

    // Chain: [0:v]filter1,filter2[vout]
    return '[0:v]${parts.join(",")}[vout]';
  }

  /// Get video dimensions and fps using FFmpeg.
  Future<({int width, int height, double fps})> getVideoInfo(String path) async {
    final result = await FFmpegService.execute(['-i', path, '-hide_banner']);
    final output = result.allOutput;

    // Anchor to video stream line to avoid matching audio bitrate like "48000"
    final resMatch = RegExp(r'Stream.*Video:.* (\d{2,5})x(\d{2,5})').firstMatch(output)
        ?? RegExp(r'(\d{2,5})x(\d{2,5})').firstMatch(output);
    final fpsMatch = RegExp(r'(\d+(?:\.\d+)?)\s*fps').firstMatch(output);

    final width = resMatch != null ? int.parse(resMatch.group(1)!) : 1920;
    final height = resMatch != null ? int.parse(resMatch.group(2)!) : 1080;
    final fps = fpsMatch != null ? double.parse(fpsMatch.group(1)!) : 30.0;

    return (width: width, height: height, fps: fps);
  }
}
