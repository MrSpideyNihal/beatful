'use strict';

/**
 * Economy tests.
 *
 * The point of this file is the money: a coin must never be created or destroyed
 * by a race, a retry or a concurrent request. Every test ends by auditing the
 * same invariant the definition of done asks for, that a player balance equals
 * the sum of their ledger rows.
 */

const test = require('node:test');
const assert = require('node:assert/strict');

const harness = require('./helpers/api');
const coins = require('../src/services/coins');

const { config, getStore, rateLimit } = harness;

let server;

test.before(async () => {
  server = await harness.startTestServer();
});

test.after(async () => {
  await server.close();
});

test.beforeEach(() => {
  rateLimit.resetAll();
});

/** The invariant: balance equals the sum of every ledger row for that user. */
async function auditLedger(userId) {
  const store = getStore();
  const user = await store.users.findById(userId);
  const sum = await store.transactions.sumForUser(userId);
  assert.equal(user.coins, sum, `ledger and balance disagree for ${userId}`);
  assert.ok(user.coins >= 0, 'a balance must never go negative');
  return user.coins;
}

test('a new account starts with the configured coins and a matching ledger row', async () => {
  const player = await server.player('Asha');
  assert.equal(await auditLedger(player.userId), config.startingCoins);
  const history = await player.get('/user/transactions');
  assert.equal(history.status, 200);
  assert.equal(history.body.transactions.length, 1);
  assert.equal(history.body.transactions[0].type, 'signup_bonus');
  assert.equal(history.body.transactions[0].amount, config.startingCoins);
});

test('concurrent debits can never overdraw a balance', async () => {
  const player = await server.player('Asha');
  const attempts = 80;
  const amount = 10;
  const affordable = config.startingCoins / amount;

  const results = await Promise.all(
    Array.from({ length: attempts }, () =>
      coins.debit(player.userId, amount, { type: coins.TYPES.MATCH_ENTRY }).then(
        () => 'ok',
        (err) => err.code,
      ),
    ),
  );

  const succeeded = results.filter((entry) => entry === 'ok').length;
  const refused = results.filter((entry) => entry === 'INSUFFICIENT_COINS').length;
  assert.equal(succeeded, affordable, 'exactly as many debits as the balance allows');
  assert.equal(refused, attempts - affordable);
  assert.equal(await auditLedger(player.userId), 0);
});

test('concurrent purchases of the same item charge exactly once', async () => {
  const player = await server.player('Asha');
  const itemId = 'back_paisley'; // 350 coins.

  const results = await Promise.all(
    Array.from({ length: 15 }, () => player.post('/shop/purchase', { itemId })),
  );
  const ok = results.filter((res) => res.status === 200);
  assert.equal(ok.length, 1, 'one purchase, not fifteen');
  for (const res of results.filter((entry) => entry.status !== 200)) {
    assert.ok(['ALREADY_OWNED', 'INSUFFICIENT_COINS'].includes(res.body.error), res.body.error);
  }

  const balance = await auditLedger(player.userId);
  assert.equal(balance, config.startingCoins - 350);
  const me = await player.get('/user/me');
  assert.deepEqual(me.body.user.ownedItems, [itemId]);
});

test('the shop prices from the server table, not from the request', async () => {
  const player = await server.player('Asha');
  const res = await player.post('/shop/purchase', { itemId: 'back_mint', price: 1, amount: 1 });
  assert.equal(res.status, 200);
  assert.equal(res.body.user.coins, config.startingCoins - 500);
  await auditLedger(player.userId);
});

