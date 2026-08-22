'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const cards = require('../src/game/cards');
const rules = require('../src/game/rules');
const engine = require('../src/game/engine');

function tableFrom(spec) {
  const table = rules.createTable();
  for (const [suit, bounds] of Object.entries(spec)) {
    table[suit] = { low: bounds[0], high: bounds[1] };
  }
  return table;
}

test('card codec round trips every card and rejects junk', () => {
  const deck = cards.buildDeck();
  assert.equal(deck.length, 52);
  assert.equal(new Set(deck).size, 52);
  for (const code of deck) {
    const { suit, rank } = cards.parseCard(code);
    assert.equal(cards.makeCard(suit, rank), code);
    assert.ok(cards.isCard(code));
  }
  for (const bad of ['', 'X7', 'H0', 'H14', 'H', 'H07', 'HH', '7H', 'H7 ', null, 12, {}]) {
    assert.equal(cards.isCard(bad), false, `should reject ${JSON.stringify(bad)}`);
  }
  assert.throws(() => cards.parseCard('H14'), TypeError);
  assert.throws(() => cards.makeCard('H', 0), TypeError);
});

test('an empty table only accepts sevens', () => {
  const table = rules.createTable();
  for (const code of cards.buildDeck()) {
    const { rank } = cards.parseCard(code);
    assert.equal(rules.isLegalMove(table, code), rank === 7, `${code} on empty table`);
  }
});

test('playing a seven opens both directions of that suit only', () => {
  let table = rules.createTable();
  table = rules.applyMove(table, 'H7');
  assert.deepEqual(table.H, { low: 7, high: 7 });
  assert.equal(rules.isLegalMove(table, 'H6'), true);
  assert.equal(rules.isLegalMove(table, 'H8'), true);
  // Other suits stay closed.
  assert.equal(rules.isLegalMove(table, 'S6'), false);
  assert.equal(rules.isLegalMove(table, 'S8'), false);
  assert.equal(rules.isLegalMove(table, 'S7'), true);
});

test('no skipping in either direction', () => {
  const table = tableFrom({ H: [6, 9] });
  assert.equal(rules.isLegalMove(table, 'H5'), true);
  assert.equal(rules.isLegalMove(table, 'H10'), true);
  for (const skip of ['H4', 'H3', 'H2', 'H1', 'H11', 'H12', 'H13']) {
    assert.equal(rules.isLegalMove(table, skip), false, `${skip} skips ahead`);
  }
});

test('cards already on the table are never legal again', () => {
  const table = tableFrom({ D: [4, 11] });
  for (let rank = 4; rank <= 11; rank += 1) {
    assert.equal(rules.isLegalMove(table, `D${rank}`), false, `D${rank} is already down`);
  }
  assert.equal(rules.isLegalMove(table, 'D3'), true);
  assert.equal(rules.isLegalMove(table, 'D12'), true);
});

test('both ends close at ace and king and the suit completes', () => {
  let table = tableFrom({ C: [2, 12] });
  assert.deepEqual(rules.nextNeeded(table, 'C'), { down: 1, up: 13 });
  table = rules.applyMove(table, 'C1');
  table = rules.applyMove(table, 'C13');
  assert.deepEqual(table.C, { low: 1, high: 13 });
  assert.equal(rules.isSuitComplete(table, 'C'), true);
  assert.deepEqual(rules.nextNeeded(table, 'C'), { down: null, up: null });
  assert.equal(rules.suitCardCount(table, 'C'), 13);
  // Nothing at all can be played into a finished suit.
  for (let rank = 1; rank <= 13; rank += 1) {
    assert.equal(rules.isLegalMove(table, `C${rank}`), false);
  }
});

test('applyMove is pure and rejects illegal cards', () => {
  const table = rules.createTable();
  const next = rules.applyMove(table, 'S7');
  assert.deepEqual(table.S, { low: null, high: null }, 'input table untouched');
  assert.deepEqual(next.S, { low: 7, high: 7 });
  assert.throws(() => rules.applyMove(table, 'S8'), /illegal move/);
  assert.throws(() => rules.applyMove(table, 'nope'), /illegal move/);
});

