/// App wide settings, persisted with shared_preferences.
///
/// Loading happens in the background and defaults apply until it lands, so no
/// screen has to wait on a disk read. Every write is guarded: a device that
/// refuses to store preferences still plays, it just forgets them.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  const AppSettings({
    this.sound = true,
    this.music = true,
    this.musicVolume = 0.35,
    this.haptics = true,
    this.loaded = false,
  });

  final bool sound;
  final bool music;
  final double musicVolume;
  final bool haptics;

  /// False until the stored values have been read.
  final bool loaded;

  AppSettings copyWith({
    bool? sound,
    bool? music,
    double? musicVolume,
    bool? haptics,
    bool? loaded,
  }) => AppSettings(
    sound: sound ?? this.sound,
    music: music ?? this.music,
    musicVolume: musicVolume ?? this.musicVolume,
    haptics: haptics ?? this.haptics,
    loaded: loaded ?? this.loaded,
  );
}

class SettingsController extends Notifier<AppSettings> {
  static const _keySound = 'settings.sound';
  static const _keyMusic = 'settings.music';
  static const _keyVolume = 'settings.musicVolume';
  static const _keyHaptics = 'settings.haptics';

  @override
  AppSettings build() {
    Future.microtask(_load);
    return const AppSettings();
  }

  Future<void> _load() async {
    final prefs = await _prefs();
    if (prefs == null) {
      state = state.copyWith(loaded: true);
      return;
    }
    state = AppSettings(
      sound: prefs.getBool(_keySound) ?? true,
      music: prefs.getBool(_keyMusic) ?? true,
      musicVolume: (prefs.getDouble(_keyVolume) ?? 0.35).clamp(0.0, 1.0),
      haptics: prefs.getBool(_keyHaptics) ?? true,
      loaded: true,
    );
  }

  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (error) {
      debugPrint('settings unavailable: $error');
      return null;
    }
  }

  Future<void> setSound(bool value) async {
    state = state.copyWith(sound: value);
    (await _prefs())?.setBool(_keySound, value);
  }

  Future<void> setMusic(bool value) async {
    state = state.copyWith(music: value);
    (await _prefs())?.setBool(_keyMusic, value);
  }

  Future<void> setMusicVolume(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    state = state.copyWith(musicVolume: clamped);
    (await _prefs())?.setDouble(_keyVolume, clamped);
  }

  Future<void> setHaptics(bool value) async {
    state = state.copyWith(haptics: value);
    (await _prefs())?.setBool(_keyHaptics, value);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);
