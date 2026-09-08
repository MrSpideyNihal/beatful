'use strict';

/**
 * Beatful rules engine.
 *
 * Pure functions only. Every decision about legality, table growth, pass
 * eligibility and ranking lives here so that the server validator, the timeout
 * auto player and every bot tier share one implementation.
 *
 * Table shape (JSON safe, stored directly in mongo):
 *   {
 *     H: { low: null, high: null },   // suit not opened yet, the 7 is missing
 *     D: { low: 5, high: 9 },         // 5,6,7,8,9 of diamonds are down
 *     ...
 *   }
 *
 * Invariants enforced by this module:
 *   - low and high are either both null or both set.
 *   - when set, low <= 7 <= high.
 *   - a suit opens only by playing its 7.
 *   - the only playable cards in an open suit are low-1 and high+1.
 */

const {
  SUITS,
  MIN_RANK,
  MAX_RANK,
  ANCHOR_RANK,
  isCard,
  parseCard,
} = require('./cards');

/** Empty table with all four suits closed. */
function createTable() {
  const table = {};
  for (const suit of SUITS) {
    table[suit] = { low: null, high: null };
  }
  return table;
}

/** Defensive deep copy so callers can never alias a stored table. */
function cloneTable(table) {
  const out = {};
  for (const suit of SUITS) {
    const pile = table && table[suit] ? table[suit] : { low: null, high: null };
    out[suit] = {
      low: pile.low === null || pile.low === undefined ? null : Number(pile.low),
      high: pile.high === null || pile.high === undefined ? null : Number(pile.high),
    };
  }
  return out;
}

/** True when the table object is structurally sound. Used to reject junk. */
function isValidTable(table) {
  if (!table || typeof table !== 'object') return false;
  for (const suit of SUITS) {
    const pile = table[suit];
    if (!pile || typeof pile !== 'object') return false;
    const { low, high } = pile;
    const lowClosed = low === null || low === undefined;
    const highClosed = high === null || high === undefined;
    if (lowClosed !== highClosed) return false;
    if (lowClosed) continue;
    if (!Number.isInteger(low) || !Number.isInteger(high)) return false;
    if (low < MIN_RANK || high > MAX_RANK) return false;
    if (low > ANCHOR_RANK || high < ANCHOR_RANK) return false;
  }
  return true;
}

function isSuitOpen(table, suit) {
  const pile = table[suit];
  return Boolean(pile) && pile.low !== null && pile.low !== undefined;
}

/** True when every rank of the suit is on the table. */
function isSuitComplete(table, suit) {
  return isSuitOpen(table, suit) && table[suit].low === MIN_RANK && table[suit].high === MAX_RANK;
}

/** How many cards of this suit are on the table. */
function suitCardCount(table, suit) {
  if (!isSuitOpen(table, suit)) return 0;
  return table[suit].high - table[suit].low + 1;
}

/** Total cards on the table across all suits. */
function tableCardCount(table) {
  let total = 0;
  for (const suit of SUITS) total += suitCardCount(table, suit);
  return total;
}

/**
 * The two ranks that could legally be played in this suit right now.
 * Returns { down, up } where each value is a rank or null when that direction
 * is exhausted. For a closed suit it returns { down: null, up: null } and the
 * only legal card is the 7, reported by needsAnchor.
 */
function nextNeeded(table, suit) {
  if (!isSuitOpen(table, suit)) return { down: null, up: null };
  const { low, high } = table[suit];
  return {
    down: low > MIN_RANK ? low - 1 : null,
    up: high < MAX_RANK ? high + 1 : null,
  };
}

function needsAnchor(table, suit) {
  return !isSuitOpen(table, suit);
}

/**
 * The single legality check. Every code path that plays a card goes through
 * this: the API route, the timeout auto player and all three bot tiers.
 */
function isLegalMove(table, card) {
  if (!isCard(card)) return false;
  // Satte Pe Satta rule: game can only start by 7 of Hearts (H7).
  // Until 7 of Hearts is played, no other card is legal.
  if (!isSuitOpen(table, 'H')) {
    return card === 'H7';
  }
  const { suit, rank } = parseCard(card);
  const pile = table[suit];
  if (!pile) return false;
  if (pile.low === null || pile.low === undefined) {
    // Suit is closed. Only the 7 opens it.
    return rank === ANCHOR_RANK;
  }
  if (rank >= pile.low && rank <= pile.high) return false; // already on the table
  return rank === pile.low - 1 || rank === pile.high + 1;
}

/** Every card in the hand that can be played right now, in hand order. */
function legalMoves(table, hand) {
  if (!Array.isArray(hand)) return [];
  const seen = new Set();
  const out = [];
  for (const card of hand) {
    if (seen.has(card)) continue;
    seen.add(card);
    if (isLegalMove(table, card)) out.push(card);
  }
  return out;
}

