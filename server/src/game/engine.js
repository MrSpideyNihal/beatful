'use strict';

/**
 * Round and turn machinery built on top of the pure rules module.
 *
 * The game state object below is JSON safe and is stored verbatim inside the
 * room document. It holds every hand, so it must never be sent to a client as
 * is: use publicView(state, seatIndex) for that.
 */

const cards = require('./cards');
const rules = require('./rules');

const LOG_LIMIT = 24;

class GameError extends Error {
  constructor(code, message, details) {
    super(message || code);
    this.name = 'GameError';
    this.code = code;
    if (details) this.details = details;
  }
}

const STATUS = {
  IN_PROGRESS: 'in_progress',
  ROUND_OVER: 'round_over',
  FINISHED: 'finished',
};

/**
 * Traditional Sevens opener: whoever holds the seven of diamonds moves first.
 * Deterministic, easy to explain in the rules screen, and it guarantees the
 * first seat to act always has at least one legal move.
 */
function findStartingSeat(hands) {
  const opener = cards.makeCard('D', cards.ANCHOR_RANK);
  for (let seat = 0; seat < hands.length; seat += 1) {
    if (hands[seat].includes(opener)) return seat;
  }
  return 0;
}

/**
 * Deal a fresh round. Carries cumulative scores across rounds of the same
 * match. Returns a brand new state object.
 */
function startRound(options) {
  const {
    seatCount,
    timerSeconds,
    rounds = 1,
    round = 1,
    scores = null,
    seed = cards.randomSeed(),
    now = Date.now(),
    shuffled = true,
  } = options || {};

  if (!Number.isInteger(seatCount) || seatCount < 2 || seatCount > 8) {
    throw new GameError('BAD_SEAT_COUNT', 'seat count must be between 2 and 8');
  }
  if (!Number.isInteger(timerSeconds) || timerSeconds < 5 || timerSeconds > 120) {
    throw new GameError('BAD_TIMER', 'turn timer must be between 5 and 120 seconds');
  }

  let currentSeed = seed;
  let hands;
  const MAX_REDEAL = 10;
  for (let attempt = 0; attempt < MAX_REDEAL; attempt += 1) {
    const rng = cards.createRng(currentSeed);
    const deck = shuffled ? cards.shuffle(cards.buildDeck(), rng) : cards.buildDeck();
    hands = rules.dealHands(deck, seatCount).map((hand) => cards.sortHand(hand));

    // Three-kings reshuffle: if any single player holds 3+ kings and there are
    // more than 2 seats, redeal with a fresh seed derived from the current RNG.
    // Skipped for 2-player games where concentrated kings are more expected.
    if (seatCount > 2) {
      const tooManyKings = hands.some(
        (hand) => hand.filter((c) => cards.rankOf(c) === 13).length >= 3,
      );
      if (tooManyKings) {
        currentSeed = Math.floor(rng() * 0xFFFFFFFF) >>> 0;
        continue;
      }
    }
    break;
  }

  const state = {
    seatCount,
    round,
    rounds,
    seed,
    timerSeconds,
    status: STATUS.IN_PROGRESS,
    table: rules.createTable(),
    hands,
    currentTurnSeat: findStartingSeat(hands),
    turnStartedAt: now,
    scores: Array.isArray(scores) && scores.length === seatCount ? scores.slice() : new Array(seatCount).fill(0),
    roundResults: [],
    lastAction: { type: 'deal', at: now, round },
    log: [{ type: 'deal', at: now, round }],
    winnerSeat: null,
    ranks: null,
    passStreak: 0,
  };

  // Degenerate deal guard: with more seats than cards a seat can start empty
  // and therefore has already won. Player counts are capped at 8 so this is
  // unreachable in production, but the engine still resolves it cleanly.
  const emptySeat = rules.findWinnerSeat(hands);
  if (emptySeat >= 0) {
    finishRound(state, emptySeat, now);
  }
  return state;
}

function handSizes(state) {
  return state.hands.map((hand) => hand.length);
}

function seatInBounds(state, seatIndex) {
  return Number.isInteger(seatIndex) && seatIndex >= 0 && seatIndex < state.seatCount;
}

function pushLog(state, entry) {
  state.log.push(entry);
  if (state.log.length > LOG_LIMIT) {
    state.log = state.log.slice(state.log.length - LOG_LIMIT);
  }
  state.lastAction = entry;
}

