'use strict';

/**
 * API level tests.
 *
 * Everything here goes over real HTTP against the real express app, so a passing
 * run means routing, auth, validation, turn order enforcement and the long poll
 * all behave as a device would see them.
 */

const test = require('node:test');
const assert = require('node:assert/strict');

const harness = require('./helpers/api');
const rules = require('../src/game/rules');
const cards = require('../src/game/cards');

const { rooms, rateLimit, config } = harness;

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

/* ----------------------------------------------------------------- helpers */

async function createRoom(host, settings) {
  const res = await host.post('/room/create', { settings: settings || {} });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  return res.body.room;
}

async function joinRoom(client, code) {
  const res = await client.post('/room/join', { code });
  assert.equal(res.status, 200, JSON.stringify(res.body));
  return res.body.room;
}

async function viewFor(client, roomId) {
  const res = await client.get(`/room/${roomId}`);
  assert.equal(res.status, 200, JSON.stringify(res.body));
  return res.body.room;
}

/** Two humans in a started room, plus the room view each of them sees. */
async function startedPair(settings) {
  const host = await server.player('Asha');
  const guest = await server.player('Ravi');
  const room = await createRoom(host, { playerCount: 2, timerSeconds: 15, ...settings });
  await joinRoom(guest, room.roomCode);
  const started = await host.post(`/room/${room.roomId}/start`);
  assert.equal(started.status, 200, JSON.stringify(started.body));
  return { host, guest, roomId: room.roomId, roomCode: room.roomCode };
}

/** The client whose seat is on turn, and its current view. */
async function onTurn(clients, roomId) {
  for (const client of clients) {
    const view = await viewFor(client, roomId);
    if (view.game && view.game.currentTurnSeat === view.yourSeat) return { client, view };
  }
  throw new Error('no client is on turn');
}

/* -------------------------------------------------------------- open routes */

test('health and meta answer without a token', async () => {
  const health = await server.anon.get('/health');
  assert.equal(health.status, 200);
  assert.equal(health.body.ok, true);

  const meta = await server.anon.get('/meta');
  assert.equal(meta.status, 200);
  assert.equal(meta.body.minPlayers, 2);
  assert.equal(meta.body.maxPlayers, 8);
  assert.match(meta.body.coinPolicy, /cannot be exchanged for real money/);
});

test('unknown route returns the standard error shape, never a stack', async () => {
  const res = await server.anon.get('/no/such/thing');
  assert.equal(res.status, 404);
  assert.deepEqual(Object.keys(res.body).sort(), ['error', 'message']);
  assert.equal(res.body.error, 'NOT_FOUND');
});

test('protected routes reject a missing or bad token', async () => {
  const missing = await server.anon.get('/user/me');
  assert.equal(missing.status, 401);
  assert.equal(missing.body.error, 'UNAUTHORIZED');

  const bad = await harness.makeClient(server.base, 'not.a.real.token').get('/user/me');
  assert.equal(bad.status, 401);
  assert.equal(bad.body.error, 'TOKEN_INVALID');
  assert.ok(!('stack' in bad.body));
});

/* ---------------------------------------------------------------- identity */

test('user init is idempotent for the same device id', async () => {
  const guestId = 'device-aaaa-bbbb-cccc-1234';
  const first = await server.anon.post('/user/init', { guestId });
  assert.equal(first.status, 200);
  assert.equal(first.body.isNewUser, true);
  assert.equal(first.body.user.coins, config.startingCoins);

  const second = await server.anon.post('/user/init', { guestId });
  assert.equal(second.status, 200);
  assert.equal(second.body.isNewUser, false);
  assert.equal(second.body.user.userId, first.body.user.userId);
});

test('user init and rename validate their input', async () => {
  const short = await server.anon.post('/user/init', { guestId: 'nope' });
  assert.equal(short.status, 400);
  assert.equal(short.body.error, 'BAD_REQUEST');

  const player = await server.player('Meera');
  const bad = await player.patch('/user/name', { displayName: 'x' });
  assert.equal(bad.status, 400);
  assert.equal(bad.body.error, 'NAME_INVALID');

  const ok = await player.patch('/user/name', { displayName: '  Meera   Devi  ' });
  assert.equal(ok.status, 200);
  assert.equal(ok.body.user.displayName, 'Meera Devi');
});

