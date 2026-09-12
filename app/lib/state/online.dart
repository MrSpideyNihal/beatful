/// The online room: one long poll loop, and the moves that jump the queue.
///
/// The server is the authority for everything here. This controller never decides
/// whether a move is legal, who won, or whether a turn ran out: it sends the
/// intent, takes the room the server sends back, and draws it.
///
/// Two rules shape the polling, both from the spec:
///   - a player's own move is never delayed by a poll, so play and pass apply the
///     response the moment it lands
///   - polling pauses on your own turn and while the app is in the background,
///     replaced by a light snapshot heartbeat so presence stays honest
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/engine.dart' as engine;
import '../game/narrate.dart' as narrate;
import '../models/room.dart';
import '../services/api.dart';
import '../services/cues.dart';
import 'identity.dart';

/// How often to check in while the long poll is parked, which is either your own
/// turn or a backgrounded app. Comfortably inside the server's disconnect grace.
const Duration _heartbeat = Duration(seconds: 20);

/// Longest gap between retries after the connection drops.
const Duration _maxBackoff = Duration(seconds: 8);

enum RoomStage {
  /// No room. The friends screen is where you get one.
  none,

  /// Waiting for the first room object.
  joining,

  /// In a room, lobby or match.
  live,

  /// The room ended or we left. Nothing more to poll.
  closed,
}

@immutable
class OnlineRoom {
  const OnlineRoom({
    this.stage = RoomStage.none,
    this.room,
    this.notice,
    this.trouble,
    this.busy = false,
    this.closedReason,
  });

  final RoomStage stage;
  final RoomView? room;

  /// A short message for a refused tap or a host action that was declined.
  final String? notice;

  /// The connection banner. Non null means the poll loop is struggling.
  final String? trouble;

  /// A request is in flight, so buttons show progress instead of re-firing.
  final bool busy;

  /// Why the room went away, shown after a kick or a host closing the lobby.
  final String? closedReason;

  bool get hasRoom => room != null;

  /// The seat a bot is about to move in, so its badge can show a thinking dot.
  int? get thinkingSeat {
    final view = room;
    if (view == null || !view.isPlaying) return null;
    final game = view.game;
    if (game == null || game.status != engine.GameStatus.inProgress) return null;
    for (final player in view.players) {
      if (player.seatIndex == game.currentTurnSeat) {
        return player.isBot ? player.seatIndex : null;
      }
    }
    return null;
  }

  OnlineRoom copyWith({
    RoomStage? stage,
    RoomView? room,
    String? notice,
    bool clearNotice = false,
    String? trouble,
    bool clearTrouble = false,
    bool? busy,
    String? closedReason,
  }) => OnlineRoom(
    stage: stage ?? this.stage,
    room: room ?? this.room,
    notice: clearNotice ? null : (notice ?? this.notice),
    trouble: clearTrouble ? null : (trouble ?? this.trouble),
    busy: busy ?? this.busy,
    closedReason: closedReason ?? this.closedReason,
  );
}

class OnlineController extends Notifier<OnlineRoom> {
  Timer? _noticeTimer;
  Timer? _wakeTimer;
  Timer? _beatTimer;

  bool _polling = false;
  bool _stopped = true;
  bool _backgrounded = false;
  int _failures = 0;

  /// Notices already shown, so a re-poll of the same room does not repeat them.
  final Set<String> _seenNotices = {};

  String? _lastActionKey;
  bool _cuedResult = false;
  int? _cuedTurnAt;

  @override
  OnlineRoom build() {
    ref.onDispose(_stopEverything);
    return const OnlineRoom();
  }

  Api get _api => ref.read(apiProvider);

  Cues get _cues => ref.read(cuesProvider);

  RoomView? get _room => state.room;

  /* ------------------------------------------------------------- lifecycle */

  /// Takes the room object returned by create or join and starts following it.
  void enter(RoomView room) {
    _stopped = false;
    _backgrounded = false;
    _failures = 0;
    _seenNotices
      ..clear()
      ..addAll(room.notices.map((notice) => notice.id));
    _lastActionKey = _keyOf(room.game?.lastAction);
    _cuedResult = false;
    _cuedTurnAt = null;
    state = OnlineRoom(stage: RoomStage.live, room: room);
    _drive();
  }

