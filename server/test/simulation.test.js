'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { playRound, runBatch } = require('../src/game/simulate');
const bots = require('../src/game/bots');
const rules = require('../src/game/rules');
const cards = require('../src/game/cards');

test('every seat count from 2 to 8 plays a clean full round', () => {
  for (let seatCount = 2; seatCount <= 8; seatCount += 1) {
    for (let i = 0; i < 25; i += 1) {
      const result = playRound({ seatCount, seed: seatCount * 1000 + i });
      assert.equal(result.cardsRemaining[result.winnerSeat], 0);
      assert.equal(result.ranks[result.winnerSeat], 1);
      assert.equal(
        result.tableCards + result.cardsRemaining.reduce((a, b) => a + b, 0),
        52,
        'cards are conserved',
      );
    }
  }
});

test('mixed difficulty tables finish and pass counts stay sane', () => {
  const mixes = [
    ['easy', 'easy'],
    ['easy', 'medium', 'hard'],
    ['hard', 'hard', 'hard', 'hard'],
    ['medium', 'easy', 'hard', 'medium', 'easy'],
    ['hard', 'medium', 'easy', 'hard', 'medium', 'easy', 'hard', 'medium'],
  ];
  for (const difficulties of mixes) {
    const batch = runBatch({
      rounds: 40,
      seatCount: difficulties.length,
      difficulties,
      startSeed: 500 + difficulties.length,
    });
    assert.equal(batch.results.length, 40);
    assert.equal(batch.wins.reduce((a, b) => a + b, 0), 40);
    for (const result of batch.results) {
      assert.ok(result.plays >= 4, 'at least the four sevens get played');
      assert.ok(result.plays <= 52);
    }
  }
});

test('timer driven auto play resolves whole rounds on its own', () => {
  // Every seat is resolved by the server timer, never by a bot decision. This
  // is the disconnected table case: it must still reach a winner.
  for (let i = 0; i < 40; i += 1) {
    const result = playRound({ seatCount: 4, seed: 9000 + i, timeoutRatio: 1 });
    assert.equal(result.autoResolved, result.steps);
    assert.equal(result.cardsRemaining[result.winnerSeat], 0);
  }
});

test('a table with some seats timing out still completes', () => {
  for (let i = 0; i < 40; i += 1) {
    const result = playRound({
      seatCount: 5,
      difficulties: ['hard', 'medium', 'easy', 'medium', 'hard'],
      seed: 7000 + i,
      timeoutRatio: 0.35,
    });
    assert.ok(result.autoResolved > 0);
    assert.equal(result.cardsRemaining[result.winnerSeat], 0);
  }
});

test('bots only ever return a legal card or a genuine pass', () => {
  const rng = cards.createRng(4242);
  for (const difficulty of bots.DIFFICULTIES) {
    for (let i = 0; i < 400; i += 1) {
      // Build a random reachable table by playing random legal cards.
      let table = rules.createTable();
      const deck = cards.shuffle(cards.buildDeck(), rng);
      const steps = Math.floor(rng() * 30);
      for (let s = 0; s < steps; s += 1) {
        const options = deck.filter((c) => rules.isLegalMove(table, c));
        if (!options.length) break;
        table = rules.applyMove(table, options[Math.floor(rng() * options.length)]);
      }
      const hand = cards.shuffle(deck, rng).slice(0, 1 + Math.floor(rng() * 12));
      const choice = bots.chooseMove(difficulty, {
        table,
        hand,
        handCounts: [hand.length, 5, 5],
        mySeat: 0,
        rng,
      });
      if (choice === null) {
        assert.equal(rules.hasLegalMove(table, hand), false, `${difficulty} passed with a move available`);
      } else {
        assert.ok(hand.includes(choice), `${difficulty} played a card it does not hold`);
        assert.ok(rules.isLegalMove(table, choice), `${difficulty} played an illegal card`);
      }
    }
  }
});

test('harder bots win more often than easy bots head to head', () => {
  // Seat order alternates so seating advantage cannot explain the result.
  const hardVsEasy = runBatch({ rounds: 150, seatCount: 2, difficulties: ['hard', 'easy'], startSeed: 11 });
  const easyVsHard = runBatch({ rounds: 150, seatCount: 2, difficulties: ['easy', 'hard'], startSeed: 11 });
  const hardWins = hardVsEasy.wins[0] + easyVsHard.wins[1];
  const easyWins = hardVsEasy.wins[1] + easyVsHard.wins[0];
  assert.equal(hardWins + easyWins, 300);
  assert.ok(hardWins > easyWins, `hard ${hardWins} should beat easy ${easyWins}`);

  const mediumVsEasy = runBatch({ rounds: 150, seatCount: 2, difficulties: ['medium', 'easy'], startSeed: 23 });
  const easyVsMedium = runBatch({ rounds: 150, seatCount: 2, difficulties: ['easy', 'medium'], startSeed: 23 });
  const mediumWins = mediumVsEasy.wins[0] + easyVsMedium.wins[1];
  const easyWins2 = mediumVsEasy.wins[1] + easyVsMedium.wins[0];
  assert.ok(mediumWins > easyWins2, `medium ${mediumWins} should beat easy ${easyWins2}`);
});

test('a long stress run of mixed tables never trips an invariant', () => {
  let played = 0;
  for (let seatCount = 2; seatCount <= 8; seatCount += 1) {
    const difficulties = [];
    for (let seat = 0; seat < seatCount; seat += 1) {
      difficulties.push(bots.DIFFICULTIES[seat % 3]);
    }
    const batch = runBatch({
      rounds: 120,
      seatCount,
      difficulties,
      startSeed: 314159 + seatCount,
      timeoutRatio: seatCount % 2 === 0 ? 0.15 : 0,
    });
    played += batch.rounds;
  }
  assert.equal(played, 840);
});
