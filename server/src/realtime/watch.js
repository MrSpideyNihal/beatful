'use strict';

/**
 * Long polling wake ups.
 *
 * A client asks for room state with ?since=<version>. If the server already has
 * something newer it answers straight away. Otherwise it parks the request here
 * until the room version changes or the poll window closes.
 *
 * No sockets, no redis, no polling loop on the server: a room mutation calls
 * notify() and every parked request for that room resolves in the same tick.
 */

const watchers = new Map();

/**
 * Resolves true when the room changed, false when the wait timed out or the
 * client went away. Never rejects.
 */
function waitForChange(roomId, timeoutMs, signal) {
  return new Promise((resolve) => {
    if (signal && signal.aborted) {
      resolve(false);
      return;
    }
    const set = watchers.get(roomId) || new Set();
    const entry = { resolve: null, timer: null, onAbort: null };

    const settle = (changed) => {
      if (entry.resolve === null) return;
      const done = entry.resolve;
      entry.resolve = null;
      clearTimeout(entry.timer);
      if (signal && entry.onAbort) signal.removeEventListener('abort', entry.onAbort);
      set.delete(entry);
      if (set.size === 0) watchers.delete(roomId);
      done(changed);
    };

    entry.resolve = resolve;
    entry.settle = settle;
    entry.timer = setTimeout(() => settle(false), timeoutMs);
    if (signal) {
      entry.onAbort = () => settle(false);
      signal.addEventListener('abort', entry.onAbort, { once: true });
    }
    set.add(entry);
    watchers.set(roomId, set);
  });
}

/** Wake every request parked on this room. */
function notify(roomId) {
  const set = watchers.get(roomId);
  if (!set || set.size === 0) return 0;
  const entries = Array.from(set);
  for (const entry of entries) {
    if (entry.settle) entry.settle(true);
  }
  return entries.length;
}

function watcherCount(roomId) {
  if (roomId === undefined) {
    let total = 0;
    for (const set of watchers.values()) total += set.size;
    return total;
  }
  const set = watchers.get(roomId);
  return set ? set.size : 0;
}

/** Used on shutdown so parked requests do not hold the process open. */
function releaseAll() {
  for (const roomId of Array.from(watchers.keys())) notify(roomId);
}

module.exports = { waitForChange, notify, watcherCount, releaseAll };
