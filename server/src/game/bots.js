'use strict';

/**
 * Bot players.
 *
 * All three tiers pick from rules.legalMoves(), which is the same function the
 * API route uses to validate a human move. No tier has its own idea of what is
 * legal, so bot behaviour can never drift away from the real rules.
 *
 * chooseMove returns a card code to play, or null meaning "pass". Null is only
 * ever returned when the hand genuinely has zero legal moves.
 */

const { parseCard, ANCHOR_RANK, MIN_RANK, MAX_RANK, SUITS } = require('./cards');
const rules = require('./rules');

const DIFFICULTIES = ['easy', 'medium', 'hard'];

function pickRandom(list, rng) {
  const next = typeof rng === 'function' ? rng : Math.random;
  const index = Math.floor(next() * list.length) % list.length;
  return list[index];
}

/** How far from the anchor a rank sits. Bigger means harder to place later. */
function stuckness(rank) {
  return Math.abs(rank - ANCHOR_RANK);
}

/**
 * How many of the bot's own cards follow this card outward, uninterrupted.
 * Playing a card whose continuation is in hand keeps the initiative: the next
 * turn the bot can immediately dump the follow up.
 */
function ownRunDepth(hand, suit, fromRank, step) {
  const held = new Set(hand);
  let depth = 0;
  let rank = fromRank + step;
  while (rank >= MIN_RANK && rank <= MAX_RANK && held.has(`${suit}${rank}`)) {
    depth += 1;
    rank += step;
  }
  return depth;
}

/**
 * Direction a legal card extends, plus the rank slot it opens next.
 * For a 7 the play opens both directions at once.
 */
function moveShape(table, card) {
  const { suit, rank } = parseCard(card);
  if (!rules.isSuitOpen(table, suit)) {
    return {
      suit,
      rank,
      anchor: true,
      openedRanks: [ANCHOR_RANK - 1, ANCHOR_RANK + 1].filter((r) => r >= MIN_RANK && r <= MAX_RANK),
    };
  }
  const step = rank < table[suit].low ? -1 : 1;
  const opened = rank + step;
  return {
    suit,
    rank,
    anchor: false,
    step,
    openedRanks: opened >= MIN_RANK && opened <= MAX_RANK ? [opened] : [],
  };
}

/**
 * How many of the bot's own cards sit further out in this direction, whether or
 * not they are consecutive. Those cards are stranded until this direction is
 * built all the way to them, so advancing it is progress even when the very
 * next rank is not in hand.
 */
function ownBeyond(hand, suit, fromRank, step) {
  let count = 0;
  for (const code of hand) {
    const parsed = parseCard(code);
    if (parsed.suit !== suit) continue;
    if (step > 0 ? parsed.rank > fromRank : parsed.rank < fromRank) count += 1;
  }
  return count;
}

function chainValue(hand, table, card) {
  const shape = moveShape(table, card);
  if (shape.anchor) {
    return (
      ownRunDepth(hand, shape.suit, ANCHOR_RANK, -1) + ownRunDepth(hand, shape.suit, ANCHOR_RANK, 1)
    );
  }
  return ownRunDepth(hand, shape.suit, shape.rank, shape.step);
}

/** Cards already on the table, derived from the pile bounds. */
function tableCards(table) {
  const out = [];
  for (const suit of SUITS) {
    if (!rules.isSuitOpen(table, suit)) continue;
    for (let rank = table[suit].low; rank <= table[suit].high; rank += 1) {
      out.push(`${suit}${rank}`);
    }
  }
  return out;
}

/** Easy: uniform choice over every legal move. */
function chooseEasy(ctx) {
  const options = rules.legalMoves(ctx.table, ctx.hand);
  if (options.length === 0) return null;
  return pickRandom(options, ctx.rng);
}

/**
 * Medium: empty the hand as fast as possible. Values keeping a run going, and
 * dumps cards that sit far from the anchor while it can, because those are the
 * ones that strand a hand at the end of a round.
 */
