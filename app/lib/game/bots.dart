/// Bot players for solo matches.
///
/// Ported from server/src/game/bots.js so a solo game plays exactly like a
/// friends game with bots filling seats. Every tier picks from
/// rules.legalMoves(), the same function that validates a human move, so no tier
/// can invent its own idea of what is legal. chooseMove returns a card, or null
/// meaning pass, and null only when the hand genuinely has nothing playable.
library;

import 'cards.dart' as cards;
import 'rules.dart' as rules;

enum BotDifficulty {
  easy('easy', 'Easy', 'Plays whatever it can, in no particular order.'),
  medium(
    'medium',
    'Medium',
    'Empties its hand quickly and clears awkward cards.',
  ),
  hard(
    'hard',
    'Hard',
    'Counts the cards it has not seen and avoids helping you.',
  );

  const BotDifficulty(this.wire, this.label, this.blurb);

  final String wire;
  final String label;
  final String blurb;

  static BotDifficulty fromWire(Object? value) {
    for (final entry in BotDifficulty.values) {
      if (entry.wire == value) return entry;
    }
    return BotDifficulty.medium;
  }
}

/// Everything a bot is allowed to know: the table, its own hand, how many cards
/// everybody holds, and its seat. No peeking at another hand.
class BotContext {
  BotContext({
    required this.table,
    required this.hand,
    required this.handCounts,
    required this.mySeat,
    required this.rng,
  });

  final rules.TableState table;
  final List<String> hand;
  final List<int> handCounts;
  final int mySeat;
  final cards.Rng rng;
}

typedef _MoveShape = ({
  String suit,
  int rank,
  bool anchor,
  int step,
  List<int> openedRanks,
});

String _pickRandom(List<String> list, cards.Rng rng) {
  final index = (rng() * list.length).floor() % list.length;
  return list[index];
}

/// How far from the anchor a rank sits. Bigger means harder to place later.
int stuckness(int rank) => (rank - cards.anchorRank).abs();

/// How many of the bot's own cards follow this one outward without a gap.
/// Playing a card whose continuation is in hand keeps the initiative.
int ownRunDepth(List<String> hand, String suit, int fromRank, int step) {
  final held = hand.toSet();
  var depth = 0;
  var rank = fromRank + step;
  while (rank >= cards.minRank &&
      rank <= cards.maxRank &&
      held.contains('$suit$rank')) {
    depth += 1;
    rank += step;
  }
  return depth;
}

/// Which direction a legal card extends, and the rank slot it opens next. A 7
/// opens both directions at once.
_MoveShape _moveShape(rules.TableState table, String card) {
  final parsed = cards.parseCard(card);
  if (!rules.isSuitOpen(table, parsed.suit)) {
    return (
      suit: parsed.suit,
      rank: parsed.rank,
      anchor: true,
      step: 0,
      openedRanks: [cards.anchorRank - 1, cards.anchorRank + 1]
          .where((rank) => rank >= cards.minRank && rank <= cards.maxRank)
          .toList(),
    );
  }
  final step = parsed.rank < table[parsed.suit].low! ? -1 : 1;
  final opened = parsed.rank + step;
  return (
    suit: parsed.suit,
    rank: parsed.rank,
    anchor: false,
    step: step,
    openedRanks: opened >= cards.minRank && opened <= cards.maxRank
        ? [opened]
        : <int>[],
  );
}

/// Own cards further out in this direction, consecutive or not. They stay
/// stranded until the direction is built out to them, so pushing that way is
/// progress even when the very next rank is missing.
int ownBeyond(List<String> hand, String suit, int fromRank, int step) {
  var count = 0;
  for (final code in hand) {
    final parsed = cards.parseCard(code);
    if (parsed.suit != suit) continue;
    if (step > 0 ? parsed.rank > fromRank : parsed.rank < fromRank) count += 1;
  }
  return count;
}

int chainValue(List<String> hand, rules.TableState table, String card) {
  final shape = _moveShape(table, card);
  if (shape.anchor) {
    return ownRunDepth(hand, shape.suit, cards.anchorRank, -1) +
        ownRunDepth(hand, shape.suit, cards.anchorRank, 1);
  }
  return ownRunDepth(hand, shape.suit, shape.rank, shape.step);
}

/// Cards already on the table, derived from the pile bounds.
List<String> tableCards(rules.TableState table) {
  final out = <String>[];
  for (final suit in cards.suits) {
    final pile = table[suit];
    if (!pile.isOpen) continue;
    for (var rank = pile.low!; rank <= pile.high!; rank += 1) {
      out.add('$suit$rank');
    }
  }
  return out;
}

