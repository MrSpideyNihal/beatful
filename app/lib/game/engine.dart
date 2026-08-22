/// Round and turn machinery on top of the pure rules module.
///
/// Ported from server/src/game/engine.js. In an online match the server owns a
/// state exactly like this one and the client only ever sees publicView output;
/// in solo play the client owns it. Both paths render from a PublicView, so the
/// board does not care where the match is running.
library;

import 'cards.dart' as cards;
import 'rules.dart' as rules;

const int logLimit = 24;

/// A rule violation with a stable code, matching the server error codes so one
/// set of messages covers both.
class GameError implements Exception {
  GameError(this.code, [this.message]);

  final String code;
  final String? message;

  @override
  String toString() => 'GameError($code)';
}

enum GameStatus {
  inProgress('in_progress'),
  roundOver('round_over'),
  finished('finished');

  const GameStatus(this.wire);

  final String wire;

  static GameStatus fromWire(Object? value) {
    for (final status in GameStatus.values) {
      if (status.wire == value) return status;
    }
    return GameStatus.inProgress;
  }
}

/// One entry in the round log: the deal, a play, a pass or the round ending.
class ActionEntry {
  const ActionEntry({
    required this.type,
    required this.at,
    this.seatIndex,
    this.card,
    this.direction,
    this.auto = false,
    this.round,
    this.winnerSeat,
    this.ranks,
  });

  final String type;
  final int at;
  final int? seatIndex;
  final String? card;
  final rules.MoveDirection? direction;
  final bool auto;
  final int? round;
  final int? winnerSeat;
  final List<int>? ranks;

  bool get isPlay => type == 'play';

  bool get isPass => type == 'pass';

  factory ActionEntry.fromJson(Map<String, Object?> json) => ActionEntry(
    type: json['type'] as String? ?? 'deal',
    at: (json['at'] as num?)?.toInt() ?? 0,
    seatIndex: (json['seatIndex'] as num?)?.toInt(),
    card: json['card'] as String?,
    direction: rules.MoveDirection.fromWire(json['direction']),
    auto: json['auto'] == true,
    round: (json['round'] as num?)?.toInt(),
    winnerSeat: (json['winnerSeat'] as num?)?.toInt(),
    ranks: _intList(json['ranks']),
  );

  /// Shaped exactly like the server log entries, so a recorded server response
  /// and a locally produced one compare equal field for field.
  Map<String, Object?> toJson() => {
    'type': type,
    'at': at,
    if (seatIndex != null) 'seatIndex': seatIndex,
    if (card != null) 'card': card,
    if (direction != null) 'direction': direction!.wire,
    if (type == 'play' || type == 'pass') 'auto': auto,
    if (round != null) 'round': round,
    if (winnerSeat != null) 'winnerSeat': winnerSeat,
    if (ranks != null) 'ranks': ranks,
  };
}

class RoundResult {
  const RoundResult({
    required this.round,
    required this.winnerSeat,
    required this.ranks,
    required this.cardsRemaining,
  });

  final int round;
  final int winnerSeat;
  final List<int> ranks;
  final List<int> cardsRemaining;

  factory RoundResult.fromJson(Map<String, Object?> json) => RoundResult(
    round: (json['round'] as num?)?.toInt() ?? 1,
    winnerSeat: (json['winnerSeat'] as num?)?.toInt() ?? 0,
    ranks: _intList(json['ranks']) ?? const [],
    cardsRemaining: _intList(json['cardsRemaining']) ?? const [],
  );

  Map<String, Object?> toJson() => {
    'round': round,
    'winnerSeat': winnerSeat,
    'ranks': ranks,
    'cardsRemaining': cardsRemaining,
  };
}

/// Where a seat finished the whole match. Lower score is better.
class Standing {
  const Standing({
    required this.seatIndex,
    required this.score,
    required this.rank,
  });

  final int seatIndex;
  final int score;
  final int rank;

  factory Standing.fromJson(Map<String, Object?> json) => Standing(
    seatIndex: (json['seatIndex'] as num?)?.toInt() ?? 0,
    score: (json['score'] as num?)?.toInt() ?? 0,
    rank: (json['rank'] as num?)?.toInt() ?? 0,
  );

  Map<String, Object?> toJson() => {
    'seatIndex': seatIndex,
    'score': score,
    'rank': rank,
  };
}

List<int>? _intList(Object? value) {
  if (value is! List) return null;
  return [for (final entry in value) (entry as num).toInt()];
}