/** Milliseconds left on the current turn. Never negative. */
function turnMillisLeft(state, now = Date.now()) {
  if (state.status !== STATUS.IN_PROGRESS) return 0;
  const deadline = state.turnStartedAt + state.timerSeconds * 1000;
  return Math.max(0, deadline - now);
}

function isTurnExpired(state, now = Date.now()) {
  return state.status === STATUS.IN_PROGRESS && turnMillisLeft(state, now) === 0;
}

function advanceTurn(state, now) {
  let seat = state.currentTurnSeat;
  for (let step = 1; step <= state.seatCount; step += 1) {
    const candidate = (state.currentTurnSeat + step) % state.seatCount;
    if (state.hands[candidate].length > 0) {
      seat = candidate;
      break;
    }
  }
  state.currentTurnSeat = seat;
  state.turnStartedAt = now;
}

function finishRound(state, winnerSeat, now) {
  const sizes = handSizes(state);
  const ranks = rules.rankSeats(sizes);
  state.winnerSeat = winnerSeat;
  state.ranks = ranks;
  state.roundResults.push({
    round: state.round,
    winnerSeat,
    ranks,
    cardsRemaining: sizes,
  });
  for (let seat = 0; seat < state.seatCount; seat += 1) {
    // Lower total is better. A win adds 1, last place adds seatCount.
    state.scores[seat] += ranks[seat];
  }
  state.status = state.round >= state.rounds ? STATUS.FINISHED : STATUS.ROUND_OVER;
  pushLog(state, { type: 'round_over', at: now, round: state.round, winnerSeat, ranks });
}

/**
 * Play one card for a seat. Throws GameError with a stable code on any rule
 * violation so the route layer can map it straight to a client error string.
 */
function playCard(state, seatIndex, card, now = Date.now()) {
  if (state.status !== STATUS.IN_PROGRESS) {
    throw new GameError('ROUND_NOT_ACTIVE', 'the round is not accepting moves');
  }
  if (!seatInBounds(state, seatIndex)) {
    throw new GameError('BAD_SEAT', 'unknown seat');
  }
  if (state.currentTurnSeat !== seatIndex) {
    throw new GameError('NOT_YOUR_TURN', 'it is not your turn');
  }
  if (!cards.isCard(card)) {
    throw new GameError('BAD_CARD', 'that is not a card');
  }
  const hand = state.hands[seatIndex];
  const handIndex = hand.indexOf(card);
  if (handIndex < 0) {
    throw new GameError('CARD_NOT_IN_HAND', 'you do not hold that card');
  }
  if (!rules.isLegalMove(state.table, card)) {
    throw new GameError('ILLEGAL_MOVE', 'that card cannot be played yet');
  }

  const direction = rules.moveDirection(state.table, card);
  state.table = rules.applyMove(state.table, card);
  hand.splice(handIndex, 1);
  state.passStreak = 0;
  const entry = {
    type: 'play',
    at: now,
    seatIndex,
    card,
    direction,
    auto: false,
  };

  if (hand.length === 0) {
    pushLog(state, entry);
    finishRound(state, seatIndex, now);
    return entry;
  }

  pushLog(state, entry);
  advanceTurn(state, now);
  return entry;
}

/**
 * Pass. House rule: passing is only allowed with zero legal moves. This is
 * enforced here, so a client cannot pass away a playable card by mistake or on
 * purpose. The client shows a nudge instead of sending the request.
 */
function pass(state, seatIndex, now = Date.now()) {
  if (state.status !== STATUS.IN_PROGRESS) {
    throw new GameError('ROUND_NOT_ACTIVE', 'the round is not accepting moves');
  }
  if (!seatInBounds(state, seatIndex)) {
    throw new GameError('BAD_SEAT', 'unknown seat');
  }
  if (state.currentTurnSeat !== seatIndex) {
    throw new GameError('NOT_YOUR_TURN', 'it is not your turn');
  }
  if (rules.hasLegalMove(state.table, state.hands[seatIndex])) {
    throw new GameError('MUST_PLAY', 'you still have a card you can play');
  }
  state.passStreak += 1;
  const entry = { type: 'pass', at: now, seatIndex, auto: false };
  pushLog(state, entry);
  advanceTurn(state, now);
  return entry;
}

/**
 * Timer expiry resolution. This is the only place a turn can be resolved
 * without a client request, and it is always driven by the server clock.
 */
