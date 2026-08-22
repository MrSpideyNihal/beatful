'use strict';

/**
 * Structured logging.
 *
 * Only fields that are explicitly passed get logged. Request bodies, tokens and
 * connection strings are never logged by any caller, and redact() strips the
 * obvious offenders if one slips through.
 */

const SENSITIVE = new Set(['token', 'authorization', 'mongoUri', 'password', 'secret', 'guestId']);

const LEVELS = { silent: 0, error: 1, warn: 2, info: 3, debug: 4 };
const requested = String(process.env.LOG_LEVEL || '').toLowerCase();
const threshold =
  LEVELS[requested] === undefined
    ? process.env.NODE_ENV === 'production'
      ? LEVELS.info
      : LEVELS.debug
    : LEVELS[requested];

function redact(meta) {
  if (!meta || typeof meta !== 'object') return undefined;
  const out = {};
  for (const [key, value] of Object.entries(meta)) {
    if (SENSITIVE.has(key)) {
      out[key] = '[redacted]';
    } else if (value instanceof Error) {
      out[key] = { name: value.name, message: value.message, code: value.code };
    } else if (typeof value === 'object' && value !== null) {
      out[key] = JSON.stringify(value).slice(0, 500);
    } else {
      out[key] = value;
    }
  }
  return out;
}

function emit(level, message, meta) {
  if (LEVELS[level] > threshold) return;
  const line = { at: new Date().toISOString(), level, message };
  const extra = redact(meta);
  if (extra) Object.assign(line, extra);
  const text = JSON.stringify(line);
  if (level === 'error') process.stderr.write(`${text}\n`);
  else process.stdout.write(`${text}\n`);
}

module.exports = {
  info: (message, meta) => emit('info', message, meta),
  warn: (message, meta) => emit('warn', message, meta),
  error: (message, meta) => emit('error', message, meta),
  debug: (message, meta) => emit('debug', message, meta),
};
