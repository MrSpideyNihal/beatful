/// Beatful rules engine.
///
/// Ported from server/src/game/rules.js and kept in step with it by the golden
/// vectors in test/vectors. Pure functions only: no Flutter, no network, no
/// clock. Every decision about legality, table growth, passing and ranking lives
/// here, so the offline solo game and the bots share one implementation exactly
/// the way the server shares one with its own bots.
library;

import 'cards.dart' as cards;

/// One suit on the table.
///
/// Either both bounds are null, meaning the suit has not been opened, or both
/// are set with low <= 7 <= high. The only playable ranks are low - 1 and
/// high + 1.
class SuitPile {
  const SuitPile(this.low, this.high);

  const SuitPile.closed() : low = null, high = null;

  final int? low;
  final int? high;

  bool get isOpen => low != null;

  factory SuitPile.fromJson(Object? json) {
    if (json is! Map) return const SuitPile.closed();
    final low = json['low'];
    final high = json['high'];
    if (low == null || high == null) return const SuitPile.closed();
    return SuitPile((low as num).toInt(), (high as num).toInt());
  }

  Map<String, Object?> toJson() => {'low': low, 'high': high};

  @override
  bool operator ==(Object other) =>
      other is SuitPile && other.low == low && other.high == high;

  @override
  int get hashCode => Object.hash(low, high);

  @override
  String toString() => 'SuitPile($low, $high)';
}

/// The four suit piles. Immutable: applyMove returns a new table.
class TableState {
  TableState(Map<String, SuitPile> piles) : _piles = Map.unmodifiable(piles);

  factory TableState.empty() => TableState({
    for (final suit in cards.suits) suit: const SuitPile.closed(),
  });