/// The full state of a round, hands included. Never hand this to the UI: use
/// publicView so one seat cannot read another seat's cards.
class GameState {
  GameState({
    required this.seatCount,
    required this.round,
    required this.rounds,
    required this.seed,
    required this.timerSeconds,
    required this.status,
    required this.table,
    required this.hands,
    required this.currentTurnSeat,
    required this.turnStartedAt,
    required this.scores,
    required this.roundResults,
    required this.lastAction,
    required this.log,
    required this.winnerSeat,
    required this.ranks,
    required this.passStreak,
  });

  final int seatCount;
  final int round;
  final int rounds;
  final int seed;
  final int timerSeconds;
  GameStatus status;
  rules.TableState table;
  final List<List<String>> hands;
  int currentTurnSeat;
  int turnStartedAt;
  final List<int> scores;
  final List<RoundResult> roundResults;
  ActionEntry lastAction;
  final List<ActionEntry> log;
  int? winnerSeat;
  List<int>? ranks;
  int passStreak;
}

/// Traditional sevens opener: whoever holds the seven of diamonds moves first.
/// Deterministic, easy to explain, and the first seat to act always has a move.
int findStartingSeat(List<List<String>> hands) {
  final opener = cards.makeCard('D', cards.anchorRank);
  for (var seat = 0; seat < hands.length; seat += 1) {
    if (hands[seat].contains(opener)) return seat;
  }
  return 0;
}

/// Deal a fresh round, carrying cumulative scores across rounds of a match.
GameState startRound({
  required int seatCount,
  required int timerSeconds,
  int rounds = 1,
  int round = 1,
  List<int>? scores,
  int? seed,
  int? now,
  bool shuffled = true,
}) {
  if (seatCount < 2 || seatCount > 8) {
    throw GameError('BAD_SEAT_COUNT', 'seat count must be between 2 and 8');
  }
  if (timerSeconds < 5 || timerSeconds > 120) {
    throw GameError(
      'BAD_TIMER',
      'turn timer must be between 5 and 120 seconds',
    );
  }

  final resolvedSeed = seed ?? cards.randomSeed();
  final resolvedNow = now ?? DateTime.now().millisecondsSinceEpoch;
  final rng = cards.createRng(resolvedSeed);
  final deck = shuffled
      ? cards.shuffle(cards.buildDeck(), rng)
      : cards.buildDeck();
  final hands = rules
      .dealHands(deck, seatCount)
      .map((hand) => cards.sortHand(hand))
      .toList(growable: false);

  final deal = ActionEntry(type: 'deal', at: resolvedNow, round: round);
  final state = GameState(
    seatCount: seatCount,
    round: round,
    rounds: rounds,
    seed: resolvedSeed,
    timerSeconds: timerSeconds,
    status: GameStatus.inProgress,
    table: rules.createTable(),
    hands: hands,
    currentTurnSeat: findStartingSeat(hands),
    turnStartedAt: resolvedNow,
    scores: scores != null && scores.length == seatCount
        ? List<int>.of(scores)
        : List<int>.filled(seatCount, 0),
    roundResults: <RoundResult>[],
    lastAction: deal,
    log: <ActionEntry>[deal],
    winnerSeat: null,
    ranks: null,
    passStreak: 0,
  );

  // Degenerate deal guard: with more seats than cards a seat could start empty
  // and has therefore already won. Unreachable at 8 seats or fewer, but the
  // engine still resolves it cleanly rather than dealing a turn to an empty hand.
  final emptySeat = rules.findWinnerSeat(hands);
  if (emptySeat >= 0) {
    _finishRound(state, emptySeat, resolvedNow);
  }
  return state;
}

List<int> handSizes(GameState state) => [
  for (final hand in state.hands) hand.length,
];

bool _seatInBounds(GameState state, int seatIndex) =>
    seatIndex >= 0 && seatIndex < state.seatCount;

void _pushLog(GameState state, ActionEntry entry) {
  state.log.add(entry);
  if (state.log.length > logLimit) {
    state.log.removeRange(0, state.log.length - logLimit);
  }
  state.lastAction = entry;
}

/// Milliseconds left on the current turn. Never negative.
int turnMillisLeft(GameState state, [int? now]) {
  if (state.status != GameStatus.inProgress) return 0;
  final at = now ?? DateTime.now().millisecondsSinceEpoch;
  final deadline = state.turnStartedAt + state.timerSeconds * 1000;
  final left = deadline - at;
  return left > 0 ? left : 0;
}