function resolveTimeout(state, now = Date.now(), rng = Math.random) {
  if (state.status !== STATUS.IN_PROGRESS) return null;
  if (!isTurnExpired(state, now)) return null;

  const seatIndex = state.currentTurnSeat;
  const hand = state.hands[seatIndex];
  const options = rules.legalMoves(state.table, hand);

  if (options.length === 0) {
    state.passStreak += 1;
    const entry = { type: 'pass', at: now, seatIndex, auto: true };
    pushLog(state, entry);
    advanceTurn(state, now);
    return entry;
  }

  const pick = options[Math.floor(rng() * options.length) % options.length];
  const direction = rules.moveDirection(state.table, pick);
  state.table = rules.applyMove(state.table, pick);
  hand.splice(hand.indexOf(pick), 1);
  state.passStreak = 0;
  const entry = { type: 'play', at: now, seatIndex, card: pick, direction, auto: true };

  if (hand.length === 0) {
    pushLog(state, entry);
    finishRound(state, seatIndex, now);
    return entry;
  }
  pushLog(state, entry);
  advanceTurn(state, now);
  return entry;
}

/** Begin the next round of a multi round match. */
function nextRound(state, now = Date.now(), seed = cards.randomSeed()) {
  if (state.status !== STATUS.ROUND_OVER) {
    throw new GameError('ROUND_NOT_OVER', 'the current round is still running');
  }
  return startRound({
    seatCount: state.seatCount,
    timerSeconds: state.timerSeconds,
    rounds: state.rounds,
    round: state.round + 1,
    scores: state.scores,
    seed,
    now,
  });
}

/** Final standings across all rounds. Lower total score is better. */
function matchStandings(state) {
  const totals = state.scores.map((score, seatIndex) => ({ seatIndex, score }));
  const sorted = totals.slice().sort((a, b) => {
    if (a.score !== b.score) return a.score - b.score;
    return a.seatIndex - b.seatIndex;
  });
  const out = new Array(state.seatCount);
  let rank = 0;
  let previous = null;
  sorted.forEach((entry, index) => {
    if (previous === null || entry.score !== previous) {
      rank = index + 1;
      previous = entry.score;
    }
    out[entry.seatIndex] = { seatIndex: entry.seatIndex, score: entry.score, rank };
  });
  return out;
}

/**
 * Everything a single seat is allowed to see. Other hands are reduced to card
 * counts. Legal moves are computed here so the client never needs the rules to
 * render highlights, and cannot be tricked into thinking an illegal card is
 * playable.
 */
function publicView(state, seatIndex, now = Date.now()) {
  const mySeat = seatInBounds(state, seatIndex) ? seatIndex : null;
  const hand = mySeat === null ? [] : state.hands[mySeat].slice();
  const legal = mySeat === null ? [] : rules.legalMoves(state.table, hand);
  return {
    round: state.round,
    rounds: state.rounds,
    status: state.status,
    seatCount: state.seatCount,
    table: rules.cloneTable(state.table),
    handCounts: handSizes(state),
    currentTurnSeat: state.currentTurnSeat,
    turnStartedAt: state.turnStartedAt,
    timerSeconds: state.timerSeconds,
    millisLeft: turnMillisLeft(state, now),
    yourSeat: mySeat,
    yourHand: hand,
    yourLegalMoves: legal,
    canPass:
      state.status === STATUS.IN_PROGRESS &&
      mySeat !== null &&
      state.currentTurnSeat === mySeat &&
      legal.length === 0,
    lastAction: state.lastAction || null,
    log: state.log.slice(-8),
    scores: state.scores.slice(),
    // Copied, not referenced. A view is a snapshot of one moment, so dealing the
    // next round must not reach back into a response already handed out.
    roundResults: state.roundResults.map((entry) => ({
      ...entry,
      ranks: entry.ranks.slice(),
      cardsRemaining: entry.cardsRemaining.slice(),
    })),
    winnerSeat: state.winnerSeat,
    ranks: state.ranks ? state.ranks.slice() : null,
    standings: state.status === STATUS.FINISHED ? matchStandings(state) : null,
  };
}

module.exports = {
  GameError,
  STATUS,
  LOG_LIMIT,
  startRound,
  nextRound,
  playCard,
  pass,
  resolveTimeout,
  advanceTurn,
  turnMillisLeft,
  isTurnExpired,
  handSizes,
  publicView,
  matchStandings,
  findStartingSeat,
};
