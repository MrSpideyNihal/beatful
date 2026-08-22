'use strict';

/**
 * Card primitives for Beatful.
 *
 * A card is stored as a compact string code: suit letter + rank number.
 *   "H1"  = ace of hearts
 *   "S7"  = seven of spades
 *   "D13" = king of diamonds
 *
 * Rank numbers are 1..13 where 1 = ace, 11 = jack, 12 = queen, 13 = king.
 * There is no wrap around: ace is strictly the low end, king the high end.
 *
 * This module is pure. It has no dependency on express, mongodb or any
 * transport so that it can be unit tested and reused by the bots and by the
 * server side validator without drift.
 */

const SUITS = ['H', 'D', 'C', 'S'];
const SUIT_NAMES = { H: 'hearts', D: 'diamonds', C: 'clubs', S: 'spades' };
const SUIT_SYMBOLS = { H: '♥', D: '♦', C: '♣', S: '♠' };

const MIN_RANK = 1;
const MAX_RANK = 13;
const ANCHOR_RANK = 7;
const DECK_SIZE = 52;

const RANK_LABELS = {
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

/** Build the card code for a suit and rank. Throws on bad input. */
function makeCard(suit, rank) {
  if (!SUITS.includes(suit)) {
    throw new TypeError(`invalid suit: ${String(suit)}`);
  }
  if (!Number.isInteger(rank) || rank < MIN_RANK || rank > MAX_RANK) {
    throw new TypeError(`invalid rank: ${String(rank)}`);
  }
  return `${suit}${rank}`;
}

/** True when the value is a syntactically valid card code. */
function isCard(code) {
  if (typeof code !== 'string' || code.length < 2 || code.length > 3) return false;
  if (!SUITS.includes(code[0])) return false;
  const rest = code.slice(1);
  if (!/^[0-9]{1,2}$/.test(rest)) return false;
  const rank = Number(rest);
  if (String(rank) !== rest) return false;
  return rank >= MIN_RANK && rank <= MAX_RANK;
}

/** Parse a card code into { suit, rank }. Throws on bad input. */
function parseCard(code) {
  if (!isCard(code)) {
    throw new TypeError(`invalid card code: ${String(code)}`);
  }
  return { suit: code[0], rank: Number(code.slice(1)) };
}

function suitOf(code) {
  return parseCard(code).suit;
}

function rankOf(code) {
  return parseCard(code).rank;
}

/** Human readable label such as "8 of hearts". Used for timeout notices. */
function cardLabel(code) {
  const { suit, rank } = parseCard(code);
  return `${RANK_LABELS[rank]}${SUIT_SYMBOLS[suit]}`;
}

/** Fresh ordered 52 card deck. No jokers. */
function buildDeck() {
  const deck = [];
  for (const suit of SUITS) {
    for (let rank = MIN_RANK; rank <= MAX_RANK; rank += 1) {
      deck.push(makeCard(suit, rank));
    }
  }
  return deck;
}

/**
 * Deterministic pseudo random generator (mulberry32). Seeded shuffles keep
 * tests reproducible and let a room record the exact seed it was dealt with.
 */
function createRng(seed) {
  let state = (Number.isFinite(seed) ? Math.floor(seed) : 0) >>> 0;
  if (state === 0) state = 0x9e3779b9;
  return function next() {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function randomSeed() {
  return Math.floor(Math.random() * 0xffffffff) >>> 0;
}

/** Fisher Yates shuffle. Returns a new array, never mutates the input. */
function shuffle(cards, rng) {
  const next = typeof rng === 'function' ? rng : Math.random;
  const out = cards.slice();
  for (let i = out.length - 1; i > 0; i -= 1) {
    const j = Math.floor(next() * (i + 1));
    const tmp = out[i];
    out[i] = out[j];
    out[j] = tmp;
  }
  return out;
}

/** Stable sort used for hand display: suit order then rank. */
function sortHand(cards) {
  return cards.slice().sort((a, b) => {
    const ca = parseCard(a);
    const cb = parseCard(b);
    if (ca.suit !== cb.suit) return SUITS.indexOf(ca.suit) - SUITS.indexOf(cb.suit);
    return ca.rank - cb.rank;
  });
}

module.exports = {
  SUITS,
  SUIT_NAMES,
  SUIT_SYMBOLS,
  RANK_LABELS,
  MIN_RANK,
  MAX_RANK,
  ANCHOR_RANK,
  DECK_SIZE,
  makeCard,
  isCard,
  parseCard,
  suitOf,
  rankOf,
  cardLabel,
  buildDeck,
  createRng,
  randomSeed,
  shuffle,
  sortHand,
};