/* ------------------------------------------------------------------- rooms */

test('room lookup reports a mistyped and an unknown code differently', async () => {
  const host = await server.player('Asha');
  const room = await createRoom(host);

  const malformed = await host.get('/room/lookup?code=AB');
  assert.equal(malformed.status, 400);
  assert.equal(malformed.body.error, 'BAD_ROOM_CODE');

  const unknown = await host.get('/room/lookup?code=ZZZZZZ');
  assert.equal(unknown.status, 404);
  assert.equal(unknown.body.error, 'ROOM_NOT_FOUND');

  const found = await host.get(`/room/lookup?code=${room.roomCode}`);
  assert.equal(found.status, 200);
  assert.equal(found.body.canJoin, true);
  assert.equal(found.body.alreadyIn, true);
  assert.equal(found.body.link, `beatful://join/${room.roomCode}`);
});

test('join refuses a full room, a locked room and a started room', async () => {
  const host = await server.player('Asha');
  const guest = await server.player('Ravi');
  const third = await server.player('Nikhil');
  const room = await createRoom(host, { playerCount: 2 });

  await joinRoom(guest, room.roomCode);
  const full = await third.post('/room/join', { code: room.roomCode });
  assert.equal(full.status, 409);
  assert.equal(full.body.error, 'ROOM_FULL');

  const bigger = await host.post(`/room/${room.roomId}/settings`, { settings: { playerCount: 3 } });
  assert.equal(bigger.status, 200);
  await host.post(`/room/${room.roomId}/lock`, { locked: true });
  const locked = await third.post('/room/join', { code: room.roomCode });
  assert.equal(locked.status, 403);
  assert.equal(locked.body.error, 'ROOM_LOCKED');

  await host.post(`/room/${room.roomId}/lock`, { locked: false });
  const started = await host.post(`/room/${room.roomId}/start`);
  assert.equal(started.status, 200);
  const late = await third.post('/room/join', { code: room.roomCode });
  assert.equal(late.status, 400);
  assert.equal(late.body.error, 'ALREADY_STARTED');
});

test('host only controls are enforced on the server', async () => {
  const host = await server.player('Asha');
  const guest = await server.player('Ravi');
  const room = await createRoom(host, { playerCount: 3 });
  await joinRoom(guest, room.roomCode);

  for (const [path, body] of [
    [`/room/${room.roomId}/settings`, { settings: { timerSeconds: 30 } }],
    [`/room/${room.roomId}/start`, {}],
    [`/room/${room.roomId}/lock`, { locked: true }],
    [`/room/${room.roomId}/bot`, {}],
    [`/room/${room.roomId}/kick`, { userId: host.userId }],
  ]) {
    const res = await guest.post(path, body);
    assert.equal(res.status, 403, `${path} should be host only`);
    assert.equal(res.body.error, 'NOT_HOST');
  }

  const selfKick = await host.post(`/room/${room.roomId}/kick`, { userId: host.userId });
  assert.equal(selfKick.status, 403);
  assert.equal(selfKick.body.error, 'FORBIDDEN');

  const kicked = await host.post(`/room/${room.roomId}/kick`, { userId: guest.userId });
  assert.equal(kicked.status, 200);
  assert.equal(kicked.body.room.players.length, 1);
});

test('settings are validated and locked once the game starts', async () => {
  const host = await server.player('Asha');
  const room = await createRoom(host, { playerCount: 2, fillWithBots: true });

  const tooMany = await host.post(`/room/${room.roomId}/settings`, { settings: { playerCount: 9 } });
  assert.equal(tooMany.status, 400);
  assert.equal(tooMany.body.error, 'SETTINGS_INVALID');

  const badTimer = await host.post(`/room/${room.roomId}/settings`, { settings: { timerSeconds: 2 } });
  assert.equal(badTimer.status, 400);

  const feeless = await host.post(`/room/${room.roomId}/settings`, { settings: { coinMatch: true, entryFee: 0 } });
  assert.equal(feeless.status, 400);
  assert.match(feeless.body.message, /entry fee/i);

  await host.post(`/room/${room.roomId}/start`);
  const late = await host.post(`/room/${room.roomId}/settings`, { settings: { timerSeconds: 20 } });
  assert.equal(late.status, 400);
  assert.equal(late.body.error, 'ALREADY_STARTED');
});

