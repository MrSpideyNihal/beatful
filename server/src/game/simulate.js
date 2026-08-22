'use strict';

/**
 * Headless bot versus bot driver.
 *
 * Used by the test suite and by scripts/simulate.js. Every step is checked
 * against the rules module, so a rules bug shows up here long before any UI
 * exists. The driver also verifies the invariants that must hold for the whole
 * game: cards are conserved, no seat ever moves out of turn, and the table only
 * ever grows by legal moves.
 */

const cards = require('./cards');
const rules = require('./rules');
const engine = require('./engine');
const bots = require('./bots');

class SimulationError extends Error {}

function countTableCards(table) {
  return rules.tableCardCount(table);
}

/**
 * Play one full round to completion with bots in every seat.
 *
 * options:
 *   seatCount     2..8
 *   difficulties  array of 'easy' | 'medium' | 'hard', one per seat
 *   seed          number, makes the whole game reproducible
 *   timeoutRatio  0..1 chance a seat is resolved by the turn timer instead of
 *                 by its own choice, to exercise the auto play path
 */
function playRound(options) {
  const {
    seatCount = 4,
    difficulties = [],
    seed = cards.randomSeed(),
    timeoutRatio = 0,
  } = options || {};

  const rng = cards.createRng(seed);
  const state = engine.startRound({ seatCount, timerSeconds: 15, seed, now: 0 });
  const seatDifficulty = [];
  for (let seat = 0; seat < seatCount; seat += 1) {
    seatDifficulty.push(difficulties[seat] || 'medium');
  }

  const totalDealt = state.hands.reduce((sum, hand) => sum + hand.length, 0);
  if (totalDealt !== 52) {
    throw new SimulationError(`deal lost cards: ${totalDealt}`);
  }

  let plays = 0;
  let passes = 0;
  let autoResolved = 0;
  let now = 0;
  const maxSteps = 52 + seatCount * 60;

  for (let step = 0; step < maxSteps; step += 1) {
    if (state.status !== engine.STATUS.IN_PROGRESS) {
      return summarise(state, { plays, passes, autoResolved, seed, seatDifficulty, steps: step });
    }

    const seat = state.currentTurnSeat;
    if (state.hands[seat].length === 0) {
      throw new SimulationError('an empty seat was given the turn');
    }

    // Somebody must always be able to move while cards remain: every unopened
    // suit has its seven in a hand, and every open suit needs a rank that is in
    // a hand. If this trips, the rules module has a hole in it.
    if (rules.isDeadlocked(state.table, state.hands)) {
      throw new SimulationError('deadlock: no seat can move but cards remain');
    }
    if (state.passStreak >= seatCount) {
      throw new SimulationError('every seat passed in a row, which is impossible');
    }

    now += 1000;
    const before = countTableCards(state.table);
    const handBefore = state.hands[seat].length;
    const useTimeout = timeoutRatio > 0 && rng() < timeoutRatio;

    if (useTimeout) {
      const forced = engine.resolveTimeout(state, state.turnStartedAt + state.timerSeconds * 1000, rng);
      if (!forced) throw new SimulationError('timeout resolution did nothing');
      autoResolved += 1;
      if (forced.type === 'play') plays += 1;
      else passes += 1;
      assertStep(state, seat, forced, before, handBefore);
      continue;
    }

    const choice = bots.chooseMove(seatDifficulty[seat], {
      table: state.table,
      hand: state.hands[seat].slice(),
      handCounts: engine.handSizes(state),
      mySeat: seat,
      rng,
    });

    if (choice === null) {
      if (rules.hasLegalMove(state.table, state.hands[seat])) {
        throw new SimulationError(`bot passed with a legal move available (seat ${seat})`);
      }
      const entry = engine.pass(state, seat, now);
      passes += 1;
      assertStep(state, seat, entry, before, handBefore);
      continue;
    }

    if (!rules.isLegalMove(state.table, choice)) {
      throw new SimulationError(`bot chose an illegal card ${choice}`);
    }
    const entry = engine.playCard(state, seat, choice, now);
    plays += 1;
    assertStep(state, seat, entry, before, handBefore);
  }

  throw new SimulationError('round did not finish within the step budget');
}

function assertStep(state, seat, entry, tableBefore, handBefore) {
  const tableAfter = countTableCards(state.table);
  const inHands = state.hands.reduce((sum, hand) => sum + hand.length, 0);
  if (tableAfter + inHands !== 52) {
    throw new SimulationError(`card count drifted: table ${tableAfter} hands ${inHands}`);
  }
  if (entry.type === 'play') {
    if (tableAfter !== tableBefore + 1) throw new SimulationError('a play did not add exactly one card');
    if (state.hands[seat].length !== handBefore - 1) throw new SimulationError('a play did not remove one card');
  } else {
    if (tableAfter !== tableBefore) throw new SimulationError('a pass changed the table');
    if (state.hands[seat].length !== handBefore) throw new SimulationError('a pass changed a hand');
  }
  if (!rules.isValidTable(state.table)) {
    throw new SimulationError('table left a valid state');
  }
}

function summarise(state, meta) {
  const sizes = engine.handSizes(state);
  if (sizes[state.winnerSeat] !== 0) {
    throw new SimulationError('the winner still holds cards');
  }
  return {
    winnerSeat: state.winnerSeat,
    ranks: state.ranks,
    cardsRemaining: sizes,
    tableCards: countTableCards(state.table),
    ...meta,
  };
}

/** Run many rounds and aggregate wins per seat. */
function runBatch(options) {
  const { rounds = 100, seatCount = 4, difficulties = [], startSeed = 1, timeoutRatio = 0 } = options || {};
  const wins = new Array(seatCount).fill(0);
  const results = [];
  for (let i = 0; i < rounds; i += 1) {
    const result = playRound({ seatCount, difficulties, seed: startSeed + i * 7919, timeoutRatio });
    wins[result.winnerSeat] += 1;
    results.push(result);
  }
  return { wins, results, rounds };
}

module.exports = { playRound, runBatch, SimulationError };
