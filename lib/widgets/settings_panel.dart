import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../providers/settings_provider.dart';

/// Expandable panel with threshold sliders and effect dropdowns.
class SettingsPanel extends ConsumerWidget {
  const SettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);

    return ExpansionTile(
      title: Text('Settings', style: theme.textTheme.titleMedium),
      initiallyExpanded: false,
      childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // Kick effect dropdown
        _DropdownRow<KickEffect>(
          label: 'Kick effect',
          value: settings.kickEffect,
          items: KickEffect.values,
          nameOf: _kickEffectName,
          onChanged: notifier.setKickEffect,
        ),
        const SizedBox(height: 8),

        // Snare effect dropdown
        _DropdownRow<SnareEffect>(
          label: 'Snare effect',
          value: settings.snareEffect,
          items: SnareEffect.values,
          nameOf: _snareEffectName,
          onChanged: notifier.setSnareEffect,
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  static String _kickEffectName(KickEffect e) {
    switch (e) {
      case KickEffect.zoomPunch:
        return 'Zoom Punch';
      case KickEffect.flashWhite:
        return 'Flash White';
      case KickEffect.borderPulse:
        return 'Border Pulse';
      case KickEffect.chromaticAberration:
        return 'Chromatic Aberration';
      case KickEffect.screenSlam:
        return 'Screen Slam';
      case KickEffect.redFlash:
        return 'Red Flash';
      case KickEffect.vignetteSslam:
        return 'Vignette Slam';
      case KickEffect.saturationKill:
        return 'Saturation Kill';
      case KickEffect.strobeDark:
        return 'Strobe Dark';
      case KickEffect.gammaPunch:
        return 'Gamma Punch';
    }
  }

  static String _snareEffectName(SnareEffect e) {
    switch (e) {
      case SnareEffect.flashInvert:
        return 'Flash Invert';
      case SnareEffect.shake:
        return 'Shake';
      case SnareEffect.colorTint:
        return 'Color Tint';
      case SnareEffect.hardStrobe:
        return 'Hard Strobe';
      case SnareEffect.horizontalGlitch:
        return 'Horizontal Glitch';
      case SnareEffect.screenPop:
        return 'Screen Pop';
      case SnareEffect.burst:
        return 'Burst';
      case SnareEffect.whiteFlash:
        return 'White Flash';
      case SnareEffect.blueTint:
        return 'Blue Tint';
      case SnareEffect.sharpenBlast:
        return 'Sharpen Blast';
      case SnareEffect.solarize:
        return 'Solarize';
      case SnareEffect.hueSpin:
        return 'Hue Spin';
    }
  }
}

class _DropdownRow<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final String Function(T) nameOf;
  final ValueChanged<T> onChanged;

  const _DropdownRow({
    required this.label,
    required this.value,
    required this.items,
    required this.nameOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        Expanded(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            dropdownColor: Theme.of(context).cardTheme.color,
            items: items
                .map((e) => DropdownMenuItem(value: e, child: Text(nameOf(e))))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ],
    );
  }
}