  /// Rejoins a room the app already knows the code of, for instance after a cold
  /// start on a deep link.
  Future<bool> joinByCode(String code) async {
    state = state.copyWith(stage: RoomStage.joining, busy: true, clearTrouble: true);
    try {
      final response = await _api.joinRoom(code);
      final room = _roomFrom(response);
      if (room == null) throw const ApiFailure('SERVER_ERROR', 'The room came back empty.');
      enter(room);
      return true;
    } on ApiFailure catch (failure) {
      state = OnlineRoom(
        stage: RoomStage.none,
        notice: narrate.errorMessage(failure.code, failure.message),
      );
      return false;
    }
  }

  /// Starts a rematch in the same room with the same players and same room code.
  Future<bool> playAgain() async {
    final old = _room;
    if (old == null || state.busy) return false;
    state = state.copyWith(busy: true, clearNotice: true);
    try {
      final updated = _roomFrom(await _api.rematch(old.roomId));
      if (updated != null) {
        _cuedResult = false;
        state = state.copyWith(room: updated, busy: false);
      }
      return true;
    } on ApiFailure catch (failure) {
      state = state.copyWith(
        busy: false,
        notice: narrate.errorMessage(failure.code, failure.message),
      );
      return false;
    }
  }

  /// Leaves for good. Safe to call when there is no room.
  Future<void> leave() async {
    final room = _room;
    _stopEverything();
    state = const OnlineRoom();
    if (room == null) return;
    try {
      await _api.leaveRoom(room.roomId);
    } on ApiFailure catch (failure) {
      // Leaving is best effort. The server drops an absent seat on its own.
      debugPrint('leave not acknowledged: ${failure.code}');
    }
    await ref.read(identityProvider.notifier).refresh();
  }

  /// Backgrounded. The held connection is dropped so the server can release the
  /// slot, and a heartbeat keeps the seat marked as present.
  void suspend() {
    if (_stopped || _backgrounded) return;
    _backgrounded = true;
    _wakeTimer?.cancel();
    _startBeat();
  }

  void resumeFromBackground() {
    if (_stopped || !_backgrounded) return;
    _backgrounded = false;
    _stopBeat();
    _failures = 0;
    unawaited(refresh());
    _drive();
  }

  void _stopEverything() {
    _stopped = true;
    _wakeTimer?.cancel();
    _wakeTimer = null;
    _noticeTimer?.cancel();
    _noticeTimer = null;
    _stopBeat();
  }

  /* ---------------------------------------------------------------- polling */

  /// True while the long poll should be parked rather than held open.
  bool get _parked {
    if (_backgrounded) return true;
    final room = _room;
    if (room == null) return false;
    // Your own turn: the next thing that can change the room is your tap, or the
    // server's timeout, and _armTurnWake covers the timeout.
    return room.isYourTurn;
  }

  /// Makes sure exactly one poll is in flight when one should be.
  void _drive() {
    if (_stopped || _polling) return;
    final room = _room;
    if (room == null || state.stage != RoomStage.live) return;
    if (_parked) {
      _armTurnWake(room);
      _startBeat();
      return;
    }
    _stopBeat();
    _polling = true;
    unawaited(_pollOnce(room));
  }

  /// While it is your turn nothing polls, so the client would miss the server
  /// auto playing an expired turn. This wakes up just after the deadline.
  void _armTurnWake(RoomView room) {
    _wakeTimer?.cancel();
    final game = room.game;
    if (game == null || !room.isYourTurn) return;
    final wait = game.millisLeft + 800;
    _wakeTimer = Timer(Duration(milliseconds: wait), () {
      _wakeTimer = null;
      unawaited(refresh());
    });
  }

  void _startBeat() {
    _beatTimer ??= Timer.periodic(_heartbeat, (_) => unawaited(refresh()));
  }

  void _stopBeat() {
    _beatTimer?.cancel();
    _beatTimer = null;
  }

  Future<void> _pollOnce(RoomView room) async {
    try {
      final response = await _api.pollRoom(room.roomId, room.version);
      _failures = 0;
      if (state.trouble != null) state = state.copyWith(clearTrouble: true);
      final outcome = PollOutcome.fromJson(response);
      if (outcome.changed && outcome.room != null) _apply(outcome.room!);
    } on ApiFailure catch (failure) {
      _onPollFailure(failure);
    } catch (error) {
      debugPrint('poll fault: $error');
      _onPollFailure(const ApiFailure('OFFLINE', 'Lost the connection.'));
    } finally {
      _polling = false;
    }
    if (_stopped) return;
    if (_failures == 0) {
      // Immediately re-issue, which is what makes long polling feel live.
      _drive();
      return;
    }
    final wait = _backoff();
    _wakeTimer?.cancel();
    _wakeTimer = Timer(wait, () {
      _wakeTimer = null;
      _drive();
    });
  }