/// Easy: uniform choice over every legal move.
String? chooseEasy(BotContext ctx) {
  final options = rules.legalMoves(ctx.table, ctx.hand);
  if (options.isEmpty) return null;
  return _pickRandom(options, ctx.rng);
}

/// Medium: empty the hand fast. Values keeping a run going and dumps cards far
/// from the anchor while it still can, since those are what strand a hand.
String? chooseMedium(BotContext ctx) {
  final options = rules.legalMoves(ctx.table, ctx.hand);
  if (options.isEmpty) return null;
  if (options.length == 1) return options[0];

  String? best;
  var bestScore = double.negativeInfinity;
  for (final card in options) {
    final parsed = cards.parseCard(card);
    final chain = chainValue(ctx.hand, ctx.table, card);
    var score = (chain * 12 + stuckness(parsed.rank) * 3).toDouble();
    // Opening a suit is worth extra when the bot holds cards next to the anchor.
    if (!rules.isSuitOpen(ctx.table, parsed.suit)) score += 4 + chain * 4;
    score += ctx.rng() * 0.5; // stable tie break
    if (score > bestScore) {
      bestScore = score;
      best = card;
    }
  }
  return best;
}

/// Hard: everything medium does, plus card counting.
///
/// The whole deck is dealt, so any card neither on the table nor in this hand is
/// provably in an opponent hand. The slot a move opens is therefore either useful
/// to this bot or a direct gift to somebody else, and a gift costs more when an
/// opponent is nearly out of cards.
String? chooseHard(BotContext ctx) {
  final options = rules.legalMoves(ctx.table, ctx.hand);
  if (options.isEmpty) return null;
  if (options.length == 1) return options[0];

  final held = ctx.hand.toSet();
  final onTable = tableCards(ctx.table).toSet();
  var closestOpponent = 99;
  for (var seat = 0; seat < ctx.handCounts.length; seat += 1) {
    if (seat == ctx.mySeat) continue;
    if (ctx.handCounts[seat] < closestOpponent) {
      closestOpponent = ctx.handCounts[seat];
    }
  }
  // Somebody about to win makes every gift much more expensive.
  final threat = closestOpponent <= 2
      ? 3.0
      : closestOpponent <= 4
      ? 1.8
      : 1.0;

  String? best;
  var bestScore = double.negativeInfinity;
  for (final card in options) {
    final parsed = cards.parseCard(card);
    final shape = _moveShape(ctx.table, card);
    final chain = chainValue(ctx.hand, ctx.table, card);

    var score = (chain * 14 + stuckness(parsed.rank) * 4).toDouble();

    if (shape.anchor) {
      score +=
          (ownBeyond(ctx.hand, parsed.suit, cards.anchorRank, -1) +
              ownBeyond(ctx.hand, parsed.suit, cards.anchorRank, 1)) *
          7;
      // A suit nobody has opened is where dead weight collects: open it.
      score += 5 + chain * 5;
    } else {
      score += ownBeyond(ctx.hand, parsed.suit, parsed.rank, shape.step) * 7;
    }

    for (final openedRank in shape.openedRanks) {
      final openedCard = '${parsed.suit}$openedRank';
      if (held.contains(openedCard)) {
        score += 10; // opens a slot only this bot can fill
      } else if (!onTable.contains(openedCard)) {
        score -= 9 * threat; // provably hands an opponent a playable card
      }
    }

    // Holding the one card that gates a whole direction is real leverage, but
    // only while the bot still has other work to do.
    if (!shape.anchor && chain == 0 && ctx.hand.length > 3) {
      score -= 4;
    }

    score += ctx.rng() * 0.5;
    if (score > bestScore) {
      bestScore = score;
      best = card;
    }
  }
  return best;
}

/// Returns a legal card, or null when the seat must pass.
String? chooseMove(BotDifficulty difficulty, BotContext ctx) {
  final choice = switch (difficulty) {
    BotDifficulty.easy => chooseEasy(ctx),
    BotDifficulty.medium => chooseMedium(ctx),
    BotDifficulty.hard => chooseHard(ctx),
  };
  if (choice == null) return null;
  // Belt and braces: never hand back something the rules would reject.
  if (!rules.isLegalMove(ctx.table, choice)) {
    final options = rules.legalMoves(ctx.table, ctx.hand);
    return options.isEmpty ? null : options[0];
  }
  return choice;
}