bool isTurnExpired(GameState state, [int? now]) =>
    state.status == GameStatus.inProgress && turnMillisLeft(state, now) == 0;

void _advanceTurn(GameState state, int now) {
  var seat = state.currentTurnSeat;
  for (var step = 1; step <= state.seatCount; step += 1) {
    final candidate = (state.currentTurnSeat + step) % state.seatCount;
    if (state.hands[candidate].isNotEmpty) {
      seat = candidate;
      break;
    }
  }
  state.currentTurnSeat = seat;
  state.turnStartedAt = now;
}

void _finishRound(GameState state, int winnerSeat, int now) {
  final sizes = handSizes(state);
  final ranks = rules.rankSeats(sizes);
  state.winnerSeat = winnerSeat;
  state.ranks = ranks;
  state.roundResults.add(
    RoundResult(
      round: state.round,
      winnerSeat: winnerSeat,
      ranks: ranks,
      cardsRemaining: sizes,
    ),
  );
  for (var seat = 0; seat < state.seatCount; seat += 1) {
    // Lower total is better: a win adds 1, last place adds seatCount.
    state.scores[seat] += ranks[seat];
  }
  state.status = state.round >= state.rounds
      ? GameStatus.finished
      : GameStatus.roundOver;
  _pushLog(
    state,
    ActionEntry(
      type: 'round_over',
      at: now,
      round: state.round,
      winnerSeat: winnerSeat,
      ranks: ranks,
    ),
  );
}

/// Play one card for a seat.
ActionEntry playCard(GameState state, int seatIndex, String card, [int? now]) {
  final at = now ?? DateTime.now().millisecondsSinceEpoch;
  if (state.status != GameStatus.inProgress) {
    throw GameError('ROUND_NOT_ACTIVE', 'the round is not accepting moves');
  }
  if (!_seatInBounds(state, seatIndex)) {
    throw GameError('BAD_SEAT', 'unknown seat');
  }
  if (state.currentTurnSeat != seatIndex) {
    throw GameError('NOT_YOUR_TURN', 'it is not your turn');
  }
  if (!cards.isCard(card)) {
    throw GameError('BAD_CARD', 'that is not a card');
  }
  final hand = state.hands[seatIndex];
  final handIndex = hand.indexOf(card);
  if (handIndex < 0) {
    throw GameError('CARD_NOT_IN_HAND', 'you do not hold that card');
  }
  if (!rules.isLegalMove(state.table, card)) {
    throw GameError('ILLEGAL_MOVE', 'that card cannot be played yet');
  }

  final direction = rules.moveDirection(state.table, card);
  state.table = rules.applyMove(state.table, card);
  hand.removeAt(handIndex);
  state.passStreak = 0;
  final entry = ActionEntry(
    type: 'play',
    at: at,
    seatIndex: seatIndex,
    card: card,
    direction: direction,
  );

  _pushLog(state, entry);
  if (hand.isEmpty) {
    _finishRound(state, seatIndex, at);
    return entry;
  }
  _advanceTurn(state, at);
  return entry;
}

/// Pass. Only legal with zero playable cards, so a mis-tap cannot throw away a
/// turn that could have been played. The UI nudges instead of sending.
ActionEntry pass(GameState state, int seatIndex, [int? now]) {
  final at = now ?? DateTime.now().millisecondsSinceEpoch;
  if (state.status != GameStatus.inProgress) {
    throw GameError('ROUND_NOT_ACTIVE', 'the round is not accepting moves');
  }
  if (!_seatInBounds(state, seatIndex)) {
    throw GameError('BAD_SEAT', 'unknown seat');
  }
  if (state.currentTurnSeat != seatIndex) {
    throw GameError('NOT_YOUR_TURN', 'it is not your turn');
  }
  if (rules.hasLegalMove(state.table, state.hands[seatIndex])) {
    throw GameError('MUST_PLAY', 'you still have a card you can play');
  }
  state.passStreak += 1;
  final entry = ActionEntry(type: 'pass', at: at, seatIndex: seatIndex);
  _pushLog(state, entry);
  _advanceTurn(state, at);
  return entry;
}

