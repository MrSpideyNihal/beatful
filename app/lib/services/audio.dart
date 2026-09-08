/// Sound effects and background music.
///
/// One player per effect slot so two cues can overlap, and a separate looping
/// player for the music. Every call is fire and forget: a device that cannot play
/// audio, or an asset that failed to load, must never break a turn, so failures
/// are logged once and then ignored.
///
/// The music loop is interruptible in both directions. Turning it off stops it
/// where it is, turning it back on starts it again, and the volume slider takes
/// effect on the running loop without restarting it.
library;

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/settings.dart';

/// Effect names, matched to the files in assets/audio.
abstract final class Sfx {
  static const cardPlace = 'card_place.wav';
  static const pass = 'pass.wav';
  static const turn = 'turn.wav';
  static const warn = 'warn.wav';
  static const deny = 'deny.wav';
  static const win = 'win.wav';
  static const lose = 'lose.wav';
  static const coin = 'coin.wav';

  static const music = 'music_loop.wav';
}

class Audio {
  Audio();

  /// A small pool, reused round robin, so a fast sequence of plays does not build
  /// up players and does not cut itself off either.
  final List<AudioPlayer> _pool = [];
  AudioPlayer? _music;

  int _next = 0;
  bool _broken = false;
  bool _musicWanted = false;
  double _volume = 0.35;
  bool _disposed = false;

  static const int _poolSize = 4;

  Future<void> _ensurePool() async {
    if (_pool.isNotEmpty || _broken) return;
    try {
      try {
        await AudioPlayer.global.setAudioContext(
          AudioContext(
            android: const AudioContextAndroid(
              isSpeakerphoneOn: true,
              stayAwake: false,
              contentType: AndroidContentType.music,
              usageType: AndroidUsageType.game,
              audioFocus: AndroidAudioFocus.none,
            ),
            iOS: AudioContextIOS(
              category: AVAudioSessionCategory.playback,
              options: const {AVAudioSessionOptions.mixWithOthers},
            ),
          ),
        );
      } catch (e) {
        debugPrint('audio context setting skipped: $e');
      }
      for (var i = 0; i < _poolSize; i += 1) {
        final player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
        await player.setPlayerMode(PlayerMode.lowLatency);
        _pool.add(player);
      }
    } catch (error) {
      _fail('effect players unavailable', error);
    }
  }

  void _fail(String what, Object error) {
    _broken = true;
    debugPrint('audio off: $what: $error');
  }

  /// Play a one shot effect. Silent when sound is switched off.
  void play(String asset, {double volume = 1}) {
    if (_broken || _disposed) return;
    unawaited(_playAsync(asset, volume));
  }

  Future<void> _playAsync(String asset, double volume) async {
    await _ensurePool();
    if (_pool.isEmpty || _disposed) return;
    final player = _pool[_next % _pool.length];
    _next += 1;
    try {
      await player.stop();
      await player.setVolume(volume.clamp(0.0, 1.0));
      await player.play(AssetSource('audio/$asset'));
    } catch (error) {
      // One bad effect should not silence the whole game, so this is not fatal.
      debugPrint('audio effect $asset failed: $error');
    }
  }

  /// Start or stop the loop. Safe to call repeatedly with the same value.
  void setMusic({required bool on, required double volume}) {
    _musicWanted = on;
    _volume = volume.clamp(0.0, 1.0);
    if (_disposed) return;
    unawaited(_syncMusic());
  }

  Future<void> _syncMusic() async {
    if (_broken) return;
    try {
      if (!_musicWanted) {
        await _music?.pause();
        return;
      }
      final player = _music ?? (_music = AudioPlayer());
      await player.setReleaseMode(ReleaseMode.loop);
      await player.setVolume(_volume);
      final state = player.state;
      if (state == PlayerState.playing) return;
      if (state == PlayerState.paused) {
        await player.resume();
        return;
      }
      await player.play(AssetSource('audio/${Sfx.music}'), volume: _volume);
    } catch (error) {
      debugPrint('music unavailable: $error');
      _music = null;
    }
  }

  /// A short burst of the music at a new level, so dragging the slider is
  /// something you can hear. Does nothing when the loop is already running.
  void previewMusic(double volume) {
    if (_music != null && _musicWanted) {
      unawaited(_music!.setVolume(volume.clamp(0.0, 1.0)));
      return;
    }
    play(Sfx.music, volume: volume);
  }

  /// Backgrounding: stop the loop without forgetting that it was on.
  void suspend() {
    if (_disposed) return;
    unawaited(_music?.pause());
  }

  void resume() {
    if (_disposed) return;
    unawaited(_syncMusic());
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final player in _pool) {
      await player.dispose();
    }
    _pool.clear();
    await _music?.dispose();
    _music = null;
  }
}

/// One instance for the whole app, kept in sync with the music settings.
final audioProvider = Provider<Audio>((ref) {
  final audio = Audio();
  ref.onDispose(() => unawaited(audio.dispose()));

  ref.listen<AppSettings>(settingsProvider, (previous, next) {
    audio.setMusic(on: next.music, volume: next.musicVolume);
  }, fireImmediately: true);

  return audio;
});
