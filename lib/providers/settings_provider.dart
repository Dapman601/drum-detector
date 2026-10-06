import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../models/processing_settings.dart';

class SettingsNotifier extends StateNotifier<ProcessingSettings> {
  SettingsNotifier() : super(const ProcessingSettings());

  void setKickThreshold(double value) =>
      state = state.copyWith(kickThreshold: value);

  void setSnareThreshold(double value) =>
      state = state.copyWith(snareThreshold: value);

  void setKickEffect(KickEffect effect) =>
      state = state.copyWith(kickEffect: effect);

  void setSnareEffect(SnareEffect effect) =>
      state = state.copyWith(snareEffect: effect);

  void reset() => state = const ProcessingSettings();
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, ProcessingSettings>(
  (ref) => SettingsNotifier(),
);