function hasLegalMove(table, hand) {
  if (!Array.isArray(hand)) return false;
  for (const card of hand) {
    if (isLegalMove(table, card)) return true;
  }
  return false;
}

/**
 * Returns a new table with the card added. Throws when the move is illegal, so
 * callers must check isLegalMove first. Never mutates the input table.
 */
function applyMove(table, card) {
  if (!isLegalMove(table, card)) {
    throw new Error(`illegal move: ${String(card)}`);
  }
  const { suit, rank } = parseCard(card);
  const next = cloneTable(table);
  const pile = next[suit];
  if (pile.low === null) {
    pile.low = ANCHOR_RANK;
    pile.high = ANCHOR_RANK;
  } else if (rank === pile.low - 1) {
    pile.low = rank;
  } else {
    pile.high = rank;
  }
  return next;
}

/** Which direction a card would extend. Used by the UI for the drop animation. */
function moveDirection(table, card) {
  if (!isLegalMove(table, card)) return null;
  const { suit, rank } = parseCard(card);
  if (!isSuitOpen(table, suit)) return 'anchor';
  return rank < table[suit].low ? 'down' : 'up';
}

/**
 * Deal sizes. floor(52 / n) each, then one extra card to the first 52 % n
 * seats in turn order. With 8 players that is 6 cards each plus 4 seats
 * getting a seventh.
 */
function dealCounts(playerCount) {
  if (!Number.isInteger(playerCount) || playerCount < 1) {
    throw new TypeError(`invalid player count: ${String(playerCount)}`);
  }
  const base = Math.floor(52 / playerCount);
  const remainder = 52 % playerCount;
  const counts = [];
  for (let seat = 0; seat < playerCount; seat += 1) {
    counts.push(base + (seat < remainder ? 1 : 0));
  }
  return counts;
}

/**
 * Split a shuffled deck into hands using dealCounts. The deck must be exactly
 * 52 cards. Every card is dealt, nothing is left in a stock pile.
 */
function dealHands(deck, playerCount) {
  if (!Array.isArray(deck) || deck.length !== 52) {
    throw new TypeError('deal requires a 52 card deck');
  }
  const counts = dealCounts(playerCount);
  const hands = [];
  let cursor = 0;
  for (const count of counts) {
    hands.push(deck.slice(cursor, cursor + count));
    cursor += count;
  }
  return hands;
}

/**
 * Total pip value of cards in a hand. Ace=1, 2-10=value, Jack=11, Queen=12, King=13.
 * Empty hand (round winner) scores 0 penalty points.
 */
function handPipScore(hand) {
  if (!Array.isArray(hand) || hand.length === 0) return 0;
  return hand.reduce((sum, card) => sum + parseCard(card).rank, 0);
}

/**
 * Ranking at round end. Fewer penalty points (card pip value sum) is a better
 * rank. Seats with the same score share a rank, and the next distinct score skips
 * ahead (standard competition ranking: 1, 2, 2, 4).
 */
function rankSeats(scores) {
  const entries = scores.map((score, seatIndex) => ({ seatIndex, score }));
  const sorted = entries.slice().sort((a, b) => {
    if (a.score !== b.score) return a.score - b.score;
    return a.seatIndex - b.seatIndex;
  });
  const ranks = new Array(scores.length).fill(0);
  let currentRank = 0;
  let previousScore = null;
  sorted.forEach((entry, index) => {
    if (previousScore === null || entry.score !== previousScore) {
      currentRank = index + 1;
      previousScore = entry.score;
    }
    ranks[entry.seatIndex] = currentRank;
  });
  return ranks;
}

/**
 * A round is over as soon as any seat is empty. The deck is fully dealt and
 * every card is playable in principle, so a full board deadlock cannot happen:
 * the only terminal condition is an empty hand.
 */
function findWinnerSeat(hands) {
  for (let seat = 0; seat < hands.length; seat += 1) {
    if (hands[seat].length === 0) return seat;
  }
  return -1;
}

/**
 * Safety net for the turn loop. True when nobody on the table can move, which
 * with a fully dealt 52 card deck means every remaining card is unreachable.
 * This should be unreachable in a real game and is asserted in tests, but the
 * turn advance guards against it rather than spinning forever.
 */
function isDeadlocked(table, hands) {
  for (const hand of hands) {
    if (hand.length > 0 && hasLegalMove(table, hand)) return false;
  }
  return true;
}

module.exports = {
  createTable,
  cloneTable,
  isValidTable,
  isSuitOpen,
  isSuitComplete,
  suitCardCount,
  tableCardCount,
  nextNeeded,
  needsAnchor,
  isLegalMove,
  legalMoves,
  hasLegalMove,
  applyMove,
  moveDirection,
  dealCounts,
  dealHands,
  handPipScore,
  rankSeats,
  findWinnerSeat,
  isDeadlocked,
};
