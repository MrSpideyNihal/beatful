'use strict';

const express = require('express');

const config = require('./config');
const log = require('./lib/log');
const { asyncRoute, errorHandler, notFound } = require('./middleware/errors');
const { getStore } = require('./db');
const userRoutes = require('./routes/user');
const roomRoutes = require('./routes/room');
const economyRoutes = require('./routes/economy');
const shop = require('./services/shop');

function createApp() {
  const app = express();

  app.set('trust proxy', 1); // Render and similar hosts terminate TLS in front.
  app.disable('x-powered-by');

  /**
   * The Android client does not need CORS. A browser build of the same app does,
   * and so does anything poking at the API from a page. Answered before the body
   * parser because a preflight carries no body.
   */
  app.use((req, res, next) => {
    const origin = req.headers.origin;
    const allowed =
      origin && (config.corsOrigins.length === 0 || config.corsOrigins.includes(origin));
    if (allowed) {
      res.set('Access-Control-Allow-Origin', origin);
      res.set('Vary', 'Origin');
      res.set('Access-Control-Allow-Headers', 'authorization, content-type');
      res.set('Access-Control-Allow-Methods', 'GET, POST, PATCH, OPTIONS');
      res.set('Access-Control-Expose-Headers', 'Retry-After');
      res.set('Access-Control-Max-Age', '86400');
    }
    if (req.method === 'OPTIONS') {
      res.status(204).end();
      return;
    }
    next();
  });

  app.use(express.json({ limit: '32kb' }));

  // A malformed JSON body is a client mistake, not a server crash.
  app.use((err, req, res, next) => {
    if (err && err.type === 'entity.parse.failed') {
      res.status(400).json({ error: 'BAD_REQUEST', message: 'That request body was not valid JSON.' });
      return;
    }
    next(err);
  });

  app.get(
    '/health',
    asyncRoute(async (req, res) => {
      let db = { ok: false };
      try {
        db = await getStore().health();
      } catch (err) {
        db = { ok: false, reason: 'unavailable' };
      }
      res.status(db.ok ? 200 : 503).json({
        ok: db.ok,
        service: 'beatful',
        env: config.nodeEnv,
        db,
        time: new Date().toISOString(),
      });
    }),
  );

  /**
   * Public, unauthenticated: the numbers the client needs to draw its own
   * screens consistently with the server rules, plus the coin policy text.
   */
  app.get('/meta', (req, res) => {
    res.json({
      minPlayers: config.minPlayers,
      maxPlayers: config.maxPlayers,
      timerSeconds: {
        min: config.minTimerSeconds,
        max: config.maxTimerSeconds,
        default: config.defaultTimerSeconds,
      },
      maxRounds: config.maxRounds,
      pollTimeoutMs: config.pollTimeoutMs,
      disconnectGraceMs: config.disconnectGraceMs,
      startingCoins: config.startingCoins,
      adReward: { coins: config.adRewardCoins, dailyCap: config.adRewardDailyCap },
      shopItems: shop.ITEMS.length,
      coinPolicy:
        'Coins are play money for this game only. They cannot be exchanged for real money, ' +
        'transferred between players, or refunded.',
    });
  });

  app.use('/user', userRoutes);
  app.use('/room', roomRoutes);
  app.use(economyRoutes);

  app.use(notFound);
  app.use(errorHandler);

  log.debug('app built');
  return app;
}

module.exports = { createApp };