test('a non member cannot read or act on a room', async () => {
  const { roomId } = await startedPair();
  const stranger = await server.player('Outsider');

  const read = await stranger.get(`/room/${roomId}`);
  assert.equal(read.status, 403);
  assert.equal(read.body.error, 'NOT_IN_ROOM');

  const play = await stranger.post(`/room/${roomId}/play`, { card: 'D7' });
  assert.equal(play.status, 403);
  assert.equal(play.body.error, 'NOT_IN_ROOM');

  const poll = await stranger.get(`/room/${roomId}/state?since=0`);
  assert.equal(poll.status, 403);
  assert.equal(poll.body.error, 'NOT_IN_ROOM');
});

test('a room that does not exist is a clean 404', async () => {
  const player = await server.player('Asha');
  const res = await player.get('/room/11111111-2222-3333-4444-555555555555');
  assert.equal(res.status, 404);
  assert.equal(res.body.error, 'ROOM_NOT_FOUND');
});

/* ---------------------------------------------------------------- gameplay */

test('the starting seat holds the seven of diamonds', async () => {
  const { host, guest, roomId } = await startedPair();
  const { view } = await onTurn([host, guest], roomId);
  assert.ok(view.game.yourHand.includes('D7'));
  assert.ok(view.game.yourLegalMoves.includes('D7'));
});

test('an illegal card is rejected and the turn does not move', async () => {
  const { host, guest, roomId } = await startedPair();
  const { client, view } = await onTurn([host, guest], roomId);

  // The table is empty, so only a seven can be played.
  const notASeven = view.game.yourHand.find((card) => cards.rankOf(card) !== cards.ANCHOR_RANK);
  assert.ok(notASeven, 'a 26 card hand always has a non seven');

  const res = await client.post(`/room/${roomId}/play`, { card: notASeven });
  assert.equal(res.status, 400);
  assert.equal(res.body.error, 'ILLEGAL_MOVE');

  const after = await viewFor(client, roomId);
  assert.equal(after.game.currentTurnSeat, view.yourSeat);
  assert.equal(after.game.yourHand.length, view.game.yourHand.length);
  assert.equal(rules.tableCardCount(after.game.table), 0);
});

test('a card the player does not hold is rejected', async () => {
  const { host, guest, roomId } = await startedPair();
  const { client, view } = await onTurn([host, guest], roomId);
  const held = new Set(view.game.yourHand);
  const notHeld = cards.buildDeck().find((card) => !held.has(card));

  const res = await client.post(`/room/${roomId}/play`, { card: notHeld });
  assert.equal(res.status, 400);
  assert.equal(res.body.error, 'CARD_NOT_IN_HAND');
});

test('junk in the card field is rejected before any game logic', async () => {
  const { host, guest, roomId } = await startedPair();
  const { client } = await onTurn([host, guest], roomId);

  for (const junk of ['', 'ZZ', 'H0', 'H14', 'hearts', 42, null, { card: 'H7' }]) {
    const res = await client.post(`/room/${roomId}/play`, { card: junk });
    assert.equal(res.status, 400, `expected ${JSON.stringify(junk)} to be refused`);
    assert.equal(res.body.error, 'BAD_CARD');
  }
});

test('playing out of turn is rejected', async () => {
  const { host, guest, roomId } = await startedPair();
  const { client } = await onTurn([host, guest], roomId);
  const waiting = client === host ? guest : host;
  const waitingView = await viewFor(waiting, roomId);

  const play = await waiting.post(`/room/${roomId}/play`, { card: waitingView.game.yourHand[0] });
  assert.equal(play.status, 403);
  assert.equal(play.body.error, 'NOT_YOUR_TURN');

  const pass = await waiting.post(`/room/${roomId}/pass`);
  assert.equal(pass.status, 403);
  assert.equal(pass.body.error, 'NOT_YOUR_TURN');
});

