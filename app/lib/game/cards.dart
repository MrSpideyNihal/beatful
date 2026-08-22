/// Card primitives.
///
/// Ported from server/src/game/cards.js. The server is the only authority in an
/// online match, but solo play runs entirely on the device, so the engine exists
/// in both languages. test/rules_vectors_test.dart replays golden vectors
/// generated from the Node engine, so the two cannot drift: change this file and
/// the vectors have to be regenerated with `npm run vectors` in server, or the
/// tests go red on both sides.
///
/// A card is a compact code: suit letter plus rank number. "H1" is the ace of
/// hearts, "S7" the seven of spades, "D13" the king of diamonds. Ranks run 1 to
/// 13 with no wrap around, so the ace is strictly low and the king strictly high.
library;

import 'dart:math' as math;

const List<String> suits = ['H', 'D', 'C', 'S'];

const Map<String, String> suitNames = {
  'H': 'hearts',
  'D': 'diamonds',
  'C': 'clubs',
  'S': 'spades',
};

const Map<String, String> suitSymbols = {
  'H': '♥',
  'D': '♦',
  'C': '♣',
  'S': '♠',
};

const Map<int, String> rankLabels = {
  1: 'A',
  2: '2',
  3: '3',
  4: '4',
  5: '5',
  6: '6',
  7: '7',
  8: '8',
  9: '9',
  10: '10',
  11: 'J',
  12: 'Q',
  13: 'K',
};

/// Face rank words, used both by the image file names and by spoken labels.
const Map<int, String> _rankWords = {
  1: 'ace',
  11: 'jack',
  12: 'queen',
  13: 'king',
};

const int minRank = 1;
const int maxRank = 13;
const int anchorRank = 7;
const int deckSize = 52;

final RegExp _rankDigits = RegExp(r'^[0-9]{1,2}$');

/// A seeded generator. Returns a double in [0, 1).
typedef Rng = double Function();

/// Build the card code for a suit and rank.
String makeCard(String suit, int rank) {
  if (!suits.contains(suit)) {
    throw ArgumentError.value(suit, 'suit', 'invalid suit');
  }
  if (rank < minRank || rank > maxRank) {
    throw ArgumentError.value(rank, 'rank', 'invalid rank');
  }
  return '$suit$rank';
}

/// True when the value is a syntactically valid card code.
bool isCard(Object? code) {
  if (code is! String || code.length < 2 || code.length > 3) return false;
  if (!suits.contains(code[0])) return false;
  final rest = code.substring(1);
  if (!_rankDigits.hasMatch(rest)) return false;
  final rank = int.tryParse(rest);
  // Rejects padded forms such as "H07", which would otherwise parse to 7.
  if (rank == null || rank.toString() != rest) return false;
  return rank >= minRank && rank <= maxRank;
}

/// Split a card code into its suit and rank.
({String suit, int rank}) parseCard(String code) {
  if (!isCard(code)) {
    throw ArgumentError.value(code, 'code', 'invalid card code');
  }
  return (suit: code[0], rank: int.parse(code.substring(1)));
}

String suitOf(String code) => parseCard(code).suit;

int rankOf(String code) => parseCard(code).rank;

/// Short label such as "8" followed by the suit symbol. Used in notices.
String cardLabel(String code) {
  final parsed = parseCard(code);
  return '${rankLabels[parsed.rank]}${suitSymbols[parsed.suit]}';
}

/// Spoken form for screen readers, where a suit symbol reads as nothing useful.
String cardSpokenLabel(String code) {
  final parsed = parseCard(code);
  final rank = _rankWords[parsed.rank] ?? parsed.rank.toString();
  return '$rank of ${suitNames[parsed.suit]}';
}

/// Path of the face image for a card, matching the files in assets/cards.
String cardImageAsset(String code) {
  final parsed = parseCard(code);
  final rank = _rankWords[parsed.rank] ?? parsed.rank.toString();
  return 'assets/cards/${rank}_of_${suitNames[parsed.suit]}.png';
}

/// Fresh ordered 52 card deck. No jokers.
List<String> buildDeck() {
  final deck = <String>[];
  for (final suit in suits) {
    for (var rank = minRank; rank <= maxRank; rank += 1) {
      deck.add('$suit$rank');
    }
  }
  return deck;
}

int _imul(int a, int b) => (a * b) & 0xFFFFFFFF;

/// Deterministic mulberry32, bit for bit the same generator as the server.
///
/// Every intermediate value is masked back to 32 bits because Dart integers are
/// 64 bit while the reference implementation runs on 32 bit operators.
Rng createRng(num seed) {
  var state = (seed.isFinite ? seed.floor() : 0) & 0xFFFFFFFF;
  if (state == 0) state = 0x9e3779b9;
  return () {
    state = (state + 0x6d2b79f5) & 0xFFFFFFFF;
    var t = state;
    t = _imul(t ^ (t >> 15), t | 1);
    t = (t ^ (t + _imul(t ^ (t >> 7), t | 61))) & 0xFFFFFFFF;
    return ((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0;
  };
}

final math.Random _entropy = math.Random();

/// A seed for a fresh solo round. Recorded on the state so a hand is replayable.
int randomSeed() => _entropy.nextInt(0xFFFFFFFF);

/// Fisher Yates shuffle. Returns a new list, never mutates the input.
List<String> shuffle(List<String> cards, [Rng? rng]) {
  final next = rng ?? createRng(randomSeed());
  final out = List<String>.of(cards);
  for (var i = out.length - 1; i > 0; i -= 1) {
    final j = (next() * (i + 1)).floor();
    final tmp = out[i];
    out[i] = out[j];
    out[j] = tmp;
  }
  return out;
}

/// Hand display order: suit order first, then rank.
List<String> sortHand(List<String> cards) {
  final out = List<String>.of(cards);
  out.sort((a, b) {
    final ca = parseCard(a);
    final cb = parseCard(b);
    if (ca.suit != cb.suit) {
      return suits.indexOf(ca.suit) - suits.indexOf(cb.suit);
    }
    return ca.rank - cb.rank;
  });
  return out;
}