/// Timer expiry. The only way a turn resolves without a tap, and always driven
/// by the clock that owns the match.
ActionEntry? resolveTimeout(GameState state, int now, [cards.Rng? rng]) {
  if (state.status != GameStatus.inProgress) return null;
  if (!isTurnExpired(state, now)) return null;

  final seatIndex = state.currentTurnSeat;
  final hand = state.hands[seatIndex];
  final options = rules.legalMoves(state.table, hand);

  if (options.isEmpty) {
    state.passStreak += 1;
    final entry = ActionEntry(
      type: 'pass',
      at: now,
      seatIndex: seatIndex,
      auto: true,
    );
    _pushLog(state, entry);
    _advanceTurn(state, now);
    return entry;
  }

  final roll = rng ?? cards.createRng(cards.randomSeed());
  final pick = options[(roll() * options.length).floor() % options.length];
  final direction = rules.moveDirection(state.table, pick);
  state.table = rules.applyMove(state.table, pick);
  hand.remove(pick);
  state.passStreak = 0;
  final entry = ActionEntry(
    type: 'play',
    at: now,
    seatIndex: seatIndex,
    card: pick,
    direction: direction,
    auto: true,
  );

  _pushLog(state, entry);
  if (hand.isEmpty) {
    _finishRound(state, seatIndex, now);
    return entry;
  }
  _advanceTurn(state, now);
  return entry;
}

/// Begin the next round of a multi round match.
GameState nextRound(GameState state, {int? now, int? seed}) {
  if (state.status != GameStatus.roundOver) {
    throw GameError('ROUND_NOT_OVER', 'the current round is still running');
  }
  return startRound(
    seatCount: state.seatCount,
    timerSeconds: state.timerSeconds,
    rounds: state.rounds,
    round: state.round + 1,
    scores: state.scores,
    seed: seed,
    now: now,
  );
}

/// Final standings across every round. Lower total is better.
List<Standing> computeStandings(List<int> scores) {
  final order = [for (var seat = 0; seat < scores.length; seat += 1) seat];
  order.sort((a, b) {
    if (scores[a] != scores[b]) return scores[a] - scores[b];
    return a - b;
  });
  final out = List<Standing?>.filled(scores.length, null);
  var rank = 0;
  int? previous;
  for (var index = 0; index < order.length; index += 1) {
    final seat = order[index];
    if (previous == null || scores[seat] != previous) {
      rank = index + 1;
      previous = scores[seat];
    }
    out[seat] = Standing(seatIndex: seat, score: scores[seat], rank: rank);
  }
  return out.cast<Standing>();
}

List<Standing> matchStandings(GameState state) =>
    computeStandings(state.scores);

/// Everything one seat may see. Other hands are card counts only, and the legal
/// move list is computed here so the board never has to work it out itself.
PublicView publicView(GameState state, int? seatIndex, [int? now]) {
  final at = now ?? DateTime.now().millisecondsSinceEpoch;
  final mySeat = seatIndex != null && _seatInBounds(state, seatIndex)
      ? seatIndex
      : null;
  final hand = mySeat == null
      ? <String>[]
      : List<String>.of(state.hands[mySeat]);
  final legal = mySeat == null
      ? <String>[]
      : rules.legalMoves(state.table, hand);
  return PublicView(
    round: state.round,
    rounds: state.rounds,
    status: state.status,
    seatCount: state.seatCount,
    table: state.table,
    handCounts: handSizes(state),
    currentTurnSeat: state.currentTurnSeat,
    turnStartedAt: state.turnStartedAt,
    timerSeconds: state.timerSeconds,
    millisLeft: turnMillisLeft(state, at),
    yourSeat: mySeat,
    yourHand: hand,
    yourLegalMoves: legal,
    canPass:
        state.status == GameStatus.inProgress &&
        mySeat != null &&
        state.currentTurnSeat == mySeat &&
        legal.isEmpty,
    lastAction: state.lastAction,
    log: List<ActionEntry>.of(
      state.log.length > 8
          ? state.log.sublist(state.log.length - 8)
          : state.log,
    ),
    scores: List<int>.of(state.scores),
    roundResults: List<RoundResult>.of(state.roundResults),
    winnerSeat: state.winnerSeat,
    ranks: state.ranks == null ? null : List<int>.of(state.ranks!),
    standings: state.status == GameStatus.finished
        ? matchStandings(state)
        : null,
  );
}