  /// Tolerant of a missing suit so a malformed payload reads as closed rather
  /// than throwing inside a widget build.
  factory TableState.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    return TableState({
      for (final suit in cards.suits) suit: SuitPile.fromJson(map[suit]),
    });
  }

  final Map<String, SuitPile> _piles;

  SuitPile operator [](String suit) => _piles[suit] ?? const SuitPile.closed();

  Map<String, Object?> toJson() => {
    for (final suit in cards.suits) suit: this[suit].toJson(),
  };

  TableState withPile(String suit, SuitPile pile) {
    final next = Map<String, SuitPile>.of(_piles);
    next[suit] = pile;
    return TableState(next);
  }

  @override
  bool operator ==(Object other) {
    if (other is! TableState) return false;
    for (final suit in cards.suits) {
      if (other[suit] != this[suit]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(cards.suits.map((suit) => this[suit]));

  @override
  String toString() => 'TableState(${toJson()})';
}

/// The direction a card extends its suit.
enum MoveDirection {
  anchor,
  down,
  up;

  String get wire => name;

  static MoveDirection? fromWire(Object? value) {
    for (final entry in MoveDirection.values) {
      if (entry.name == value) return entry;
    }
    return null;
  }
}

/// The ranks a suit could accept next. A null side is exhausted.
typedef NextNeeded = ({int? down, int? up});

TableState createTable() => TableState.empty();

/// True when the table is structurally sound. Used to reject junk from the wire.
bool isValidTable(Object? json) {
  final map = json is Map ? json : null;
  if (map == null) return false;
  for (final suit in cards.suits) {
    final pile = map[suit];
    if (pile is! Map) return false;
    final low = pile['low'];
    final high = pile['high'];
    if ((low == null) != (high == null)) return false;
    if (low == null) continue;
    if (low is! int || high is! int) return false;
    if (low < cards.minRank || high > cards.maxRank) return false;
    if (low > cards.anchorRank || high < cards.anchorRank) return false;
  }
  return true;
}

bool isSuitOpen(TableState table, String suit) => table[suit].isOpen;

/// True when every rank of the suit is down.
bool isSuitComplete(TableState table, String suit) {
  final pile = table[suit];
  return pile.isOpen && pile.low == cards.minRank && pile.high == cards.maxRank;
}

int suitCardCount(TableState table, String suit) {
  final pile = table[suit];
  if (!pile.isOpen) return 0;
  return pile.high! - pile.low! + 1;
}

int tableCardCount(TableState table) {
  var total = 0;
  for (final suit in cards.suits) {
    total += suitCardCount(table, suit);
  }
  return total;
}

/// The two ranks this suit could accept right now. A closed suit needs its 7,
/// reported by needsAnchor rather than here.
NextNeeded nextNeeded(TableState table, String suit) {
  final pile = table[suit];
  if (!pile.isOpen) return (down: null, up: null);
  return (
    down: pile.low! > cards.minRank ? pile.low! - 1 : null,
    up: pile.high! < cards.maxRank ? pile.high! + 1 : null,
  );
}

bool needsAnchor(TableState table, String suit) => !table[suit].isOpen;

/// The single legality check. Every path that plays a card goes through this.
bool isLegalMove(TableState table, Object? card) {
  if (!cards.isCard(card)) return false;
  // Satte Pe Satta rule: game can only start by 7 of Hearts (H7).
  // Until 7 of Hearts is played, no other card is legal.
  if (!isSuitOpen(table, 'H')) {
    return card == 'H7';
  }
  final parsed = cards.parseCard(card as String);
  final pile = table[parsed.suit];
  if (!pile.isOpen) {
    // Suit is closed. Only the 7 opens it.
    return parsed.rank == cards.anchorRank;
  }
  if (parsed.rank >= pile.low! && parsed.rank <= pile.high!) return false;
  return parsed.rank == pile.low! - 1 || parsed.rank == pile.high! + 1;
}

/// Every card in the hand playable right now, in hand order, duplicates dropped.
List<String> legalMoves(TableState table, List<String> hand) {
  final seen = <String>{};
  final out = <String>[];
  for (final card in hand) {
    if (!seen.add(card)) continue;
    if (isLegalMove(table, card)) out.add(card);
  }
  return out;
}

bool hasLegalMove(TableState table, List<String> hand) {
  for (final card in hand) {
    if (isLegalMove(table, card)) return true;
  }
  return false;
}

/// A new table with the card added. Throws when the move is illegal, so callers
/// check isLegalMove first.
TableState applyMove(TableState table, String card) {
  if (!isLegalMove(table, card)) {
    throw StateError('illegal move: $card');
  }
  final parsed = cards.parseCard(card);
  final pile = table[parsed.suit];
  if (!pile.isOpen) {
    return table.withPile(
      parsed.suit,
      const SuitPile(cards.anchorRank, cards.anchorRank),
    );
  }
  if (parsed.rank == pile.low! - 1) {
    return table.withPile(parsed.suit, SuitPile(parsed.rank, pile.high));
  }
  return table.withPile(parsed.suit, SuitPile(pile.low, parsed.rank));
}

/// Which way a card would extend its suit. Drives the deal animation.
MoveDirection? moveDirection(TableState table, String card) {
  if (!isLegalMove(table, card)) return null;
  final parsed = cards.parseCard(card);
  final pile = table[parsed.suit];
  if (!pile.isOpen) return MoveDirection.anchor;
  return parsed.rank < pile.low! ? MoveDirection.down : MoveDirection.up;
}

/// Deal sizes: floor(52 / n) each, then one extra to the first 52 % n seats in
/// turn order.
List<int> dealCounts(int playerCount) {
  if (playerCount < 1) {
    throw ArgumentError.value(
      playerCount,
      'playerCount',
      'invalid player count',
    );
  }
  final base = 52 ~/ playerCount;
  final remainder = 52 % playerCount;
  return [
    for (var seat = 0; seat < playerCount; seat += 1)
      base + (seat < remainder ? 1 : 0),
  ];
}

/// Split a 52 card deck into hands. Nothing is left in a stock pile.
List<List<String>> dealHands(List<String> deck, int playerCount) {
  if (deck.length != 52) {
    throw ArgumentError('deal requires a 52 card deck');
  }
  final counts = dealCounts(playerCount);
  final hands = <List<String>>[];
  var cursor = 0;
  for (final count in counts) {
    hands.add(deck.sublist(cursor, cursor + count));
    cursor += count;
  }
  return hands;
}

/// Total pip value of cards in a hand. Ace=1, 2-10=value, Jack=11, Queen=12, King=13.
/// Empty hand (round winner) scores 0 penalty points.
int handPipScore(List<String> hand) {
  var total = 0;
  for (final card in hand) {
    total += cards.parseCard(card).rank;
  }
  return total;
}

/// Fewer penalty points (card pip value sum) is a better rank. Equal scores share
/// a rank and the next distinct score skips ahead (standard competition ranking:
/// 1, 2, 2, 4).
List<int> rankSeats(List<int> scores) {
  final order = [for (var seat = 0; seat < scores.length; seat += 1) seat];
  order.sort((a, b) {
    if (scores[a] != scores[b]) return scores[a] - scores[b];
    return a - b;
  });
  final ranks = List<int>.filled(scores.length, 0);
  var currentRank = 0;
  int? previousScore;
  for (var index = 0; index < order.length; index += 1) {
    final seat = order[index];
    if (previousScore == null || scores[seat] != previousScore) {
      currentRank = index + 1;
      previousScore = scores[seat];
    }
    ranks[seat] = currentRank;
  }
  return ranks;
}

/// A round ends the moment a hand is empty. Returns -1 while none is.
int findWinnerSeat(List<List<String>> hands) {
  for (var seat = 0; seat < hands.length; seat += 1) {
    if (hands[seat].isEmpty) return seat;
  }
  return -1;
}

/// Safety net for the turn loop. With a fully dealt deck this is unreachable,
/// but the loop guards on it rather than spinning.
bool isDeadlocked(TableState table, List<List<String>> hands) {
  for (final hand in hands) {
    if (hand.isNotEmpty && hasLegalMove(table, hand)) return false;
  }
  return true;
}
