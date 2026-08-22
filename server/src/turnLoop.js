'use strict';

/**
 * Server side turn loop.
 *
 * This is what makes the turn timer real: the countdown a player sees is only a
 * drawing of server state, and expiry is decided here from the server clock.
 * The same sweep drives bot turns, the pause between rounds and presence.
 *
 * A sweep is skipped while the previous one is still running, so a slow database
 * cannot pile ticks on top of each other.
 */

const config = require('./config');
const log = require('./lib/log');
const rooms = require('./services/rooms');

let timer = null;
let running = false;

async function sweepOnce(now = Date.now()) {
  const ids = rooms.liveRoomIds();
  for (const roomId of ids) {
    try {
      await rooms.tickRoom(roomId, now);
    } catch (err) {
      // One bad room must never stop the loop for every other table.
      log.error('turn sweep failed for room', { roomId, err });
    }
  }
  return ids.length;
}

function start() {
  if (timer) return;
  timer = setInterval(() => {
    if (running) return;
    running = true;
    sweepOnce()
      .catch((err) => log.error('turn sweep failed', { err }))
      .finally(() => {
        running = false;
      });
  }, config.turnSweepMs);
  if (timer.unref) timer.unref();
  log.info('turn loop started', { everyMs: config.turnSweepMs });
}

function stop() {
  if (!timer) return;
  clearInterval(timer);
  timer = null;
}

module.exports = { start, stop, sweepOnce };