test('an unaffordable item is refused and a free one cannot be bought', async () => {
  const player = await server.player('Asha');
  await player.post('/shop/purchase', { itemId: 'back_mint' }); // 500 of 500.

  const broke = await player.post('/shop/purchase', { itemId: 'back_paisley' });
  assert.equal(broke.status, 409);
  assert.equal(broke.body.error, 'INSUFFICIENT_COINS');

  const free = await player.post('/shop/purchase', { itemId: 'back_classic' });
  assert.equal(free.status, 400);
  assert.equal(free.body.error, 'ALREADY_OWNED');

  const unknown = await player.post('/shop/purchase', { itemId: 'back-does-not-exist' });
  assert.equal(unknown.status, 404);
  assert.equal(unknown.body.error, 'ITEM_NOT_FOUND');

  assert.equal(await auditLedger(player.userId), 0);
});

test('an item can only be equipped once it is owned', async () => {
  const player = await server.player('Asha');
  const denied = await player.post('/shop/equip', { itemId: 'table_slate' });
  assert.equal(denied.status, 403);
  assert.match(denied.body.message, /Buy it first/i);

  const free = await player.post('/shop/equip', { itemId: 'table_green' });
  assert.equal(free.status, 200);
  assert.equal(free.body.user.selected.table, 'table_green');

  await player.post('/shop/purchase', { itemId: 'table_slate' });
  const equipped = await player.post('/shop/equip', { itemId: 'table_slate' });
  assert.equal(equipped.status, 200);
  assert.equal(equipped.body.user.selected.table, 'table_slate');
  assert.equal(equipped.body.user.selected.cardBack, 'back_classic');
});

test('the daily ad cap holds under concurrent claims', async () => {
  const player = await server.player('Asha');
  const cap = config.adRewardDailyCap;

  const results = await Promise.all(
    Array.from({ length: cap + 4 }, () => player.post('/ads/reward')),
  );
  const granted = results.filter((res) => res.status === 200);
  const capped = results.filter((res) => res.status === 429);
  assert.equal(granted.length, cap, 'never more grants than the cap');
  assert.equal(capped.length, 4);
  for (const res of capped) assert.equal(res.body.error, 'DAILY_AD_LIMIT');

  const balance = await auditLedger(player.userId);
  assert.equal(balance, config.startingCoins + cap * config.adRewardCoins);

  const status = await player.get('/ads/status');
  assert.equal(status.body.claimedToday, cap);
  assert.equal(status.body.remainingToday, 0);
});

test('an entry fee nobody can pay refunds everyone who already paid', async () => {
  const host = await server.player('Asha');
  const guest = await server.player('Ravi');

  // Drain the guest so the second charge has to fail.
  await coins.debit(guest.userId, config.startingCoins, { type: coins.TYPES.SHOP_PURCHASE });

  const room = await host.post('/room/create', {
    settings: { playerCount: 2, coinMatch: true, entryFee: 100 },
  });
  assert.equal(room.status, 201);
  await guest.post('/room/join', { code: room.body.room.roomCode });

  const started = await host.post(`/room/${room.body.room.roomId}/start`);
  assert.equal(started.status, 409);
  assert.equal(started.body.error, 'INSUFFICIENT_COINS');

  assert.equal(await auditLedger(host.userId), config.startingCoins, 'the host must be refunded');
  assert.equal(await auditLedger(guest.userId), 0);

  const view = await host.get(`/room/${room.body.room.roomId}`);
  assert.equal(view.body.room.status, 'lobby', 'a failed start leaves the room playable');
});

test('a coin match moves the pool to the winner and nowhere else', async () => {
  const host = await server.player('Asha');
  const guest = await server.player('Ravi');
  const fee = 120;

  const created = await host.post('/room/create', {
    settings: { playerCount: 2, coinMatch: true, entryFee: fee, timerSeconds: 5 },
  });
  const roomId = created.body.room.roomId;
  await guest.post('/room/join', { code: created.body.room.roomCode });
  const started = await host.post(`/room/${roomId}/start`);
  assert.equal(started.status, 200);
  for (const player of started.body.room.players) assert.equal(player.stake, fee);

  const done = await harness.fastForward(roomId);
  assert.ok(done.finished);

  const view = await host.get(`/room/${roomId}`);
  const result = view.body.room.result;
  assert.equal(result.pool, fee * 2);
  assert.equal(result.payouts.length, 1);
  assert.equal(result.payouts[0].amount, fee * 2);

  const winnerSeat = result.payouts[0].seatIndex;
  const seats = new Map(view.body.room.players.map((player) => [player.seatIndex, player.userId]));
  const winnerId = seats.get(winnerSeat);
  const loserId = winnerId === host.userId ? guest.userId : host.userId;

  assert.equal(await auditLedger(winnerId), config.startingCoins + fee);
  assert.equal(await auditLedger(loserId), config.startingCoins - fee);
});