test('moveDirection reports anchor, up and down', () => {
  let table = rules.createTable();
  assert.equal(rules.moveDirection(table, 'H7'), 'anchor');
  table = rules.applyMove(table, 'H7');
  assert.equal(rules.moveDirection(table, 'H8'), 'up');
  assert.equal(rules.moveDirection(table, 'H6'), 'down');
  assert.equal(rules.moveDirection(table, 'H9'), null);
});

test('legalMoves filters a hand and deduplicates', () => {
  const table = tableFrom({ H: [7, 7] });
  const hand = ['H6', 'H8', 'H6', 'H10', 'S7', 'S9', 'D2'];
  assert.deepEqual(rules.legalMoves(table, hand), ['H6', 'H8', 'S7']);
  assert.equal(rules.hasLegalMove(table, ['H10', 'D2', 'S9']), false);
  assert.equal(rules.hasLegalMove(table, []), false);
  assert.deepEqual(rules.legalMoves(table, null), []);
});

test('pass eligibility is exactly zero legal moves', () => {
  const table = tableFrom({ H: [7, 8], S: [7, 7] });
  const stuck = ['H10', 'H12', 'S10', 'D5', 'C13'];
  assert.equal(rules.hasLegalMove(table, stuck), false);
  assert.equal(rules.hasLegalMove(table, stuck.concat(['C7'])), true);
  assert.equal(rules.hasLegalMove(table, stuck.concat(['S8'])), true);
  assert.equal(rules.hasLegalMove(table, stuck.concat(['H6'])), true);
});

test('table validation rejects impossible piles', () => {
  assert.equal(rules.isValidTable(rules.createTable()), true);
  assert.equal(rules.isValidTable(tableFrom({ H: [1, 13] })), true);
  assert.equal(rules.isValidTable(tableFrom({ H: [8, 9] })), false, 'low must be at most 7');
  assert.equal(rules.isValidTable(tableFrom({ H: [5, 6] })), false, 'high must be at least 7');
  assert.equal(rules.isValidTable(tableFrom({ H: [0, 7] })), false);
  assert.equal(rules.isValidTable(tableFrom({ H: [7, 14] })), false);
  assert.equal(rules.isValidTable({ H: { low: 7, high: null } }), false);
  assert.equal(rules.isValidTable(null), false);
});

test('deal counts spread the remainder over the first seats', () => {
  const expected = {
    2: [26, 26],
    3: [18, 17, 17],
    4: [13, 13, 13, 13],
    5: [11, 11, 10, 10, 10],
    6: [9, 9, 9, 9, 8, 8],
    7: [8, 8, 8, 7, 7, 7, 7],
    8: [7, 7, 7, 7, 6, 6, 6, 6],
  };
  for (const [count, sizes] of Object.entries(expected)) {
    const actual = rules.dealCounts(Number(count));
    assert.deepEqual(actual, sizes, `deal for ${count} players`);
    assert.equal(actual.reduce((a, b) => a + b, 0), 52, 'whole deck is dealt');
    assert.ok(Math.max(...actual) - Math.min(...actual) <= 1, 'sizes differ by at most one');
  }
  assert.throws(() => rules.dealCounts(0), TypeError);
  assert.throws(() => rules.dealCounts(2.5), TypeError);
});

test('dealHands hands out every distinct card once', () => {
  const deck = cards.shuffle(cards.buildDeck(), cards.createRng(99));
  for (let players = 2; players <= 8; players += 1) {
    const hands = rules.dealHands(deck, players);
    const all = hands.flat();
    assert.equal(all.length, 52);
    assert.equal(new Set(all).size, 52);
    assert.deepEqual(hands.map((h) => h.length), rules.dealCounts(players));
  }
  assert.throws(() => rules.dealHands(deck.slice(0, 51), 4), TypeError);
});

