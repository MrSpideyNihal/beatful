'use strict';

/**
 * API test harness.
 *
 * Boots the real express app on an ephemeral port against the in memory store,
 * so these tests exercise routing, auth, validation, rate limiting and the room
 * service exactly as a device would. No database and no network is needed.
 *
 * Environment is set here, before anything under src/ is required, because
 * config reads it once at load time.
 */

process.env.NODE_ENV = 'test';
process.env.USE_MEMORY_DB = 'true';
process.env.AUTH_SECRET = 'test-only-secret';
process.env.LOG_LEVEL = process.env.LOG_LEVEL || 'silent';
process.env.POLL_TIMEOUT_MS = process.env.POLL_TIMEOUT_MS || '1000';
delete process.env.MONGO_URI;

const { once } = require('node:events');
const crypto = require('node:crypto');

const config = require('../../src/config');
const { createApp } = require('../../src/app');
const { initStore, getStore, closeStore, createMemoryStore } = require('../../src/db');
const rooms = require('../../src/services/rooms');
const users = require('../../src/services/users');
const engine = require('../../src/game/engine');
const rateLimit = require('../../src/middleware/rateLimit');
const watch = require('../../src/realtime/watch');

/** One HTTP client bound to a base url and, optionally, a guest token. */
function makeClient(base, token) {
  async function request(method, path, body) {
    const headers = {};
    if (token) headers.Authorization = `Bearer ${token}`;
    if (body !== undefined) headers['content-type'] = 'application/json';
    const response = await fetch(base + path, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    const text = await response.text();
    let parsed = null;
    if (text) {
      try {
        parsed = JSON.parse(text);
      } catch (err) {
        parsed = { raw: text };
      }
    }
    return { status: response.status, body: parsed, headers: response.headers };
  }

  return {
    token,
    base,
    request,
    get: (path) => request('GET', path),
    post: (path, body) => request('POST', path, body),
    patch: (path, body) => request('PATCH', path, body),
    withToken: (other) => makeClient(base, other),
  };
}

async function startTestServer() {
  await initStore(createMemoryStore());
  const app = createApp();
  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const base = `http://127.0.0.1:${server.address().port}`;

  return {
    base,
    server,
    anon: makeClient(base, null),

    /**
     * A ready to use player. Identity is created through the service rather than
     * the endpoint so bulk tests do not trip the init rate limit, which has its
     * own dedicated test.
     */
    async player(name) {
      const guestId = crypto.randomUUID();
      const created = await users.initGuest(guestId, name, 0);
      const client = makeClient(base, created.token);
      client.userId = created.user.userId;
      client.name = created.user.displayName;
      client.guestId = guestId;
      return client;
    },

    async close() {
      watch.releaseAll();
      rooms.resetCache();
      rateLimit.resetAll();
      await new Promise((resolve) => {
        server.close(() => resolve());
        // fetch keeps sockets alive, which would otherwise hold close() open.
        if (server.closeAllConnections) server.closeAllConnections();
      });
      await closeStore();
    },
  };
}

/**
 * Runs the room forward on a fake clock until it finishes, letting the server
 * turn timer resolve every seat. This is how a full match is played out in a
 * test without waiting real seconds.
 */
async function fastForward(roomId, { steps = 400, stepMs = null } = {}) {
  const jump = stepMs || (config.maxTimerSeconds + 1) * 1000;
  let now = Date.now();
  for (let i = 0; i < steps; i += 1) {
    now += jump;
    await rooms.tickRoom(roomId, now);
    const room = await rooms.requireRoom(roomId).catch(() => null);
    if (!room || room.status === 'finished') return { finished: true, steps: i + 1 };
  }
  return { finished: false, steps };
}

function coinsOf(user) {
  return user.coins;
}

module.exports = {
  startTestServer,
  makeClient,
  fastForward,
  coinsOf,
  config,
  rooms,
  users,
  engine,
  rateLimit,
  getStore,
};