/// The board's only input. Produced locally in solo play and parsed from the
/// server in an online match, identical either way.
class PublicView {
  const PublicView({
    required this.round,
    required this.rounds,
    required this.status,
    required this.seatCount,
    required this.table,
    required this.handCounts,
    required this.currentTurnSeat,
    required this.turnStartedAt,
    required this.timerSeconds,
    required this.millisLeft,
    required this.yourSeat,
    required this.yourHand,
    required this.yourLegalMoves,
    required this.canPass,
    required this.lastAction,
    required this.log,
    required this.scores,
    required this.roundResults,
    required this.winnerSeat,
    required this.ranks,
    required this.standings,
  });

  final int round;
  final int rounds;
  final GameStatus status;
  final int seatCount;
  final rules.TableState table;
  final List<int> handCounts;
  final int currentTurnSeat;
  final int turnStartedAt;
  final int timerSeconds;
  final int millisLeft;
  final int? yourSeat;
  final List<String> yourHand;
  final List<String> yourLegalMoves;
  final bool canPass;
  final ActionEntry? lastAction;
  final List<ActionEntry> log;
  final List<int> scores;
  final List<RoundResult> roundResults;
  final int? winnerSeat;
  final List<int>? ranks;
  final List<Standing>? standings;

  bool get isOver => status != GameStatus.inProgress;

  bool get isMyTurn =>
      status == GameStatus.inProgress &&
      yourSeat != null &&
      currentTurnSeat == yourSeat;

  bool isLegal(String card) => yourLegalMoves.contains(card);

  /// The same shape the server sends. Used to compare a locally computed view
  /// against a recorded server one, and to keep a solo game across a restart.
  Map<String, Object?> toJson() => {
    'round': round,
    'rounds': rounds,
    'status': status.wire,
    'seatCount': seatCount,
    'table': table.toJson(),
    'handCounts': handCounts,
    'currentTurnSeat': currentTurnSeat,
    'turnStartedAt': turnStartedAt,
    'timerSeconds': timerSeconds,
    'millisLeft': millisLeft,
    'yourSeat': yourSeat,
    'yourHand': yourHand,
    'yourLegalMoves': yourLegalMoves,
    'canPass': canPass,
    'lastAction': lastAction?.toJson(),
    'log': [for (final entry in log) entry.toJson()],
    'scores': scores,
    'roundResults': [for (final entry in roundResults) entry.toJson()],
    'winnerSeat': winnerSeat,
    'ranks': ranks,
    'standings': standings == null
        ? null
        : [for (final entry in standings!) entry.toJson()],
  };

  factory PublicView.fromJson(Map<String, Object?> json) => PublicView(
    round: (json['round'] as num?)?.toInt() ?? 1,
    rounds: (json['rounds'] as num?)?.toInt() ?? 1,
    status: GameStatus.fromWire(json['status']),
    seatCount: (json['seatCount'] as num?)?.toInt() ?? 0,
    table: rules.TableState.fromJson(json['table']),
    handCounts: _intList(json['handCounts']) ?? const [],
    currentTurnSeat: (json['currentTurnSeat'] as num?)?.toInt() ?? 0,
    turnStartedAt: (json['turnStartedAt'] as num?)?.toInt() ?? 0,
    timerSeconds: (json['timerSeconds'] as num?)?.toInt() ?? 15,
    millisLeft: (json['millisLeft'] as num?)?.toInt() ?? 0,
    yourSeat: (json['yourSeat'] as num?)?.toInt(),
    yourHand: _stringList(json['yourHand']),
    yourLegalMoves: _stringList(json['yourLegalMoves']),
    canPass: json['canPass'] == true,
    lastAction: json['lastAction'] is Map
        ? ActionEntry.fromJson(
            Map<String, Object?>.from(json['lastAction'] as Map),
          )
        : null,
    log: [
      for (final entry in (json['log'] as List? ?? const []))
        ActionEntry.fromJson(Map<String, Object?>.from(entry as Map)),
    ],
    scores: _intList(json['scores']) ?? const [],
    roundResults: [
      for (final entry in (json['roundResults'] as List? ?? const []))
        RoundResult.fromJson(Map<String, Object?>.from(entry as Map)),
    ],
    winnerSeat: (json['winnerSeat'] as num?)?.toInt(),
    ranks: _intList(json['ranks']),
    standings: json['standings'] is List
        ? [
            for (final entry in json['standings'] as List)
              Standing.fromJson(Map<String, Object?>.from(entry as Map)),
          ]
        : null,
  );
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return [for (final entry in value) entry as String];
}