test('a seat dealt zero cards has already won', () => {
  // 53 seats is impossible in the app but the engine must not produce a broken
  // state: the empty seat wins immediately instead of the turn loop hanging.
  const counts = rules.dealCounts(53);
  assert.equal(counts[52], 0);
  const hands = [['H7'], []];
  assert.equal(rules.findWinnerSeat(hands), 1);
});

test('ranking is by cards remaining with shared ranks', () => {
  assert.deepEqual(rules.rankSeats([0, 3, 5, 1]), [1, 3, 4, 2]);
  assert.deepEqual(rules.rankSeats([0, 2, 2, 5]), [1, 2, 2, 4]);
  assert.deepEqual(rules.rankSeats([4, 4, 4]), [1, 1, 1]);
  assert.deepEqual(rules.rankSeats([0, 1]), [1, 2]);
});

test('the seven of diamonds holder opens the round', () => {
  const state = engine.startRound({ seatCount: 4, timerSeconds: 15, seed: 4242 });
  const seat = state.hands.findIndex((hand) => hand.includes('D7'));
  assert.equal(state.currentTurnSeat, seat);
  assert.ok(rules.hasLegalMove(state.table, state.hands[state.currentTurnSeat]));
});

test('engine rejects out of turn, missing, and illegal cards', () => {
  const state = engine.startRound({ seatCount: 3, timerSeconds: 15, seed: 7 });
  const seat = state.currentTurnSeat;
  const other = (seat + 1) % 3;
  assert.throws(() => engine.playCard(state, other, state.hands[other][0]), (err) => err.code === 'NOT_YOUR_TURN');
  assert.throws(() => engine.playCard(state, seat, 'not-a-card'), (err) => err.code === 'BAD_CARD');
  const notHeld = cards.buildDeck().find((c) => !state.hands[seat].includes(c));
  assert.throws(() => engine.playCard(state, seat, notHeld), (err) => err.code === 'CARD_NOT_IN_HAND');
  const illegal = state.hands[seat].find((c) => !rules.isLegalMove(state.table, c));
  if (illegal) {
    assert.throws(() => engine.playCard(state, seat, illegal), (err) => err.code === 'ILLEGAL_MOVE');
  }
  assert.throws(() => engine.pass(state, seat), (err) => err.code === 'MUST_PLAY');
  assert.throws(() => engine.playCard(state, 9, 'H7'), (err) => err.code === 'BAD_SEAT');
});

test('a legal play advances the turn and shrinks the hand', () => {
  const state = engine.startRound({ seatCount: 4, timerSeconds: 15, seed: 1234 });
  const seat = state.currentTurnSeat;
  const before = state.hands[seat].length;
  const card = rules.legalMoves(state.table, state.hands[seat])[0];
  const entry = engine.playCard(state, seat, card);
  assert.equal(entry.type, 'play');
  assert.equal(entry.auto, false);
  assert.equal(state.hands[seat].length, before - 1);
  assert.equal(state.hands[seat].includes(card), false);
  assert.notEqual(state.currentTurnSeat, seat);
  assert.equal(rules.isLegalMove(state.table, card), false, 'card is now on the table');
});