  Duration _backoff() {
    final ms = 400 * _failures * _failures;
    return ms >= _maxBackoff.inMilliseconds
        ? _maxBackoff
        : Duration(milliseconds: ms);
  }

  void _onPollFailure(ApiFailure failure) {
    // The room is gone for good: stop rather than hammering a dead id.
    if (failure.code == 'ROOM_NOT_FOUND' || failure.code == 'NOT_IN_ROOM') {
      _stopEverything();
      state = OnlineRoom(
        stage: RoomStage.closed,
        closedReason: failure.code == 'ROOM_NOT_FOUND'
            ? 'That room has closed.'
            : 'You are no longer in that room.',
      );
      return;
    }
    if (failure.isAuth) {
      _stopEverything();
      state = state.copyWith(
        trouble: 'Signed out. Restart the app to reconnect.',
      );
      unawaited(ref.read(identityProvider.notifier).connect());
      return;
    }
    _failures += 1;
    // One dropped poll is normal on a phone. Only say something once it looks
    // like a real outage.
    if (_failures >= 2) {
      state = state.copyWith(
        trouble: failure.waking
            ? 'Reconnecting to the game server.'
            : 'Connection lost. Trying again. Your turns still play out on the timer.',
      );
    }
  }

  /// A snapshot with no waiting. Also the presence heartbeat.
  Future<void> refresh() async {
    final room = _room;
    if (_stopped || room == null) return;
    try {
      final response = await _api.roomSnapshot(room.roomId);
      final fresh = _roomFrom(response);
      if (fresh != null) {
        _failures = 0;
        _apply(fresh);
        if (state.trouble != null) state = state.copyWith(clearTrouble: true);
      }
    } on ApiFailure catch (failure) {
      _onPollFailure(failure);
    }
  }

  /* ------------------------------------------------------------------ moves */

  /// Applies the local player's card immediately. The response is the new room,
  /// so this never waits on the poll loop.
  Future<void> play(String card) async {
    final room = _room;
    if (room == null || !room.isPlaying) return;
    final game = room.game;
    if (game == null) return;
    if (!game.isMyTurn) {
      _cues.denied();
      _nudge('Wait for your turn.');
      return;
    }
    if (!game.isLegal(card)) {
      // Refused locally with a reason, which is a nicer answer than a round trip
      // to be told the same thing. The server still validates every accepted move.
      _cues.denied();
      _nudge(narrate.explainIllegal(game.table, card));
      return;
    }
    await _send(
      () => _api.play(room.roomId, card),
      onDone: () => _cues.cardPlayed(),
    );
  }

  Future<void> passTurn() async {
    final room = _room;
    if (room == null || !room.isPlaying) return;
    final game = room.game;
    if (game == null) return;
    if (!game.isMyTurn) {
      _cues.denied();
      _nudge('Wait for your turn.');
      return;
    }
    if (game.yourLegalMoves.isNotEmpty) {
      _cues.denied();
      _nudge(narrate.errorMessage('MUST_PLAY'));
      return;
    }
    await _send(() => _api.pass(room.roomId), onDone: () => _cues.passed());
  }

  /* ------------------------------------------------------------ room control */

  Future<void> setReady(bool ready) async {
    final room = _room;
    if (room == null) return;
    await _send(() => _api.setReady(room.roomId, ready), onDone: _cues.tap);
  }

  Future<void> start() async {
    final room = _room;
    if (room == null) return;
    await _send(() => _api.startGame(room.roomId));
  }

  Future<void> applySettings(Map<String, Object?> patch) async {
    final room = _room;
    if (room == null) return;
    await _send(() => _api.updateSettings(room.roomId, patch));
  }

  Future<void> addBot(String difficulty) async {
    final room = _room;
    if (room == null) return;
    await _send(() => _api.addBot(room.roomId, difficulty));
  }

  Future<void> kick(String userId) async {
    final room = _room;
    if (room == null) return;
    await _send(() => _api.kick(room.roomId, userId));
  }

  Future<void> setLocked(bool locked) async {
    final room = _room;
    if (room == null) return;
    await _send(() => _api.setLocked(room.roomId, locked));
  }

  /// Hands an abandoned seat to a bot. Host only, and only once the seat has
  /// actually gone quiet, which the server enforces.
  Future<void> handSeatToBot(int seatIndex) async {
    final room = _room;
    if (room == null) return;
    await _send(() => _api.botTakeover(room.roomId, seatIndex));
  }

  Future<void> sendChat({int? messageIndex, String? text}) async {
    final room = _room;
    if (room == null) return;
    await _send(
      () => _api.sendChat(room.roomId, messageIndex: messageIndex, text: text),
      onDone: _cues.tap,
    );
  }