test('passing with a legal move in hand is refused', async () => {
  const { host, guest, roomId } = await startedPair();
  const { client } = await onTurn([host, guest], roomId);

  const res = await client.post(`/room/${roomId}/pass`);
  assert.equal(res.status, 400);
  assert.equal(res.body.error, 'MUST_PLAY');
  assert.match(res.body.message, /card you can play/i);
});

test('a move applies immediately in its own response, no polling needed', async () => {
  const { host, guest, roomId } = await startedPair();
  const { client, view } = await onTurn([host, guest], roomId);
  const before = view.version;

  const res = await client.post(`/room/${roomId}/play`, { card: 'D7' });
  assert.equal(res.status, 200);
  const room = res.body.room;
  assert.ok(room.version > before);
  assert.equal(room.game.table.D.low, 7);
  assert.equal(room.game.table.D.high, 7);
  assert.equal(room.game.yourHand.length, 25);
  assert.notEqual(room.game.currentTurnSeat, view.yourSeat);
  assert.equal(room.game.lastAction.type, 'play');
  assert.equal(room.game.lastAction.auto, false);
});

test('the state a player receives never contains another hand', async () => {
  const { host, guest, roomId } = await startedPair();
  const view = await viewFor(host, roomId);
  const serialised = JSON.stringify(view);
  assert.ok(!serialised.includes('"hands"'));
  const guestView = await viewFor(guest, roomId);
  assert.equal(view.game.yourHand.length + guestView.game.yourHand.length, 52);
  for (const card of view.game.yourHand) {
    assert.ok(!guestView.game.yourHand.includes(card));
  }
});

test('two players can finish a whole round through the API', async () => {
  const { host, guest, roomId } = await startedPair();
  let moves = 0;
  let finalRoom = null;

  for (let guard = 0; guard < 200; guard += 1) {
    const { client, view } = await onTurn([host, guest], roomId);
    const legal = view.game.yourLegalMoves;
    const res = legal.length
      ? await client.post(`/room/${roomId}/play`, { card: legal[0] })
      : await client.post(`/room/${roomId}/pass`);
    assert.equal(res.status, 200, JSON.stringify(res.body));
    moves += 1;
    if (res.body.room.status === 'finished') {
      finalRoom = res.body.room;
      break;
    }
  }

  assert.ok(finalRoom, `round did not finish in ${moves} moves`);
  assert.equal(finalRoom.game.status, 'finished');
  assert.ok(finalRoom.game.winnerSeat === 0 || finalRoom.game.winnerSeat === 1);
  const counts = finalRoom.game.handCounts;
  assert.equal(counts[finalRoom.game.winnerSeat], 0);
  assert.equal(finalRoom.result.standings.length, 2);
  assert.equal(finalRoom.result.pool, 0);

  // Nobody can keep playing after the match is over.
  const after = await host.post(`/room/${roomId}/play`, { card: 'D7' });
  assert.equal(after.status, 400);
  assert.ok(['NOT_STARTED', 'ROUND_NOT_ACTIVE'].includes(after.body.error));
});

/* ------------------------------------------------------------- turn timer */

test('an expired turn is auto played by the server', async () => {
  const { host, guest, roomId } = await startedPair({ timerSeconds: 15 });
  const before = await onTurn([host, guest], roomId);
  const state = (await rooms.requireRoom(roomId)).gameState;
  const expiredAt = state.turnStartedAt + state.timerSeconds * 1000 + 1;

  await rooms.tickRoom(roomId, expiredAt);

  const after = await viewFor(before.client, roomId);
  assert.equal(after.game.lastAction.type, 'play');
  assert.equal(after.game.lastAction.auto, true);
  assert.equal(after.game.lastAction.seatIndex, before.view.yourSeat);
  assert.equal(after.game.handCounts[before.view.yourSeat], 25);
  assert.equal(rules.tableCardCount(after.game.table), 1);
  assert.notEqual(after.game.currentTurnSeat, before.view.yourSeat);

  const notice = after.notices.find((entry) => entry.kind === 'timeout_play');
  assert.ok(notice, 'a timeout notice should be visible to both seats');
  assert.match(notice.text, /ran out of time\. Auto played /);
});

