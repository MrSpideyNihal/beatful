/// The solo match: a local engine, local bots and a local clock.
///
/// Solo runs with no network at all, so this controller is the authority the
/// server is in online play. It calls the same rules module the server calls,
/// which is why a bot cannot make a move a real opponent could not make.
///
/// Everything the screen needs is in SoloGame. The engine state itself stays
/// private, because it holds every hand.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/bots.dart' as bots;
import '../game/cards.dart' as cards;
import '../game/engine.dart' as engine;
import '../game/narrate.dart' as narrate;
import '../models/avatar.dart';
import '../models/seat_info.dart';
import '../services/cues.dart';
import 'identity.dart';
import 'profile.dart';
import 'solo_config.dart';

/// You are always seat 0 in a solo match, so the layout never moves around.
const int humanSeat = 0;

@immutable
class SoloGame {
  const SoloGame({
    required this.config,
    required this.seats,
    required this.view,
    this.notice,
    this.thinkingSeat,
    this.paused = false,
  });

  final SoloConfig config;
  final List<SeatInfo> seats;
  final engine.PublicView view;

  /// A short message for a refused tap, cleared on its own.
  final String? notice;

  /// The bot that is about to move, so its seat can show a thinking dot.
  final int? thinkingSeat;

  final bool paused;

  bool get roundOver => view.status == engine.GameStatus.roundOver;

  bool get matchOver => view.status == engine.GameStatus.finished;

  SeatInfo get you => seats[humanSeat];
}

class SoloController extends AutoDisposeNotifier<SoloGame> {
  late engine.GameState _game;
  late SoloConfig _config;
  late List<SeatInfo> _seats;
  late cards.Rng _rng;

  Timer? _actTimer;
  Timer? _warnTimer;
  Timer? _noticeTimer;

  bool _disposed = false;
  String? _notice;
  int? _thinkingSeat;
  int? _pausedAt;
  int? _cuedTurnAt;
  engine.GameStatus _lastStatus = engine.GameStatus.inProgress;

  @override
  SoloGame build() {
    ref.onDispose(() {
      _disposed = true;
      _cancelTimers();
      _noticeTimer?.cancel();
    });
    _config = ref.read(soloConfigProvider);
    _seats = _buildSeats(_config, ref.read(profileProvider));
    _rng = cards.createRng(cards.randomSeed());
    _deal();
    return _snapshot();
  }

  int _now() => DateTime.now().millisecondsSinceEpoch;

  Cues get _cues => ref.read(cuesProvider);

  void _deal() {
    _game = engine.startRound(
      seatCount: _config.seatCount,
      timerSeconds: _config.timerSeconds,
      rounds: _config.rounds,
      now: _now(),
    );
    _lastStatus = _game.status;
    _cuedTurnAt = null;
    _notice = null;
    _thinkingSeat = null;
    _schedule();
  }

  List<SeatInfo> _buildSeats(SoloConfig config, Profile profile) {
    final seats = <SeatInfo>[
      SeatInfo(
        index: humanSeat,
        name: profile.name,
        avatar: profile.avatar,
        isYou: true,
      ),
    ];
    for (var seat = 1; seat < config.seatCount; seat += 1) {
      seats.add(
        SeatInfo(
          index: seat,
          name: botName(seat - 1),
          // Never hand a bot the avatar the player is using.
          avatar: (profile.avatar + seat) % avatarCount(),
          isBot: true,
          difficulty: config.difficulty,
        ),
      );
    }
    return seats;
  }

  SoloGame _snapshot() => SoloGame(
    config: _config,
    seats: _seats,
    view: engine.publicView(_game, humanSeat, _now()),
    notice: _notice,
    thinkingSeat: _thinkingSeat,
    paused: _pausedAt != null,
  );

  void _publish() {
    if (_disposed) return;
    state = _snapshot();
  }

  void _cancelTimers() {
    _actTimer?.cancel();
    _actTimer = null;
    _warnTimer?.cancel();
    _warnTimer = null;
  }

  /// Decide what happens next: a bot move, a turn timer, or nothing because the
  /// round is over. Safe to call at any time; it always replaces the timers.
  void _schedule() {
    _cancelTimers();
    if (_disposed) return;

    if (_game.status != engine.GameStatus.inProgress) {
      _thinkingSeat = null;
      if (_lastStatus == engine.GameStatus.inProgress) {
        _lastStatus = _game.status;
        if (_game.winnerSeat == humanSeat) {
          _cues.win();
          ref.read(identityProvider.notifier).awardCoins(10);
        } else {
          _cues.lose();
        }
      }
      return;
    }
    _lastStatus = _game.status;
    if (_pausedAt != null) return;

    final seat = _game.currentTurnSeat;
    if (seat == humanSeat) {
      _thinkingSeat = null;
      final left = engine.turnMillisLeft(_game, _now());
      if (_cuedTurnAt != _game.turnStartedAt) {
        _cuedTurnAt = _game.turnStartedAt;
        _cues.turnStart();
      }
      if (left > 5000) {
        _warnTimer = Timer(
          Duration(milliseconds: left - 5000),
          () => _cues.timerWarning(),
        );
      }
      _actTimer = Timer(Duration(milliseconds: left), _onTimeout);
      return;
    }

    // A bot pauses long enough that the table can be read, no longer.
    _thinkingSeat = seat;
    final delay = 420 + (_rng() * 380).floor();
    _actTimer = Timer(Duration(milliseconds: delay), _botMove);
  }

