'use strict';

const express = require('express');

const { asyncRoute } = require('../middleware/errors');
const { requireUser } = require('../middleware/auth');
const { rateLimit } = require('../middleware/rateLimit');
const validate = require('../lib/validate');
const users = require('../services/users');
const { getStore } = require('../db');

const router = express.Router();

/**
 * First launch. The device sends the guest id it generated and stored locally.
 * Calling this again with the same id returns the same account, so the app can
 * call it on every cold start without creating duplicates.
 */
router.post(
  '/init',
  rateLimit({ name: 'user_init', limit: 30, windowMs: 60_000 }),
  asyncRoute(async (req, res) => {
    const body = validate.requireObject(req.body);
    const guestId = validate.guestId(body.guestId);
    const displayName = validate.optionalDisplayName(body.displayName, undefined);
    const avatarId = validate.avatarId(body.avatarId, 0);
    const result = await users.initGuest(guestId, displayName, avatarId);
    res.json({ user: result.user, token: result.token, isNewUser: result.created });
  }),
);

router.get(
  '/me',
  requireUser,
  asyncRoute(async (req, res) => {
    res.json({ user: users.publicUser(req.user) });
  }),
);

router.patch(
  '/name',
  requireUser,
  rateLimit({ name: 'user_name', limit: 20, windowMs: 60_000 }),
  asyncRoute(async (req, res) => {
    const body = validate.requireObject(req.body);
    const displayName = validate.displayName(body.displayName);
    const user = await users.updateProfile(req.user._id, { displayName });
    res.json({ user });
  }),
);

router.patch(
  '/avatar',
  requireUser,
  rateLimit({ name: 'user_avatar', limit: 30, windowMs: 60_000 }),
  asyncRoute(async (req, res) => {
    const body = validate.requireObject(req.body);
    const avatarId = validate.avatarId(body.avatarId, null);
    if (avatarId === null) {
      res.json({ user: users.publicUser(req.user) });
      return;
    }
    const user = await users.updateProfile(req.user._id, { avatarId });
    res.json({ user });
  }),
);

/** Coin history. The client shows this so a balance change is never a mystery. */
router.get(
  '/transactions',
  requireUser,
  asyncRoute(async (req, res) => {
    const rows = await getStore().transactions.listForUser(req.user._id, 50);
    res.json({
      transactions: rows.map((row) => ({
        id: row._id,
        type: row.type,
        amount: row.amount,
        balanceAfter: row.balanceAfter,
        roomCode: row.roomCode,
        itemId: row.itemId,
        createdAt: row.createdAt,
      })),
    });
  }),
);

router.get(
  '/matches',
  requireUser,
  asyncRoute(async (req, res) => {
    const rows = await getStore().matches.listForUser(req.user._id, 20);
    res.json({
      matches: rows.map((row) => ({
        roomCode: row.roomCode,
        mode: row.mode,
        rounds: row.rounds,
        coinMatch: row.coinMatch,
        createdAt: row.createdAt,
        you: row.players.find((player) => player.userId === req.user._id) || null,
        players: row.players.map((player) => ({
          name: player.name,
          isBot: player.isBot,
          finalRank: player.finalRank,
          payout: player.payout,
        })),
      })),
    });
  }),
);

module.exports = router;