test('an expired turn with nothing playable is auto passed', async () => {
  const { host, guest, roomId } = await startedPair({ timerSeconds: 15 });
  const room = await rooms.requireRoom(roomId);
  const state = room.gameState;
  const seat = state.currentTurnSeat;

  // Only the diamond seven is down, and this seat holds two cards that touch
  // neither end of it, so there is genuinely no legal move.
  state.table = rules.applyMove(rules.createTable(), 'D7');
  state.hands[seat] = ['H1', 'S13'];
  const expiredAt = state.turnStartedAt + state.timerSeconds * 1000 + 1;

  await rooms.tickRoom(roomId, expiredAt);

  const view = await viewFor(host, roomId);
  assert.equal(view.game.lastAction.type, 'pass');
  assert.equal(view.game.lastAction.auto, true);
  assert.equal(view.game.lastAction.seatIndex, seat);
  assert.equal(view.game.handCounts[seat], 2, 'an auto pass never removes a card');
  assert.notEqual(view.game.currentTurnSeat, seat);

  const notice = view.notices.find((entry) => entry.kind === 'timeout_pass');
  assert.ok(notice);
  assert.match(notice.text, /nothing to play/i);
  const guestView = await viewFor(guest, roomId);
  assert.ok(guestView.notices.some((entry) => entry.kind === 'timeout_pass'));
});

test('the countdown the client draws comes from the server clock', async () => {
  const { host, guest, roomId } = await startedPair({ timerSeconds: 20 });
  const view = await viewFor(host, roomId);
  assert.equal(view.game.timerSeconds, 20);
  assert.ok(view.game.millisLeft > 15_000 && view.game.millisLeft <= 20_000);
  assert.ok(Math.abs(view.serverTime - Date.now()) < 5_000);
  const other = await viewFor(guest, roomId);
  assert.equal(other.game.turnStartedAt, view.game.turnStartedAt);
});

/* --------------------------------------------------------------- long poll */

test('a poll behind the current version answers at once', async () => {
  const { host, roomId } = await startedPair();
  const started = Date.now();
  const res = await host.get(`/room/${roomId}/state?since=0`);
  assert.equal(res.status, 200);
  assert.equal(res.body.changed, true);
  assert.ok(res.body.room.version > 0);
  assert.ok(Date.now() - started < 500);
});

test('a poll at the current version parks until the window closes', async () => {
  const { host, roomId } = await startedPair();
  const view = await viewFor(host, roomId);
  const started = Date.now();
  const res = await host.get(`/room/${roomId}/state?since=${view.version}`);
  const elapsed = Date.now() - started;

  assert.equal(res.status, 200);
  assert.equal(res.body.changed, false);
  assert.equal(res.body.version, view.version);
  assert.ok(elapsed >= config.pollTimeoutMs - 200, `returned after ${elapsed}ms`);
});

test('a parked poll wakes as soon as the other player moves', async () => {
  const { host, guest, roomId } = await startedPair();
  const { client: mover } = await onTurn([host, guest], roomId);
  const waiter = mover === host ? guest : host;
  const view = await viewFor(waiter, roomId);

  const started = Date.now();
  const polling = waiter.get(`/room/${roomId}/state?since=${view.version}`);
  await new Promise((resolve) => setTimeout(resolve, 60));
  const played = await mover.post(`/room/${roomId}/play`, { card: 'D7' });
  assert.equal(played.status, 200);

  const res = await polling;
  const elapsed = Date.now() - started;
  assert.equal(res.status, 200);
  assert.equal(res.body.changed, true);
  assert.equal(res.body.room.game.table.D.low, 7);
  assert.ok(elapsed < config.pollTimeoutMs, `poll should wake early, took ${elapsed}ms`);
});

