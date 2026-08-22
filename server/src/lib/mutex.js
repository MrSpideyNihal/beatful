'use strict';

/**
 * Per key async lock.
 *
 * Every mutation of a room runs inside withLock(roomId, ...). Node is single
 * threaded but an await inside a handler is a yield point, so two requests for
 * the same room could otherwise interleave a read and a write and lose a move.
 * The lock removes that whole class of bug.
 */

const chains = new Map();

function withLock(key, task) {
  const previous = chains.get(key) || Promise.resolve();
  const run = previous.then(() => task());
  // The queue itself never rejects, so one failed task cannot poison the lock
  // for every request behind it. The caller still sees the real rejection.
  const chain = run.then(
    () => {},
    () => {},
  );
  chains.set(key, chain);
  chain.then(() => {
    if (chains.get(key) === chain) chains.delete(key);
  });
  return run;
}

function pendingLockCount() {
  return chains.size;
}

module.exports = { withLock, pendingLockCount };