test('settlement pays out exactly once even if it is asked to run again', async () => {
  const host = await server.player('Asha');
  const guest = await server.player('Ravi');

  const created = await host.post('/room/create', {
    settings: { playerCount: 2, coinMatch: true, entryFee: 50, timerSeconds: 5 },
  });
  const roomId = created.body.room.roomId;
  await guest.post('/room/join', { code: created.body.room.roomCode });
  await host.post(`/room/${roomId}/start`);
  await harness.fastForward(roomId);

  const before = (await getStore().users.findById(host.userId)).coins
    + (await getStore().users.findById(guest.userId)).coins;

  const room = await harness.rooms.requireRoom(roomId);
  await harness.rooms.settleMatch(room);
  await harness.rooms.settleMatch(room);
  await harness.rooms.tickRoom(roomId, Date.now() + 60_000);

  const after = (await getStore().users.findById(host.userId)).coins
    + (await getStore().users.findById(guest.userId)).coins;
  assert.equal(after, before, 'a repeated settlement must not pay twice');
  await auditLedger(host.userId);
  await auditLedger(guest.userId);
});

test('a free match never touches a balance', async () => {
  const host = await server.player('Asha');
  const guest = await server.player('Ravi');
  const created = await host.post('/room/create', { settings: { playerCount: 2, timerSeconds: 5 } });
  const roomId = created.body.room.roomId;
  await guest.post('/room/join', { code: created.body.room.roomCode });
  await host.post(`/room/${roomId}/start`);
  await harness.fastForward(roomId);

  assert.equal(await auditLedger(host.userId), config.startingCoins);
  assert.equal(await auditLedger(guest.userId), config.startingCoins);
  const view = await host.get(`/room/${roomId}`);
  assert.equal(view.body.room.result.pool, 0);
  assert.equal(view.body.room.result.payouts.length, 0);
});

test('a player beaten by a bot still takes the pool but is not ranked first', async () => {
  // Bots stake nothing, so the coins go to the best human. The standings a
  // player reads afterwards must still show the bot in front, which is only
  // true while the payout re-ranking works on copies.
  const host = await server.player('Asha');
  const fee = 80;
  const created = await host.post('/room/create', {
    settings: { playerCount: 2, coinMatch: true, entryFee: fee, timerSeconds: 5 },
  });
  const roomId = created.body.room.roomId;
  await host.post(`/room/${roomId}/bot`, { difficulty: 'hard' });
  await host.post(`/room/${roomId}/start`);

  // A finished match the bot won, written straight into the state so the
  // outcome is not left to a shuffle.
  const room = await harness.rooms.requireRoom(roomId);
  const botSeat = room.players.find((player) => player.isBot).seatIndex;
  const humanSeat = room.players.find((player) => !player.isBot).seatIndex;
  room.gameState.status = 'finished';
  room.gameState.scores[humanSeat] = 6;
  room.gameState.scores[botSeat] = 0;
  await harness.rooms.settleMatch(room);

  const result = room.result;
  const rankOf = (seat) => result.standings.find((entry) => entry.seatIndex === seat).rank;
  assert.equal(rankOf(botSeat), 1, 'the bot had the lower score, so it came first');
  assert.equal(rankOf(humanSeat), 2);
  assert.equal(result.payouts.length, 1);
  assert.equal(result.payouts[0].seatIndex, humanSeat);
  assert.equal(result.payouts[0].amount, fee);
  assert.equal(await auditLedger(host.userId), config.startingCoins);
});