test('timeout auto plays a legal card and auto passes an unplayable hand', () => {
  const state = engine.startRound({ seatCount: 4, timerSeconds: 15, seed: 31337 });
  assert.equal(engine.resolveTimeout(state, state.turnStartedAt + 1000), null, 'not expired yet');

  const seat = state.currentTurnSeat;
  const expiry = state.turnStartedAt + 15000;
  const entry = engine.resolveTimeout(state, expiry, () => 0.5);
  assert.equal(entry.type, 'play');
  assert.equal(entry.auto, true);
  assert.equal(entry.seatIndex, seat);
  assert.equal(state.turnStartedAt, expiry, 'the next turn clock restarts');

  // Force a hand with zero legal moves and confirm the timeout passes it.
  const stuckSeat = state.currentTurnSeat;
  state.hands[stuckSeat] = ['H13', 'S13', 'D13', 'C13'];
  state.table = { H: { low: 7, high: 7 }, D: { low: 7, high: 7 }, C: { low: null, high: null }, S: { low: null, high: null } };
  const passEntry = engine.resolveTimeout(state, state.turnStartedAt + 15000, () => 0.5);
  assert.equal(passEntry.type, 'pass');
  assert.equal(passEntry.auto, true);
  assert.equal(passEntry.seatIndex, stuckSeat);
  assert.equal(state.hands[stuckSeat].length, 4, 'a pass never removes a card');
});

test('passing does not skip a seat on later turns', () => {
  const state = engine.startRound({ seatCount: 3, timerSeconds: 15, seed: 555 });
  state.table = { H: { low: 7, high: 7 }, D: { low: null, high: null }, C: { low: null, high: null }, S: { low: null, high: null } };
  state.hands = [['H6', 'H8'], ['S13'], ['C13']];
  state.currentTurnSeat = 1;
  engine.pass(state, 1);
  assert.equal(state.currentTurnSeat, 2);
  engine.pass(state, 2);
  assert.equal(state.currentTurnSeat, 0);
  engine.playCard(state, 0, 'H6');
  assert.equal(state.currentTurnSeat, 1, 'the seat that passed is still in the rotation');
  engine.pass(state, 1);
  assert.equal(state.currentTurnSeat, 2);
});

test('emptying a hand ends the round and ranks every seat', () => {
  const state = engine.startRound({ seatCount: 3, timerSeconds: 15, seed: 8 });
  state.table = { H: { low: 7, high: 7 }, D: { low: null, high: null }, C: { low: null, high: null }, S: { low: null, high: null } };
  state.hands = [['H8'], ['S1', 'S2', 'S3'], ['C13']];
  state.currentTurnSeat = 0;
  engine.playCard(state, 0, 'H8');
  assert.equal(state.status, engine.STATUS.FINISHED);
  assert.equal(state.winnerSeat, 0);
  assert.deepEqual(state.ranks, [1, 3, 2]);
  assert.deepEqual(state.scores, [1, 3, 2]);
  assert.throws(() => engine.playCard(state, 1, 'S1'), (err) => err.code === 'ROUND_NOT_ACTIVE');
  assert.throws(() => engine.pass(state, 1), (err) => err.code === 'ROUND_NOT_ACTIVE');
});

test('multi round matches carry scores and rank by total', () => {
  let state = engine.startRound({ seatCount: 3, timerSeconds: 15, rounds: 2, seed: 21 });
  state.table = { H: { low: 7, high: 7 }, D: { low: null, high: null }, C: { low: null, high: null }, S: { low: null, high: null } };
  state.hands = [['H8'], ['S1', 'S2'], ['C13']];
  state.currentTurnSeat = 0;
  engine.playCard(state, 0, 'H8');
  assert.equal(state.status, engine.STATUS.ROUND_OVER);
  assert.deepEqual(state.scores, [1, 3, 2]);

  state = engine.nextRound(state, Date.now(), 22);
  assert.equal(state.round, 2);
  assert.deepEqual(state.scores, [1, 3, 2], 'scores carry over');
  state.table = { H: { low: 7, high: 7 }, D: { low: null, high: null }, C: { low: null, high: null }, S: { low: null, high: null } };
  state.hands = [['H10'], ['H8'], ['C13']];
  state.currentTurnSeat = 1;
  engine.playCard(state, 1, 'H8');
  assert.equal(state.status, engine.STATUS.FINISHED);
  assert.deepEqual(state.scores, [3, 4, 4]);
  const standings = engine.matchStandings(state);
  assert.equal(standings[0].rank, 1);
  assert.equal(standings[1].rank, 2);
  assert.equal(standings[2].rank, 2);
  assert.throws(() => engine.nextRound(state), (err) => err.code === 'ROUND_NOT_OVER');
});