test('a bad since value is refused instead of being guessed at', async () => {
  const { host, roomId } = await startedPair();
  const res = await host.get(`/room/${roomId}/state?since=abc`);
  assert.equal(res.status, 400);
  assert.equal(res.body.error, 'BAD_REQUEST');
});

/* -------------------------------------------------------------------- bots */

test('bots fill empty seats and play by themselves', async () => {
  const host = await server.player('Asha');
  const room = await createRoom(host, { playerCount: 4, fillWithBots: true, botDifficulty: 'hard' });
  const started = await host.post(`/room/${room.roomId}/start`);
  assert.equal(started.status, 200);
  assert.equal(started.body.room.players.filter((player) => player.isBot).length, 3);

  const result = await harness.fastForward(room.roomId);
  assert.ok(result.finished, 'the bot table should finish on its own');

  const view = await viewFor(host, room.roomId);
  assert.equal(view.status, 'finished');
  assert.equal(view.game.handCounts[view.game.winnerSeat], 0);
  assert.equal(view.game.handCounts.reduce((a, b) => a + b, 0) + rules.tableCardCount(view.game.table), 52);
});

test('a bot seat cannot be handed to another bot, and nobody can play its cards', async () => {
  const host = await server.player('Asha');
  const room = await createRoom(host, { playerCount: 2 });
  const bot = await host.post(`/room/${room.roomId}/bot`, { difficulty: 'easy' });
  assert.equal(bot.status, 200);
  const started = await host.post(`/room/${room.roomId}/start`);
  assert.equal(started.status, 200);

  const botSeat = started.body.room.players.find((player) => player.isBot).seatIndex;
  const takeover = await host.post(`/room/${room.roomId}/bot-takeover`, { seatIndex: botSeat });
  assert.equal(takeover.status, 400);
  assert.match(takeover.body.message, /already a bot/i);

  // If the bot is on turn, the human cannot move for it.
  const view = await viewFor(host, room.roomId);
  if (view.game.currentTurnSeat === botSeat) {
    const res = await host.post(`/room/${room.roomId}/play`, { card: 'D7' });
    assert.equal(res.status, 403);
    assert.equal(res.body.error, 'NOT_YOUR_TURN');
  }
});

test('a seat that walks out keeps playing on the timer and can be given to a bot', async () => {
  const { host, guest, roomId } = await startedPair();
  const left = await guest.post(`/room/${roomId}/leave`);
  assert.equal(left.status, 200);

  const view = await viewFor(host, roomId);
  const guestSeat = view.players.find((player) => player.userId === guest.userId);
  assert.equal(guestSeat.connected, false);
  assert.ok(view.notices.some((entry) => entry.kind === 'away'));

  const takeover = await host.post(`/room/${roomId}/bot-takeover`, {
    seatIndex: guestSeat.seatIndex,
    difficulty: 'medium',
  });
  assert.equal(takeover.status, 200);
  const seatNow = takeover.body.room.players.find((player) => player.seatIndex === guestSeat.seatIndex);
  assert.equal(seatNow.isBot, true);
  assert.match(seatNow.name, /\(bot\)$/);

  const result = await harness.fastForward(roomId);
  assert.ok(result.finished);
});

test('a connected seat cannot be handed to a bot', async () => {
  const { host, guest, roomId } = await startedPair();
  const view = await viewFor(guest, roomId);
  const res = await host.post(`/room/${roomId}/bot-takeover`, { seatIndex: view.yourSeat });
  assert.equal(res.status, 403);
  assert.match(res.body.message, /still connected/i);
});

/* ------------------------------------------------------------- rate limits */

test('a hammered endpoint is rate limited with a retry hint', async () => {
  rateLimit.resetAll();
  const player = await server.player('Asha');
  let limited = null;

  for (let i = 0; i < 12 && !limited; i += 1) {
    const res = await player.post('/room/create', { settings: { playerCount: 2 } });
    if (res.status === 429) limited = res;
  }

  assert.ok(limited, 'creating rooms in a tight loop should be limited');
  assert.equal(limited.body.error, 'RATE_LIMITED');
  assert.ok(Number(limited.headers.get('retry-after')) >= 1);
  rateLimit.resetAll();
});
