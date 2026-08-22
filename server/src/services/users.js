'use strict';

/**
 * Guest identity.
 *
 * First launch: the device generates a UUID, posts it once, and gets back a
 * user document plus a signed token. There is no email, no password and no
 * signup wall in front of any part of the game.
 */

const config = require('../config');
const { getStore } = require('../db');
const { apiError } = require('../lib/errors');
const { issueToken } = require('../lib/token');
const coins = require('./coins');

const ADJECTIVES = ['Bright', 'Happy', 'Calm', 'Swift', 'Kind', 'Lucky', 'Clever', 'Sunny'];
const ANIMALS = ['Tiger', 'Parrot', 'Panda', 'Falcon', 'Dolphin', 'Peacock', 'Otter', 'Deer'];

function suggestName(seedText) {
  let hash = 0;
  for (let i = 0; i < seedText.length; i += 1) {
    hash = (hash * 31 + seedText.charCodeAt(i)) & 0x7fffffff;
  }
  const adjective = ADJECTIVES[hash % ADJECTIVES.length];
  const animal = ANIMALS[Math.floor(hash / ADJECTIVES.length) % ANIMALS.length];
  return `${adjective} ${animal}`;
}

/** Everything the client is allowed to know about itself. */
function publicUser(user) {
  return {
    userId: user._id,
    displayName: user.displayName,
    avatarId: user.avatarId ?? 0,
    coins: user.coins,
    stats: user.stats || { wins: 0, matchesPlayed: 0, roundsPlayed: 0 },
    ownedItems: user.ownedItems || [],
    selected: user.selected || { cardBack: 'back_classic', table: 'table_green' },
    adRewards: user.adRewards || { day: null, count: 0 },
  };
}

async function initGuest(guestId, requestedName, avatarId) {
  const store = getStore();
  const { user, created } = await store.users.upsertGuest(guestId, {
    displayName: requestedName || suggestName(guestId),
    avatarId: avatarId ?? 0,
    coins: config.startingCoins,
  });
  if (!user) throw apiError('SERVER_ERROR');

  // A brand new account gets its welcome coins logged, so the ledger and the
  // balance agree from the very first row.
  if (created && config.startingCoins > 0) {
    await coins.recordTransaction({
      userId: user._id,
      type: coins.TYPES.SIGNUP_BONUS,
      amount: config.startingCoins,
      balanceAfter: user.coins,
    });
  }

  return { user: publicUser(user), token: issueToken(user._id), created };
}

async function getUser(userId) {
  const user = await getStore().users.findById(userId);
  if (!user) throw apiError('USER_NOT_FOUND');
  return user;
}

async function updateProfile(userId, patch) {
  const user = await getStore().users.setProfile(userId, patch);
  if (!user) throw apiError('USER_NOT_FOUND');
  return publicUser(user);
}

async function selectCosmetic(userId, kind, itemId) {
  const user = await getUser(userId);
  const owned = user.ownedItems || [];
  if (!owned.includes(itemId)) throw apiError('FORBIDDEN', 'You do not own that item yet.');
  const updated = await getStore().users.setSelected(userId, kind, itemId);
  return publicUser(updated);
}

module.exports = { initGuest, getUser, updateProfile, selectCosmetic, publicUser, suggestName };
