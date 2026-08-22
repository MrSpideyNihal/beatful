'use strict';

/**
 * One error shape for the whole API:
 *   { "error": "NOT_YOUR_TURN", "message": "It is not your turn yet." }
 *
 * Codes are stable strings the client switches on. Messages are safe to show to
 * a player as is. A stack trace or a raw driver error never reaches a response.
 */

const STATUS_BY_CODE = {
  BAD_REQUEST: 400,
  BAD_CARD: 400,
  BAD_SEAT: 400,
  BAD_SEAT_COUNT: 400,
  BAD_TIMER: 400,
  BAD_ROOM_CODE: 400,
  NAME_INVALID: 400,
  SETTINGS_INVALID: 400,
  ILLEGAL_MOVE: 400,
  MUST_PLAY: 400,
  CARD_NOT_IN_HAND: 400,
  ROUND_NOT_ACTIVE: 400,
  ROUND_NOT_OVER: 400,
  NOT_ENOUGH_PLAYERS: 400,
  ALREADY_STARTED: 400,
  NOT_STARTED: 400,
  ALREADY_OWNED: 400,
  UNAUTHORIZED: 401,
  TOKEN_INVALID: 401,
  NOT_HOST: 403,
  NOT_IN_ROOM: 403,
  NOT_YOUR_TURN: 403,
  ROOM_LOCKED: 403,
  FORBIDDEN: 403,
  NOT_FOUND: 404,
  ROOM_NOT_FOUND: 404,
  USER_NOT_FOUND: 404,
  ITEM_NOT_FOUND: 404,
  ROOM_FULL: 409,
  SEAT_TAKEN: 409,
  CONFLICT: 409,
  INSUFFICIENT_COINS: 409,
  DAILY_AD_LIMIT: 429,
  RATE_LIMITED: 429,
  SERVER_ERROR: 500,
  DB_UNAVAILABLE: 503,
};

const MESSAGE_BY_CODE = {
  BAD_REQUEST: 'That request was not understood.',
  BAD_CARD: 'That is not a valid card.',
  BAD_SEAT: 'That seat does not exist.',
  BAD_ROOM_CODE: 'Room codes are 6 letters and numbers.',
  NAME_INVALID: 'Names are 2 to 16 characters, letters, numbers, spaces.',
  SETTINGS_INVALID: 'Those game settings are out of range.',
  ILLEGAL_MOVE: 'That card cannot be played yet.',
  MUST_PLAY: 'You still have a card you can play.',
  CARD_NOT_IN_HAND: 'You do not hold that card.',
  ROUND_NOT_ACTIVE: 'This round is not taking moves right now.',
  ROUND_NOT_OVER: 'The round is still being played.',
  NOT_ENOUGH_PLAYERS: 'You need at least 2 players to start.',
  ALREADY_STARTED: 'That game has already started.',
  NOT_STARTED: 'That game has not started yet.',
  ALREADY_OWNED: 'You already own that item.',
  UNAUTHORIZED: 'Please restart the app to sign in again.',
  TOKEN_INVALID: 'Your session expired. Restart the app.',
  NOT_HOST: 'Only the host can do that.',
  NOT_IN_ROOM: 'You are not in that room.',
  NOT_YOUR_TURN: 'It is not your turn yet.',
  ROOM_LOCKED: 'The host locked this room.',
  FORBIDDEN: 'You cannot do that.',
  NOT_FOUND: 'Not found.',
  ROOM_NOT_FOUND: 'No room with that code. Check the code and try again.',
  USER_NOT_FOUND: 'That player was not found.',
  ITEM_NOT_FOUND: 'That shop item is not available.',
  ROOM_FULL: 'That room is full.',
  SEAT_TAKEN: 'That seat was just taken.',
  CONFLICT: 'Something changed. Try that again.',
  INSUFFICIENT_COINS: 'You do not have enough coins.',
  DAILY_AD_LIMIT: 'You have collected all of today rewards. Come back tomorrow.',
  RATE_LIMITED: 'Slow down a moment, then try again.',
  SERVER_ERROR: 'Something went wrong on our side. Try again.',
  DB_UNAVAILABLE: 'The server is still waking up. Try again in a moment.',
};

class ApiError extends Error {
  constructor(code, message, details) {
    super(message || MESSAGE_BY_CODE[code] || code);
    this.name = 'ApiError';
    this.code = STATUS_BY_CODE[code] ? code : 'SERVER_ERROR';
    this.status = STATUS_BY_CODE[this.code] || 500;
    this.expose = true;
    if (details) this.details = details;
  }
}

function apiError(code, message, details) {
  return new ApiError(code, message, details);
}

/** Map any thrown value onto the wire shape. Unknown errors become 500s. */
function toResponse(err) {
  if (err instanceof ApiError) {
    const body = { error: err.code, message: err.message };
    if (err.details) body.details = err.details;
    return { status: err.status, body };
  }
  // GameError from the rules engine carries the same code vocabulary.
  if (err && err.name === 'GameError' && STATUS_BY_CODE[err.code]) {
    return {
      status: STATUS_BY_CODE[err.code],
      body: { error: err.code, message: MESSAGE_BY_CODE[err.code] || err.message },
    };
  }
  return {
    status: 500,
    body: { error: 'SERVER_ERROR', message: MESSAGE_BY_CODE.SERVER_ERROR },
  };
}

module.exports = { ApiError, apiError, toResponse, STATUS_BY_CODE, MESSAGE_BY_CODE };
