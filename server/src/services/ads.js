'use strict';

/**
 * Rewarded ad coins.
 *
 * The grant is capped per user per day in the database, not on the device, so
 * reinstalling the app or replaying an ad view cannot mint coins. The day key is
 * UTC, which keeps the reset time stable no matter where the player travels.
 */

const config = require('../config');
const { getStore } = require('../db');
const { apiError } = require('../lib/errors');
const coins = require('./coins');
const { publicUser } = require('./users');

function dayKey(now = new Date()) {
  return now.toISOString().slice(0, 10);
}

async function claimReward(userId) {
  const key = dayKey();
  const result = await getStore().users.claimAdReward(
    userId,
    key,
    config.adRewardDailyCap,
    config.adRewardCoins,
  );
  if (!result.ok) {
    if (result.reason === 'USER_NOT_FOUND') throw apiError('USER_NOT_FOUND');
    throw apiError('DAILY_AD_LIMIT');
  }
  await coins.recordTransaction({
    userId,
    type: coins.TYPES.AD_REWARD,
    amount: config.adRewardCoins,
    balanceAfter: result.user.coins,
  });
  return {
    granted: config.adRewardCoins,
    claimedToday: result.countToday,
    dailyCap: config.adRewardDailyCap,
    remainingToday: Math.max(0, config.adRewardDailyCap - result.countToday),
    user: publicUser(result.user),
  };
}

async function status(userId) {
  const user = await getStore().users.findById(userId);
  if (!user) throw apiError('USER_NOT_FOUND');
  const key = dayKey();
  const claimedToday = user.adRewards && user.adRewards.day === key ? user.adRewards.count : 0;
  return {
    claimedToday,
    dailyCap: config.adRewardDailyCap,
    remainingToday: Math.max(0, config.adRewardDailyCap - claimedToday),
    rewardCoins: config.adRewardCoins,
  };
}

module.exports = { claimReward, status, dayKey };
