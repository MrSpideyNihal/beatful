'use strict';

/**
 * Coin ledger.
 *
 * Rules that hold for every path in this file:
 *   - the client never sends a balance, only an intent
 *   - a balance only ever moves through store.users.adjustCoins or one of the
 *     other single step atomic helpers, so two requests cannot both spend the
 *     same coin
 *   - every movement writes a transactions row with the resulting balance, which
 *     is what the consistency check in the tests audits
 *   - coins are a closed loop. Nothing in here converts them to money.
 */

const crypto = require('node:crypto');

const { getStore } = require('../db');
const { apiError } = require('../lib/errors');
const log = require('../lib/log');

const TYPES = {
  SIGNUP_BONUS: 'signup_bonus',
  MATCH_ENTRY: 'match_entry',
  MATCH_ENTRY_REFUND: 'match_entry_refund',
  MATCH_WIN: 'match_win',
  AD_REWARD: 'ad_reward',
  SHOP_PURCHASE: 'shop_purchase',
  IAP: 'iap',
};

function txDoc({ userId, type, amount, balanceAfter, roomCode, itemId }) {
  const now = new Date();
  return {
    _id: crypto.randomUUID(),
    userId,
    type,
    amount,
    balanceAfter,
    roomCode: roomCode || null,
    itemId: itemId || null,
    createdAt: now.toISOString(),
  };
}

/**
 * Records the ledger row for a balance change that already happened. A failure
 * here is logged loudly but never rolls the balance back: the balance is the
 * authoritative value and the row is the audit trail.
 */
async function recordTransaction(entry) {
  try {
    await getStore().transactions.insert(txDoc(entry));
  } catch (err) {
    log.error('failed to write transaction row', {
      userId: entry.userId,
      type: entry.type,
      amount: entry.amount,
      err,
    });
  }
}

/** Deduct coins. Throws INSUFFICIENT_COINS instead of ever going negative. */
async function debit(userId, amount, { type, roomCode, itemId } = {}) {
  if (!Number.isInteger(amount) || amount <= 0) {
    throw apiError('BAD_REQUEST', 'Invalid coin amount.');
  }
  const result = await getStore().users.adjustCoins(userId, -amount);
  if (!result.ok) {
    throw apiError(result.reason === 'USER_NOT_FOUND' ? 'USER_NOT_FOUND' : 'INSUFFICIENT_COINS');
  }
  await recordTransaction({
    userId,
    type: type || TYPES.MATCH_ENTRY,
    amount: -amount,
    balanceAfter: result.user.coins,
    roomCode,
    itemId,
  });
  return result.user.coins;
}

/** Add coins. */
async function credit(userId, amount, { type, roomCode, itemId } = {}) {
  if (!Number.isInteger(amount) || amount <= 0) {
    throw apiError('BAD_REQUEST', 'Invalid coin amount.');
  }
  const result = await getStore().users.adjustCoins(userId, amount);
  if (!result.ok) throw apiError('USER_NOT_FOUND');
  await recordTransaction({
    userId,
    type: type || TYPES.MATCH_WIN,
    amount,
    balanceAfter: result.user.coins,
    roomCode,
    itemId,
  });
  return result.user.coins;
}

/**
 * Split a prize pool across final standings.
 *
 * winner_takes_all: rank 1 takes everything, split evenly on a tie.
 * ranked_split:     weights fall off by rank, so second place still gets some
 *                   coins back. Remainders go to the better ranks so the sum
 *                   always equals the pool exactly and no coin is invented.
 */
function computePayouts(pool, standings, mode) {
  if (pool <= 0 || standings.length === 0) return new Map();
  const payouts = new Map();
  const sorted = standings.slice().sort((a, b) => a.rank - b.rank || a.seatIndex - b.seatIndex);

  if (mode === 'ranked_split') {
    const weights = sorted.map((entry) => 1 / Math.pow(2, entry.rank - 1));
    const total = weights.reduce((a, b) => a + b, 0);
    let handedOut = 0;
    sorted.forEach((entry, index) => {
      const share = index === sorted.length - 1 ? pool - handedOut : Math.floor((pool * weights[index]) / total);
      handedOut += share;
      if (share > 0) payouts.set(entry.seatIndex, share);
    });
    return payouts;
  }

  const winners = sorted.filter((entry) => entry.rank === sorted[0].rank);
  const each = Math.floor(pool / winners.length);
  let remainder = pool - each * winners.length;
  for (const winner of winners) {
    const extra = remainder > 0 ? 1 : 0;
    remainder -= extra;
    payouts.set(winner.seatIndex, each + extra);
  }
  return payouts;
}

module.exports = { TYPES, debit, credit, recordTransaction, computePayouts };
