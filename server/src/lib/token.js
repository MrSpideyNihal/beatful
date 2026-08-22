'use strict';

const crypto = require('node:crypto');

/**
 * Guest session tokens.
 *
 * A token is `base64url(userId.expiresAtMs).hmac`. There is no session store to
 * keep, no password to lose, and a stolen device token expires on its own. The
 * signing key lives only in AUTH_SECRET.
 */

const config = require('../config');

function b64url(input) {
  return Buffer.from(input, 'utf8').toString('base64url');
}

function sign(payload) {
  return crypto.createHmac('sha256', config.authSecret).update(payload).digest('base64url');
}

function issueToken(userId, ttlDays = config.tokenTtlDays) {
  const expiresAt = Date.now() + ttlDays * 24 * 60 * 60 * 1000;
  const payload = b64url(`${userId}.${expiresAt}`);
  return `${payload}.${sign(payload)}`;
}

/** Returns { userId, expiresAt } or null. Never throws on malformed input. */
function verifyToken(token) {
  if (typeof token !== 'string' || token.length > 512) return null;
  const dot = token.lastIndexOf('.');
  if (dot <= 0) return null;
  const payload = token.slice(0, dot);
  const signature = token.slice(dot + 1);
  const expected = sign(payload);
  const a = Buffer.from(signature);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;

  let decoded;
  try {
    decoded = Buffer.from(payload, 'base64url').toString('utf8');
  } catch {
    return null;
  }
  const split = decoded.lastIndexOf('.');
  if (split <= 0) return null;
  const userId = decoded.slice(0, split);
  const expiresAt = Number(decoded.slice(split + 1));
  if (!userId || !Number.isFinite(expiresAt)) return null;
  if (expiresAt < Date.now()) return null;
  return { userId, expiresAt };
}

module.exports = { issueToken, verifyToken };
