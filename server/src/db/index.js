'use strict';

/**
 * Store selector. The rest of the server only ever talks to getStore(), so
 * swapping mongo for the in memory implementation (tests, offline dev) changes
 * nothing above this line.
 */

const config = require('../config');
const log = require('../lib/log');
const { createMemoryStore } = require('./memoryStore');
const { createMongoStore } = require('./mongoStore');

let store = null;

async function initStore(override) {
  if (store) return store;
  if (override) {
    store = override;
  } else if (config.useMemoryDb) {
    log.warn('using the in memory store, data is not persisted');
    store = createMemoryStore();
  } else {
    store = createMongoStore();
  }
  await store.init();
  return store;
}

function getStore() {
  if (!store) throw new Error('store used before initStore()');
  return store;
}

async function closeStore() {
  if (!store) return;
  await store.close();
  store = null;
}

module.exports = { initStore, getStore, closeStore, createMemoryStore, createMongoStore };