test('50 concurrent coin matches leave every balance and ledger consistent', async () => {
  const matchCount = 50;
  const fee = 100;
  const tables = [];

  for (let i = 0; i < matchCount; i += 1) {
    const host = await server.player(`Host ${i + 1}`);
    const guest = await server.player(`Guest ${i + 1}`);
    const created = await host.post('/room/create', {
      settings: { playerCount: 2, coinMatch: true, entryFee: fee, timerSeconds: 5 },
    });
    assert.equal(created.status, 201, JSON.stringify(created.body));
    const joined = await guest.post('/room/join', { code: created.body.room.roomCode });
    assert.equal(joined.status, 200);
    tables.push({ host, guest, roomId: created.body.room.roomId });
  }

  const starts = await Promise.all(tables.map((table) => table.host.post(`/room/${table.roomId}/start`)));
  for (const res of starts) assert.equal(res.status, 200, JSON.stringify(res.body));

  const finishes = await Promise.all(tables.map((table) => harness.fastForward(table.roomId)));
  for (const done of finishes) assert.ok(done.finished, 'every table should reach the end');

  let total = 0;
  for (const table of tables) {
    const hostCoins = await auditLedger(table.host.userId);
    const guestCoins = await auditLedger(table.guest.userId);
    total += hostCoins + guestCoins;

    // Winner takes the whole pool, loser is down the fee. One round cannot tie.
    const pair = [hostCoins, guestCoins].sort((a, b) => a - b);
    assert.deepEqual(pair, [config.startingCoins - fee, config.startingCoins + fee]);
  }

  assert.equal(total, matchCount * 2 * config.startingCoins, 'coins are conserved across all matches');
});

/* --------------------------------------------------------- payout arithmetic */

test('winner takes all splits a tie evenly and loses nothing to rounding', async () => {
  const standings = [
    { seatIndex: 0, rank: 1, score: 2 },
    { seatIndex: 1, rank: 1, score: 2 },
    { seatIndex: 2, rank: 3, score: 5 },
  ];
  const payouts = coins.computePayouts(301, standings, 'winner_takes_all');
  assert.equal(payouts.get(0), 151);
  assert.equal(payouts.get(1), 150);
  assert.equal(payouts.has(2), false);
  assert.equal([...payouts.values()].reduce((a, b) => a + b, 0), 301);
});

test('ranked split always hands out the pool exactly', async () => {
  for (const pool of [1, 7, 99, 100, 1001]) {
    for (const seatCount of [2, 3, 4, 5, 6, 7, 8]) {
      const standings = Array.from({ length: seatCount }, (unused, index) => ({
        seatIndex: index,
        rank: index + 1,
        score: index + 1,
      }));
      const payouts = coins.computePayouts(pool, standings, 'ranked_split');
      const sum = [...payouts.values()].reduce((a, b) => a + b, 0);
      assert.equal(sum, pool, `pool ${pool} across ${seatCount} seats`);
      for (const amount of payouts.values()) assert.ok(amount > 0);
    }
  }
});

test('an empty pool pays nobody', async () => {
  assert.equal(coins.computePayouts(0, [{ seatIndex: 0, rank: 1, score: 1 }], 'winner_takes_all').size, 0);
  assert.equal(coins.computePayouts(100, [], 'ranked_split').size, 0);
});

test('a debit or credit of a silly amount is refused outright', async () => {
  const player = await server.player('Asha');
  for (const amount of [0, -5, 1.5, Number.NaN, '10']) {
    await assert.rejects(() => coins.debit(player.userId, amount, {}), /Invalid coin amount/);
    await assert.rejects(() => coins.credit(player.userId, amount, {}), /Invalid coin amount/);
  }
  assert.equal(await auditLedger(player.userId), config.startingCoins);
});