function chooseMedium(ctx) {
  const options = rules.legalMoves(ctx.table, ctx.hand);
  if (options.length === 0) return null;
  if (options.length === 1) return options[0];

  let best = null;
  let bestScore = -Infinity;
  for (const card of options) {
    const { rank } = parseCard(card);
    const chain = chainValue(ctx.hand, ctx.table, card);
    let score = chain * 12 + stuckness(rank) * 3;
    // Opening a suit is worth extra when the bot holds cards next to the anchor.
    if (!rules.isSuitOpen(ctx.table, parseCard(card).suit)) score += 4 + chain * 4;
    score += (ctx.rng ? ctx.rng() : Math.random()) * 0.5; // stable tie break
    if (score > bestScore) {
      bestScore = score;
      best = card;
    }
  }
  return best;
}

/**
 * Hard: everything medium does, plus card counting.
 *
 * Because the whole 52 card deck is dealt out, any card that is neither on the
 * table nor in this bot's hand is provably in an opponent hand. So the slot a
 * move opens is either useful to the bot itself or a direct gift to somebody
 * else. Hard play weighs that gift against the tempo gained, and weighs it more
 * heavily when an opponent is close to running out of cards.
 */
function chooseHard(ctx) {
  const options = rules.legalMoves(ctx.table, ctx.hand);
  if (options.length === 0) return null;
  if (options.length === 1) return options[0];

  const held = new Set(ctx.hand);
  const onTable = new Set(tableCards(ctx.table));
  const counts = Array.isArray(ctx.handCounts) ? ctx.handCounts : [];
  const opponentCounts = counts.filter((_, seat) => seat !== ctx.mySeat);
  const closestOpponent = opponentCounts.length ? Math.min(...opponentCounts) : 99;
  // Somebody about to win makes every gift much more expensive.
  const threat = closestOpponent <= 2 ? 3 : closestOpponent <= 4 ? 1.8 : 1;

  let best = null;
  let bestScore = -Infinity;
  for (const card of options) {
    const { suit, rank } = parseCard(card);
    const shape = moveShape(ctx.table, card);
    const chain = chainValue(ctx.hand, ctx.table, card);

    let score = chain * 14 + stuckness(rank) * 4;

    // Cards stranded further out in this direction only come free if the
    // direction keeps growing, so advancing towards them is real progress.
    if (shape.anchor) {
      score += (ownBeyond(ctx.hand, suit, ANCHOR_RANK, -1) + ownBeyond(ctx.hand, suit, ANCHOR_RANK, 1)) * 7;
      // A suit nobody has opened is where dead weight accumulates: open it.
      score += 5 + chain * 5;
    } else {
      score += ownBeyond(ctx.hand, suit, rank, shape.step) * 7;
    }

    for (const openedRank of shape.openedRanks) {
      const openedCard = `${suit}${openedRank}`;
      if (held.has(openedCard)) {
        score += 10; // opens a slot only this bot can fill
      } else if (!onTable.has(openedCard)) {
        score -= 9 * threat; // provably hands an opponent a playable card
      }
    }

    // Holding the single card that gates a whole direction is real leverage,
    // but only while the bot still has other work to do.
    if (!shape.anchor && chain === 0 && ctx.hand.length > 3) {
      score -= 4;
    }

    score += (ctx.rng ? ctx.rng() : Math.random()) * 0.5;
    if (score > bestScore) {
      bestScore = score;
      best = card;
    }
  }
  return best;
}

const STRATEGIES = {
  easy: chooseEasy,
  medium: chooseMedium,
  hard: chooseHard,
};

/**
 * ctx = { table, hand, handCounts, mySeat, rng }
 * Returns a legal card code, or null when the seat must pass.
 */
function chooseMove(difficulty, ctx) {
  const strategy = STRATEGIES[difficulty] || STRATEGIES.medium;
  const choice = strategy(ctx);
  if (choice === null) return null;
  // Belt and braces: never hand back something the rules would reject.
  if (!rules.isLegalMove(ctx.table, choice)) {
    const options = rules.legalMoves(ctx.table, ctx.hand);
    return options.length ? options[0] : null;
  }
  return choice;
}

module.exports = {
  DIFFICULTIES,
  chooseMove,
  chooseEasy,
  chooseMedium,
  chooseHard,
  stuckness,
  ownRunDepth,
  chainValue,
  tableCards,
};
