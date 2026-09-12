'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const harness = require('./helpers/api');
const cards = require('../src/game/cards');
const { rooms, rateLimit } = harness;

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

test('admin login succeeds with valid credentials and rejects wrong password', async () => {
  const client = server.anon;

  // Wrong password
  const bad = await client.post('/admin/login', {
    username: 'nihaldev',
    password: 'wrongpassword',
  });
  assert.equal(bad.status, 401);

  // Correct credentials
  const good = await client.post('/admin/login', {
    username: 'nihaldev',
    password: 'nihalisgret9322161961',
  });
  assert.equal(good.status, 200);
  assert.ok(good.body.token);
  assert.equal(good.body.user, 'nihaldev');
});

test('admin endpoints require admin bearer token', async () => {
  const client = server.anon;
  const res = await client.get('/admin/rooms');
  assert.equal(res.status, 401);
});

test('admin can list users and gift coins', async () => {
  const player = await server.player('TargetPlayer');
  const userBefore = await harness.users.getUser(player.userId);
  const initialCoins = userBefore.coins;

  // Login as admin
  const login = await server.anon.post('/admin/login', {
    username: 'nihaldev',
    password: 'nihalisgret9322161961',
  });
  const adminToken = login.body.token;
  const adminClient = server.anon.withToken(adminToken);

  // List users
  const usersRes = await adminClient.get('/admin/users');
  assert.equal(usersRes.status, 200);
  assert.ok(Array.isArray(usersRes.body.users));
  const foundUser = usersRes.body.users.find((u) => u.userId === player.userId);
  assert.ok(foundUser);

  // Gift coins
  const giftRes = await adminClient.post('/admin/coins/gift', {
    userId: player.userId,
    amount: 500,
  });
  assert.equal(giftRes.status, 200);
  assert.equal(giftRes.body.balanceAfter, initialCoins + 500);

  // Deduct coins
  const deductRes = await adminClient.post('/admin/coins/gift', {
    userId: player.userId,
    amount: -200,
  });
  assert.equal(deductRes.status, 200);
  assert.equal(deductRes.body.balanceAfter, initialCoins + 300);
});

test('admin can inspect rooms, modify seat scores, and curse a seat with high cards', async () => {
  const host = await server.player('HostPlayer');
  const create = await host.post('/room/create', {
    settings: { playerCount: 3, fillWithBots: true },
  });
  assert.equal(create.status, 201);
  const roomId = create.body.room.roomId;

  // Start match
  const start = await host.post(`/room/${roomId}/start`);
  assert.equal(start.status, 200);

  // Login as admin
  const login = await server.anon.post('/admin/login', {
    username: 'nihaldev',
    password: 'nihalisgret9322161961',
  });
  const adminToken = login.body.token;
  const adminClient = server.anon.withToken(adminToken);

  // List rooms
  const roomsRes = await adminClient.get('/admin/rooms');
  assert.equal(roomsRes.status, 200);
  const found = roomsRes.body.rooms.find((r) => r.roomId === roomId);
  assert.ok(found);

  // Alter score for seat 0
  const scoreRes = await adminClient.post(`/admin/room/${roomId}/score`, {
    seatIndex: 0,
    score: 99,
  });
  assert.equal(scoreRes.status, 200);
  assert.equal(scoreRes.body.score, 99);

  // Curse seat 1 with high cards
  const curseRes = await adminClient.post(`/admin/room/${roomId}/curse`, {
    seatIndex: 1,
  });
  assert.equal(curseRes.status, 200);
  assert.equal(curseRes.body.cursedSeat, 1);
});
