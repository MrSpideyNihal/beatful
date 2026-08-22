/// Solo match setup, remembered between sessions.
///
/// Home starts a solo game in one tap, so whatever was chosen last time has to
/// still be there next time. A bad stored value is folded back into range rather
/// than rejected, because a preferences file is not worth an error screen.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/bots.dart';

const int minBots = 1;
const int maxBots = 7;
const List<int> timerChoices = [10, 15, 20, 30];
const List<int> roundChoices = [1, 3, 5];

@immutable
class SoloConfig {
  const SoloConfig({
    this.botCount = 3,
    this.difficulty = BotDifficulty.medium,
    this.timerSeconds = 15,
    this.rounds = 1,
  });

  final int botCount;
  final BotDifficulty difficulty;
  final int timerSeconds;
  final int rounds;

  int get seatCount => botCount + 1;

  SoloConfig copyWith({
    int? botCount,
    BotDifficulty? difficulty,
    int? timerSeconds,
    int? rounds,
  }) => SoloConfig(
    botCount: (botCount ?? this.botCount).clamp(minBots, maxBots),
    difficulty: difficulty ?? this.difficulty,
    timerSeconds: timerChoices.contains(timerSeconds ?? this.timerSeconds)
        ? (timerSeconds ?? this.timerSeconds)
        : this.timerSeconds,
    rounds: roundChoices.contains(rounds ?? this.rounds)
        ? (rounds ?? this.rounds)
        : this.rounds,
  );

  @override
  bool operator ==(Object other) =>
      other is SoloConfig &&
      other.botCount == botCount &&
      other.difficulty == difficulty &&
      other.timerSeconds == timerSeconds &&
      other.rounds == rounds;

  @override
  int get hashCode => Object.hash(botCount, difficulty, timerSeconds, rounds);
}

class SoloConfigController extends Notifier<SoloConfig> {
  static const _keyBots = 'solo.bots';
  static const _keyDifficulty = 'solo.difficulty';
  static const _keyTimer = 'solo.timer';
  static const _keyRounds = 'solo.rounds';

  @override
  SoloConfig build() {
    Future.microtask(_load);
    return const SoloConfig();
  }

  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (error) {
      debugPrint('solo setup unavailable: $error');
      return null;
    }
  }

  Future<void> _load() async {
    final prefs = await _prefs();
    if (prefs == null) return;
    final stored = SoloConfig(
      botCount: (prefs.getInt(_keyBots) ?? 3).clamp(minBots, maxBots),
      difficulty: BotDifficulty.fromWire(prefs.getString(_keyDifficulty)),
      timerSeconds: prefs.getInt(_keyTimer) ?? 15,
      rounds: prefs.getInt(_keyRounds) ?? 1,
    );
    state = const SoloConfig().copyWith(
      botCount: stored.botCount,
      difficulty: stored.difficulty,
      timerSeconds: stored.timerSeconds,
      rounds: stored.rounds,
    );
  }

  Future<void> _save(SoloConfig config) async {
    state = config;
    final prefs = await _prefs();
    if (prefs == null) return;
    await prefs.setInt(_keyBots, config.botCount);
    await prefs.setString(_keyDifficulty, config.difficulty.wire);
    await prefs.setInt(_keyTimer, config.timerSeconds);
    await prefs.setInt(_keyRounds, config.rounds);
  }

  void setBotCount(int value) => _save(state.copyWith(botCount: value));

  void setDifficulty(BotDifficulty value) =>
      _save(state.copyWith(difficulty: value));

  void setTimerSeconds(int value) => _save(state.copyWith(timerSeconds: value));

  void setRounds(int value) => _save(state.copyWith(rounds: value));
}

final soloConfigProvider = NotifierProvider<SoloConfigController, SoloConfig>(
  SoloConfigController.new,
);
