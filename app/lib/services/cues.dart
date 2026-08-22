/// Game cues: the small responses that tell a player something happened.
///
/// Sound and vibration are asked for together, because from a screen's point of
/// view they are one thing: "a card was played" or "that tap was refused". Both
/// channels honour their own setting, and every method is safe to call when both
/// are switched off.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/settings.dart';
import 'audio.dart';

class Cues {
  const Cues({required this.haptics, required this.sound, required this.audio});

  final bool haptics;
  final bool sound;
  final Audio audio;

  void _sfx(String asset, [double volume = 1]) {
    if (sound) audio.play(asset, volume: volume);
  }

  void tap() {
    if (haptics) HapticFeedback.selectionClick();
  }

  void turnStart() {
    if (haptics) HapticFeedback.mediumImpact();
    _sfx(Sfx.turn, 0.8);
  }

  void cardPlayed() {
    if (haptics) HapticFeedback.lightImpact();
    _sfx(Sfx.cardPlace);
  }

  /// Somebody else's card. Quieter, so a table of bots does not become a drum.
  void cardPlayedElsewhere() {
    _sfx(Sfx.cardPlace, 0.5);
  }

  void passed() {
    if (haptics) HapticFeedback.selectionClick();
    _sfx(Sfx.pass, 0.8);
  }

  void passedElsewhere() {
    _sfx(Sfx.pass, 0.45);
  }

  void timerWarning() {
    if (haptics) HapticFeedback.mediumImpact();
    _sfx(Sfx.warn, 0.7);
  }

  /// Refused input, such as tapping a card that cannot be played yet.
  void denied() {
    if (haptics) HapticFeedback.heavyImpact();
    _sfx(Sfx.deny, 0.7);
  }

  void win() {
    if (haptics) HapticFeedback.heavyImpact();
    _sfx(Sfx.win);
  }

  void lose() {
    if (haptics) HapticFeedback.lightImpact();
    _sfx(Sfx.lose, 0.8);
  }

  void coins() {
    if (haptics) HapticFeedback.lightImpact();
    _sfx(Sfx.coin);
  }
}

final cuesProvider = Provider<Cues>((ref) {
  final settings = ref.watch(settingsProvider);
  return Cues(
    haptics: settings.haptics,
    sound: settings.sound,
    audio: ref.watch(audioProvider),
  );
});