  /// One request that returns a room, with the busy flag and the error wording
  /// handled the same way every time.
  Future<void> _send(
    Future<Map<String, Object?>> Function() request, {
    VoidCallback? onDone,
  }) async {
    if (state.busy) return;
    state = state.copyWith(busy: true, clearNotice: true);
    try {
      final fresh = _roomFrom(await request());
      state = state.copyWith(busy: false);
      if (fresh != null) {
        _apply(fresh);
        onDone?.call();
      }
    } on ApiFailure catch (failure) {
      state = state.copyWith(busy: false);
      _cues.denied();
      if (failure.code == 'ROOM_NOT_FOUND' || failure.code == 'NOT_IN_ROOM') {
        _onPollFailure(failure);
        return;
      }
      _nudge(narrate.errorMessage(failure.code, failure.message));
      // The refusal may be because the room moved on. Catch up.
      unawaited(refresh());
    }
  }

  /* ------------------------------------------------------------------ state */

  RoomView? _roomFrom(Map<String, Object?> response) {
    final raw = response['room'];
    if (raw is! Map) return null;
    return RoomView.fromJson(Map<String, Object?>.from(raw));
  }

  void _apply(RoomView fresh) {
    if (_stopped) return;
    final previous = _room;
    // An out of order response, for instance a slow snapshot landing after a
    // fast poll, must never move the board backwards.
    if (previous != null && fresh.version < previous.version) return;

    state = state.copyWith(stage: RoomStage.live, room: fresh, clearTrouble: true);
    _announce(fresh);
    _cue(fresh);
    _drive();
  }

  /// Room level events, such as somebody joining or a seat going quiet. Match
  /// events are already narrated on the board from lastAction.
  void _announce(RoomView room) {
    for (final notice in room.notices) {
      if (_seenNotices.add(notice.id) && notice.isAlert) {
        if (notice.isChat) _cues.tap();
        _nudge(notice.text);
      }
    }
    if (_seenNotices.length > 40) {
      // Only the newest four ever arrive, so the set only needs to outlive them.
      final keep = room.notices.map((notice) => notice.id).toSet();
      _seenNotices
        ..clear()
        ..addAll(keep);
    }
  }

  void _cue(RoomView room) {
    final game = room.game;
    if (game == null) return;

    final key = _keyOf(game.lastAction);
    if (key != _lastActionKey) {
      _lastActionKey = key;
      final action = game.lastAction;
      if (action != null && action.seatIndex != room.yourSeat) {
        if (action.isPlay) {
          _cues.cardPlayedElsewhere();
        } else if (action.isPass) {
          _cues.passedElsewhere();
        }
      }
    }

    if (game.isMyTurn && _cuedTurnAt != game.turnStartedAt) {
      _cuedTurnAt = game.turnStartedAt;
      _cues.turnStart();
    }

    if (game.status == engine.GameStatus.finished && !_cuedResult) {
      _cuedResult = true;
      final won = _finishedFirst(room);
      if (won) {
        _cues.win();
      } else {
        _cues.lose();
      }
      if (room.settings.coinMatch && room.result != null) _cues.coins();
      // The balance moved, so pull it before Home shows the coin pill again.
      unawaited(ref.read(identityProvider.notifier).refresh());
    }
  }

  bool _finishedFirst(RoomView room) {
    final seat = room.yourSeat;
    if (seat == null) return false;
    for (final standing in room.result?.standings ?? const []) {
      if (standing.seatIndex == seat) return standing.rank == 1;
    }
    return room.game?.winnerSeat == seat;
  }

  String? _keyOf(engine.ActionEntry? action) => action == null
      ? null
      : '${action.type}:${action.at}:${action.seatIndex}:${action.card}';

  void _nudge(String message) {
    state = state.copyWith(notice: message);
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      _noticeTimer = null;
      if (_stopped && state.stage == RoomStage.none) return;
      state = state.copyWith(clearNotice: true);
    });
  }

  void clearNotice() {
    if (state.notice == null) return;
    _noticeTimer?.cancel();
    state = state.copyWith(clearNotice: true);
  }

  /// A line the client wants to put in the room's notice area itself, such as
  /// confirming the invite reached the clipboard. Nothing about the room changes.
  void announce(String message) => _nudge(message);
}

/// One room at a time, kept alive across the lobby and board screens so a
/// navigation does not restart the poll loop.
final onlineRoomProvider = NotifierProvider<OnlineController, OnlineRoom>(
  OnlineController.new,
);
