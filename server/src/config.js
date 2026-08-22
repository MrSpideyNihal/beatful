'use strict';

require('dotenv').config();

/**
 * Configuration is read once at boot and validated here so the process fails
 * fast with a clear message instead of half starting and throwing later.
 *
 * MONGO_URI never appears in client code and never gets logged.
 */

function readInt(name, fallback, min, max) {
  const raw = process.env[name];
  if (raw === undefined || raw === '') return fallback;
  const value = Number(raw);
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new Error(`${name} must be an integer between ${min} and ${max}`);
  }
  return value;
}

function readBool(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === '') return fallback;
  return raw === '1' || raw.toLowerCase() === 'true';
}

const nodeEnv = process.env.NODE_ENV || 'development';
const useMemoryDb = readBool('USE_MEMORY_DB', false);
const mongoUri = process.env.MONGO_URI || '';

if (!useMemoryDb && !mongoUri && nodeEnv === 'production') {
  throw new Error('MONGO_URI is required in production. Set it in the host environment, never in code.');
}

const authSecret = process.env.AUTH_SECRET || (nodeEnv === 'production' ? '' : 'dev-only-insecure-secret');
if (!authSecret) {
  throw new Error('AUTH_SECRET is required in production');
}

const config = {
  nodeEnv,
  isProduction: nodeEnv === 'production',
  port: readInt('PORT', 3000, 1, 65535),
  mongoUri,
  mongoDbName: process.env.MONGO_DB_NAME || 'beatful',
  useMemoryDb: useMemoryDb || (!mongoUri && nodeEnv !== 'production'),
  authSecret,
  tokenTtlDays: readInt('TOKEN_TTL_DAYS', 365, 1, 3650),

  // Long polling. Kept under the 30s that most free tier proxies allow.
  pollTimeoutMs: readInt('POLL_TIMEOUT_MS', 25000, 1000, 55000),

  // Room lifecycle.
  roomTtlHours: readInt('ROOM_TTL_HOURS', 6, 1, 72),
  matchTtlDays: readInt('MATCH_TTL_DAYS', 60, 1, 400),
  disconnectGraceMs: readInt('DISCONNECT_GRACE_MS', 60000, 5000, 600000),
  lobbyIdleTimeoutMs: readInt('LOBBY_IDLE_TIMEOUT_MS', 1800000, 60000, 21600000),

  // Game defaults, all overridable by the host inside these bounds.
  defaultTimerSeconds: readInt('DEFAULT_TIMER_SECONDS', 15, 5, 120),
  minTimerSeconds: 5,
  maxTimerSeconds: 120,
  minPlayers: 2,
  maxPlayers: 8,
  maxRounds: 10,

  // Economy.
  startingCoins: readInt('STARTING_COINS', 500, 0, 100000),
  maxEntryFee: readInt('MAX_ENTRY_FEE', 5000, 1, 1000000),
  adRewardCoins: readInt('AD_REWARD_COINS', 25, 1, 1000),
  adRewardDailyCap: readInt('AD_REWARD_DAILY_CAP', 5, 1, 100),

  // Turn timer sweep interval.
  turnSweepMs: readInt('TURN_SWEEP_MS', 500, 100, 5000),
};

module.exports = config;
