'use strict';

/**
 * Process entry point.
 *
 * Order matters: config validates itself on require, the store connects before
 * the first request can arrive, and the turn loop only starts once the store is
 * ready so a sweep can never run against a missing database.
 */

const config = require('./config');
const log = require('./lib/log');
const { createApp } = require('./app');
const { initStore, closeStore } = require('./db');
const turnLoop = require('./turnLoop');
const watch = require('./realtime/watch');

let server = null;
let shuttingDown = false;

async function main() {
  await initStore();
  const app = createApp();

  server = app.listen(config.port, () => {
    log.info('beatful server listening', {
      port: config.port,
      env: config.nodeEnv,
      store: config.useMemoryDb ? 'memory' : 'mongo',
    });
  });

  // Long polling parks requests for up to pollTimeoutMs, so the socket timeouts
  // have to sit comfortably above that or Node would cut the wait short.
  server.keepAliveTimeout = config.pollTimeoutMs + 10_000;
  server.headersTimeout = config.pollTimeoutMs + 15_000;
  server.requestTimeout = 0;

  server.on('error', (err) => {
    log.error('http server error', { err });
    if (err && err.code === 'EADDRINUSE') process.exit(1);
  });

  turnLoop.start();
}

async function shutdown(reason, exitCode) {
  if (shuttingDown) return;
  shuttingDown = true;
  log.info('shutting down', { reason });

  turnLoop.stop();
  watch.releaseAll(); // Answer every parked poll instead of leaving clients hanging.

  const closeHttp = new Promise((resolve) => {
    if (!server) {
      resolve();
      return;
    }
    server.close(() => resolve());
  });

  // Never let a stuck socket or a slow database hold the process open forever.
  const deadline = new Promise((resolve) => {
    const timer = setTimeout(resolve, 8000);
    if (timer.unref) timer.unref();
  });

  await Promise.race([closeHttp, deadline]);
  try {
    await closeStore();
  } catch (err) {
    log.error('failed to close the store cleanly', { err });
  }
  process.exit(exitCode);
}

/**
 * Process level safety net, required by the spec: one bad request must never
 * take the whole server down for every other table. Anything that escapes the
 * route wrappers lands here, gets logged with context and is then ignored.
 */
process.on('unhandledRejection', (reason) => {
  log.error('unhandled promise rejection', { err: reason });
});

process.on('uncaughtException', (err) => {
  log.error('uncaught exception', { err });
});

process.on('SIGTERM', () => {
  shutdown('SIGTERM', 0);
});

process.on('SIGINT', () => {
  shutdown('SIGINT', 0);
});

main().catch((err) => {
  log.error('server failed to start', { err });
  process.exit(1);
});
