'use strict';

/**
 * Fixed window rate limiter, in process, no redis.
 *
 * Keyed by user id when the request is authenticated and by IP otherwise, so one
 * abusive device cannot lock out everybody behind the same carrier NAT. Buckets
 * are pruned as they expire, so memory does not grow with traffic.
 *
 * Long polling is deliberately not rate limited by this: a client is expected to
 * re-issue that request the moment it returns.
 */

const { apiError } = require('../lib/errors');

const buckets = new Map();

function keyFor(req, name) {
  const who = req.user ? `u:${req.user._id}` : `ip:${req.ip}`;
  return `${name}:${who}`;
}

function rateLimit({ name, limit, windowMs }) {
  return function limiter(req, res, next) {
    const now = Date.now();
    const key = keyFor(req, name);
    const bucket = buckets.get(key);

    if (!bucket || bucket.resetAt <= now) {
      buckets.set(key, { count: 1, resetAt: now + windowMs });
      if (buckets.size > 5000) pruneExpired(now);
      next();
      return;
    }
    bucket.count += 1;
    if (bucket.count > limit) {
      const retryAfter = Math.ceil((bucket.resetAt - now) / 1000);
      res.set('Retry-After', String(Math.max(1, retryAfter)));
      next(apiError('RATE_LIMITED'));
      return;
    }
    next();
  };
}

function pruneExpired(now = Date.now()) {
  for (const [key, bucket] of buckets) {
    if (bucket.resetAt <= now) buckets.delete(key);
  }
}

function resetAll() {
  buckets.clear();
}

module.exports = { rateLimit, pruneExpired, resetAll };