  void _afterAction() {
    _schedule();
    _publish();
  }

  void _nudge(String message) {
    _notice = message;
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      if (_disposed) return;
      _notice = null;
      _publish();
    });
    _publish();
  }

  void clearNotice() {
    if (_notice == null) return;
    _noticeTimer?.cancel();
    _notice = null;
    _publish();
  }

  /// Tap a card. Refuses politely instead of throwing, and explains why.
  void play(String card) {
    if (_disposed) return;
    if (_game.status != engine.GameStatus.inProgress) return;
    if (_game.currentTurnSeat != humanSeat) {
      _cues.denied();
      _nudge('Wait for your turn.');
      return;
    }
    try {
      engine.playCard(_game, humanSeat, card, _now());
    } on engine.GameError catch (error) {
      _cues.denied();
      _nudge(
        error.code == 'ILLEGAL_MOVE'
            ? narrate.explainIllegal(_game.table, card)
            : narrate.errorMessage(error.code),
      );
      return;
    }
    _cues.cardPlayed();
    _notice = null;
    _noticeTimer?.cancel();
    _afterAction();
  }

  /// Pass. The engine refuses when a legal move exists, which is what turns into
  /// the nudge rather than a silent no-op.
  void passTurn() {
    if (_disposed) return;
    if (_game.status != engine.GameStatus.inProgress) return;
    try {
      engine.pass(_game, humanSeat, _now());
    } on engine.GameError catch (error) {
      _cues.denied();
      _nudge(narrate.errorMessage(error.code));
      return;
    }
    _cues.passed();
    _notice = null;
    _noticeTimer?.cancel();
    _afterAction();
  }

  void _botMove() {
    if (_disposed) return;
    final seat = _game.currentTurnSeat;
    if (_game.status != engine.GameStatus.inProgress || seat == humanSeat) {
      _afterAction();
      return;
    }
    final choice = bots.chooseMove(
      _config.difficulty,
      bots.BotContext(
        table: _game.table,
        hand: _game.hands[seat],
        handCounts: engine.handSizes(_game),
        mySeat: seat,
        rng: _rng,
      ),
    );
    try {
      if (choice == null) {
        engine.pass(_game, seat, _now());
        _cues.passedElsewhere();
      } else {
        engine.playCard(_game, seat, choice, _now());
        _cues.cardPlayedElsewhere();
      }
    } on engine.GameError catch (error) {
      // A bot must never be able to wedge the match. Fall back to the same
      // resolution a timed out seat gets.
      debugPrint('bot seat $seat refused: ${error.code}');
      engine.resolveTimeout(
        _game,
        _game.turnStartedAt + _game.timerSeconds * 1000,
        _rng,
      );
    }
    _thinkingSeat = null;
    _afterAction();
  }

  void _onTimeout() {
    if (_disposed) return;
    engine.resolveTimeout(_game, _now(), _rng);
    // Your own turn ran out, so say what the game did with it.
    if (_game.lastAction.isPlay) {
      _cues.cardPlayed();
    } else {
      _cues.passed();
    }
    _afterAction();
  }

  /// Deal the next round of a multi round match.
  void nextRound() {
    if (_disposed || _game.status != engine.GameStatus.roundOver) return;
    _game = engine.nextRound(_game, now: _now());
    _lastStatus = _game.status;
    _cuedTurnAt = null;
    _notice = null;
    _thinkingSeat = null;
    _afterAction();
  }

  /// Start a whole new match with the setup that is selected now.
  void restart() {
    if (_disposed) return;
    _config = ref.read(soloConfigProvider);
    _seats = _buildSeats(_config, ref.read(profileProvider));
    _pausedAt = null;
    _deal();
    _publish();
  }

  /// Backgrounding should not lose a turn in an offline game, so the clock stops
  /// and the current turn keeps whatever time it had left.
  void pauseClock() {
    if (_disposed || _pausedAt != null) return;
    _pausedAt = _now();
    _cancelTimers();
    _publish();
  }

  void resumeClock() {
    if (_disposed || _pausedAt == null) return;
    final away = _now() - _pausedAt!;
    _pausedAt = null;
    if (away > 0 && _game.status == engine.GameStatus.inProgress) {
      _game.turnStartedAt += away;
    }
    _afterAction();
  }
}

final soloGameProvider = AutoDisposeNotifierProvider<SoloController, SoloGame>(
  SoloController.new,
);
