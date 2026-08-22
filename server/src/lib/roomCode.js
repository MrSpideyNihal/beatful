'use strict';

const crypto = require('node:crypto');

/**
 * Room codes.
 *
 * The alphabet leaves out O, 0, I, 1 and L so a code read out loud or squinted
 * at on a phone screen cannot be typed in wrong. Codes are compared and stored
 * upper case, and input is normalised before lookup.
 */

const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const CODE_LENGTH = 6;
const CODE_PATTERN = new RegExp(`^[${ALPHABET}]{${CODE_LENGTH}}$`);

function generateRoomCode() {
  const bytes = crypto.randomBytes(CODE_LENGTH * 2);
  let code = '';
  for (let i = 0; code.length < CODE_LENGTH; i += 1) {
    code += ALPHABET[bytes[i % bytes.length] % ALPHABET.length];
  }
  return code;
}

/** Uppercases and strips spaces and dashes people type out of habit. */
function normaliseRoomCode(input) {
  if (typeof input !== 'string') return '';
  return input.toUpperCase().replace(/[^A-Z0-9]/g, '');
}

function isValidRoomCode(input) {
  return CODE_PATTERN.test(input);
}

function deepLinkFor(code) {
  return `beatful://join/${code}`;
}

module.exports = {
  ALPHABET,
  CODE_LENGTH,
  generateRoomCode,
  normaliseRoomCode,
  isValidRoomCode,
  deepLinkFor,
};