test('startRound validates its settings', () => {
  assert.throws(() => engine.startRound({ seatCount: 1, timerSeconds: 15 }), (err) => err.code === 'BAD_SEAT_COUNT');
  assert.throws(() => engine.startRound({ seatCount: 9, timerSeconds: 15 }), (err) => err.code === 'BAD_SEAT_COUNT');
  assert.throws(() => engine.startRound({ seatCount: 4, timerSeconds: 2 }), (err) => err.code === 'BAD_TIMER');
  assert.throws(() => engine.startRound({ seatCount: 4, timerSeconds: 500 }), (err) => err.code === 'BAD_TIMER');
});

test('publicView never leaks another hand', () => {
  const state = engine.startRound({ seatCount: 4, timerSeconds: 15, seed: 12 });
  const view = engine.publicView(state, 2, state.turnStartedAt + 3000);
  assert.deepEqual(view.yourHand, state.hands[2]);
  assert.deepEqual(view.handCounts, state.hands.map((h) => h.length));
  assert.equal(view.millisLeft, 12000);
  const serialised = JSON.stringify(view);
  for (let seat = 0; seat < 4; seat += 1) {
    if (seat === 2) continue;
    for (const card of state.hands[seat]) {
      if (state.hands[2].includes(card)) continue;
      assert.equal(serialised.includes(`"${card}"`), false, `${card} from seat ${seat} leaked`);
    }
  }
  const spectator = engine.publicView(state, null);
  assert.deepEqual(spectator.yourHand, []);
  assert.deepEqual(spectator.yourLegalMoves, []);
  assert.equal(spectator.canPass, false);
});

test('a publicView is a snapshot and does not change when the game moves on', () => {
  const state = engine.startRound({ seatCount: 2, timerSeconds: 15, rounds: 2, seed: 9 });
  const dealt = engine.publicView(state, 0);
  const frozen = JSON.parse(JSON.stringify(dealt));

  // Win the round outright: one card in hand and an empty table that wants it.
  state.table = rules.createTable();
  state.hands = [['D7'], ['C9', 'C10']];
  state.currentTurnSeat = 0;
  engine.playCard(state, 0, 'D7', 1000);
  assert.equal(state.status, engine.STATUS.ROUND_OVER);
  engine.nextRound(state, 2000);
  // Nothing handed out earlier may be rewritten by later play.
  assert.deepEqual(dealt, frozen);
  assert.deepEqual(dealt.roundResults, []);
  assert.deepEqual(dealt.scores, [0, 0]);
  assert.equal(dealt.ranks, null);

  const after = engine.publicView(state, 0);
  assert.equal(after.roundResults.length, 1);
  after.roundResults[0].ranks[0] = 99;
  after.scores[0] = 99;
  after.handCounts[0] = 99;
  assert.notEqual(state.roundResults[0].ranks[0], 99, 'caller mutated engine state');
  assert.notEqual(state.scores[0], 99, 'caller mutated engine state');
  assert.equal(engine.publicView(state, 0).handCounts[0], state.hands[0].length);
});

test('canPass is only true for the active seat with nothing to play', () => {
  const state = engine.startRound({ seatCount: 2, timerSeconds: 15, seed: 3 });
  state.table = { H: { low: 7, high: 7 }, D: { low: null, high: null }, C: { low: null, high: null }, S: { low: null, high: null } };
  state.hands = [['H13'], ['H6']];
  state.currentTurnSeat = 0;
  assert.equal(engine.publicView(state, 0).canPass, true);
  assert.equal(engine.publicView(state, 1).canPass, false, 'not this seat turn');
  state.currentTurnSeat = 1;
  assert.equal(engine.publicView(state, 1).canPass, false, 'this seat has a legal move');
});
