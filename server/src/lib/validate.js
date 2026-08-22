'use strict';

/**
 * Input validation. Every route runs its payload through here before any game
 * logic or database call sees it. Failures throw ApiError, so the client always
 * gets a coded, human readable reason rather than a crash further in.
 */

const { apiError } = require('./errors');
const config = require('../config');
const { normaliseRoomCode, isValidRoomCode } = require('./roomCode');
const { isCard } = require('../game/cards');
const { DIFFICULTIES } = require('../game/bots');

const NAME_PATTERN = /^[\p{L}\p{N} ._-]{2,16}$/u;
const GUEST_ID_PATTERN = /^[A-Za-z0-9-]{8,64}$/;
const ID_PATTERN = /^[A-Za-z0-9-]{6,64}$/;
const ITEM_ID_PATTERN = /^[A-Za-z0-9_-]{2,48}$/;

function requireObject(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw apiError('BAD_REQUEST', 'Expected a JSON object.');
  }
  return body;
}

function guestId(value) {
  if (typeof value !== 'string' || !GUEST_ID_PATTERN.test(value)) {
    throw apiError('BAD_REQUEST', 'Missing or malformed device id.');
  }
  return value;
}

function identifier(value, label = 'id') {
  if (typeof value !== 'string' || !ID_PATTERN.test(value)) {
    throw apiError('BAD_REQUEST', `Malformed ${label}.`);
  }
  return value;
}

/**
 * Shop item ids are catalog keys, not generated ids, so they have their own
 * shape. Anything that could not name an item reads as a missing item, which is
 * what the client already knows how to show.
 */
function itemId(value) {
  if (typeof value !== 'string' || !ITEM_ID_PATTERN.test(value)) {
    throw apiError('ITEM_NOT_FOUND');
  }
  return value;
}

/** Trims, collapses runs of spaces, then checks length and character set. */
function displayName(value) {
  if (typeof value !== 'string') throw apiError('NAME_INVALID');
  const cleaned = value.trim().replace(/\s+/g, ' ');
  if (!NAME_PATTERN.test(cleaned)) throw apiError('NAME_INVALID');
  return cleaned;
}

function optionalDisplayName(value, fallback) {
  if (value === undefined || value === null || value === '') return fallback;
  return displayName(value);
}

function roomCode(value) {
  const code = normaliseRoomCode(value);
  if (!isValidRoomCode(code)) throw apiError('BAD_ROOM_CODE');
  return code;
}

function card(value) {
  if (!isCard(value)) throw apiError('BAD_CARD');
  return value;
}

function seatIndex(value) {
  const seat = Number(value);
  if (!Number.isInteger(seat) || seat < 0 || seat >= config.maxPlayers) {
    throw apiError('BAD_SEAT');
  }
  return seat;
}

function avatarId(value, fallback = 0) {
  if (value === undefined || value === null || value === '') return fallback;
  const id = Number(value);
  if (!Number.isInteger(id) || id < 0 || id > 11) {
    throw apiError('BAD_REQUEST', 'Unknown avatar.');
  }
  return id;
}

function difficulty(value, fallback = 'medium') {
  if (value === undefined || value === null || value === '') return fallback;
  if (!DIFFICULTIES.includes(value)) {
    throw apiError('BAD_REQUEST', 'Unknown bot difficulty.');
  }
  return value;
}

function boundedInt(value, { min, max, fallback, label }) {
  if (value === undefined || value === null || value === '') return fallback;
  const num = Number(value);
  if (!Number.isInteger(num) || num < min || num > max) {
    throw apiError('SETTINGS_INVALID', `${label} must be a whole number from ${min} to ${max}.`);
  }
  return num;
}

/**
 * Room settings, used for both create and update. Only keys present in the
 * payload are returned, so a partial update leaves the rest alone.
 */
function roomSettings(body, { partial = false, current = {} } = {}) {
  requireObject(body);
  const out = {};
  const has = (key) => Object.prototype.hasOwnProperty.call(body, key) && body[key] !== undefined;

  if (!partial || has('playerCount')) {
    out.playerCount = boundedInt(body.playerCount, {
      min: config.minPlayers,
      max: config.maxPlayers,
      fallback: current.playerCount ?? 4,
      label: 'Number of players',
    });
  }
  if (!partial || has('timerSeconds')) {
    out.timerSeconds = boundedInt(body.timerSeconds, {
      min: config.minTimerSeconds,
      max: config.maxTimerSeconds,
      fallback: current.timerSeconds ?? config.defaultTimerSeconds,
      label: 'Turn timer',
    });
  }
  if (!partial || has('rounds')) {
    out.rounds = boundedInt(body.rounds, {
      min: 1,
      max: config.maxRounds,
      fallback: current.rounds ?? 1,
      label: 'Rounds',
    });
  }
  if (!partial || has('coinMatch')) {
    out.coinMatch = Boolean(has('coinMatch') ? body.coinMatch : current.coinMatch);
  }
  if (!partial || has('entryFee')) {
    out.entryFee = boundedInt(body.entryFee, {
      min: 0,
      max: config.maxEntryFee,
      fallback: current.entryFee ?? 0,
      label: 'Entry fee',
    });
  }
  if (!partial || has('shuffleSeats')) {
    out.shuffleSeats = Boolean(has('shuffleSeats') ? body.shuffleSeats : current.shuffleSeats);
  }
  if (!partial || has('payout')) {
    const payout = has('payout') ? body.payout : current.payout ?? 'winner_takes_all';
    if (!['winner_takes_all', 'ranked_split'].includes(payout)) {
      throw apiError('SETTINGS_INVALID', 'Unknown payout mode.');
    }
    out.payout = payout;
  }
  if (!partial || has('fillWithBots')) {
    out.fillWithBots = Boolean(has('fillWithBots') ? body.fillWithBots : current.fillWithBots);
  }
  if (!partial || has('botDifficulty')) {
    out.botDifficulty = difficulty(body.botDifficulty, current.botDifficulty ?? 'medium');
  }

  const merged = { ...current, ...out };
  if (merged.coinMatch && merged.entryFee <= 0) {
    throw apiError('SETTINGS_INVALID', 'A coin match needs an entry fee above zero.');
  }
  return out;
}

function sinceVersion(value) {
  if (value === undefined || value === null || value === '') return 0;
  const num = Number(value);
  if (!Number.isFinite(num) || num < 0 || num > Number.MAX_SAFE_INTEGER) {
    throw apiError('BAD_REQUEST', 'Bad state version.');
  }
  return Math.floor(num);
}

module.exports = {
  requireObject,
  guestId,
  identifier,
  itemId,
  displayName,
  optionalDisplayName,
  roomCode,
  card,
  seatIndex,
  avatarId,
  difficulty,
  boundedInt,
  roomSettings,
  sinceVersion,
};
