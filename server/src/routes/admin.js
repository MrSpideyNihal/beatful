'use strict';

const express = require('express');

const { asyncRoute } = require('../middleware/errors');
const { rateLimit } = require('../middleware/rateLimit');
const { apiError } = require('../lib/errors');
const { issueToken, verifyToken } = require('../lib/token');
const validate = require('../lib/validate');
const { getStore } = require('../db');
const coins = require('../services/coins');
const rooms = require('../services/rooms');
const log = require('../lib/log');

const router = express.Router();

const ADMIN_USER = process.env.ADMIN_USER || 'nihaldev';
const ADMIN_PASS = process.env.ADMIN_PASS || 'nihalisgret9322161961';

/**
 * Admin authentication middleware.
 */
function requireAdmin(req, res, next) {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) {
    throw apiError('UNAUTHORIZED', 'Admin authorization token required.');
  }
  const token = header.slice(7).trim();
  const verified = verifyToken(token);
  if (!verified || !verified.userId || !verified.userId.startsWith('admin:')) {
    throw apiError('UNAUTHORIZED', 'Invalid or expired admin token.');
  }
  req.admin = { username: verified.userId.slice(6) };
  next();
}

/**
 * Admin Login
 */
router.post(
  '/login',
  rateLimit({ name: 'admin_login', limit: 15, windowMs: 60_000 }),
  asyncRoute(async (req, res) => {
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const username = String(body.username || '').trim();
    const password = String(body.password || '').trim();

    if (username !== ADMIN_USER || password !== ADMIN_PASS) {
      log.warn('Failed admin login attempt', { username });
      throw apiError('UNAUTHORIZED', 'Invalid admin credentials.');
    }

    const token = issueToken(`admin:${username}`, 30);
    log.info('Admin logged in successfully', { username });
    res.json({ ok: true, token, user: username });
  }),
);

/**
 * List / search users
 */
router.get(
  '/users',
  requireAdmin,
  asyncRoute(async (req, res) => {
    const query = req.query.q ? String(req.query.q).trim() : '';
    const userList = await getStore().users.listUsers({ query, limit: 50 });
    res.json({
      users: userList.map((u) => ({
        userId: u._id,
        guestId: u.guestId,
        displayName: u.displayName,
        avatarId: u.avatarId ?? 0,
        coins: u.coins ?? 0,
        stats: u.stats || { wins: 0, matchesPlayed: 0, roundsPlayed: 0 },
        createdAt: u.createdAt,
      })),
    });
  }),
);

/**
 * Gift or deduct coins for a user
 */
router.post(
  '/coins/gift',
  requireAdmin,
  asyncRoute(async (req, res) => {
    const body = validate.requireObject(req.body);
    const userId = validate.identifier(body.userId, 'user id');
    const amount = Number(body.amount);

    if (!Number.isInteger(amount) || amount === 0 || Math.abs(amount) > 1_000_000) {
      throw apiError('BAD_REQUEST', 'Amount must be a non-zero integer up to 1,000,000.');
    }

    let newBalance;
    if (amount > 0) {
      newBalance = await coins.credit(userId, amount, { type: 'admin_grant' });
    } else {
      newBalance = await coins.debit(userId, Math.abs(amount), { type: 'admin_deduction' });
    }

    log.info('Admin adjusted coins', { admin: req.admin.username, userId, amount, newBalance });
    res.json({ ok: true, userId, amount, balanceAfter: newBalance });
  }),
);

/**
 * List active game rooms
 */
router.get(
  '/rooms',
  requireAdmin,
  asyncRoute(async (req, res) => {
    const activeRooms = rooms.listRoomsAdmin();
    res.json({ rooms: activeRooms });
  }),
);

/**
 * Alter seat score in an active room
 */
router.post(
  '/room/:id/score',
  requireAdmin,
  asyncRoute(async (req, res) => {
    const roomId = validate.identifier(req.params.id, 'room id');
    const body = validate.requireObject(req.body);
    const seatIndex = Number(body.seatIndex);
    const score = Number(body.score);

    if (!Number.isInteger(seatIndex) || seatIndex < 0 || seatIndex >= 8) {
      throw apiError('BAD_REQUEST', 'Invalid seat index.');
    }
    if (!Number.isInteger(score) || score < 0 || score > 500) {
      throw apiError('BAD_REQUEST', 'Score must be a positive integer between 0 and 500.');
    }

    const room = await rooms.setSeatScore(roomId, seatIndex, score);
    log.info('Admin altered seat score', { admin: req.admin.username, roomId, seatIndex, score });
    res.json({ ok: true, roomId, seatIndex, score, room: rooms.roomView(room, '') });
  }),
);

/**
 * Curse a player seat for the next round (deal high penalty cards: J, Q, K)
 */
router.post(
  '/room/:id/curse',
  requireAdmin,
  asyncRoute(async (req, res) => {
    const roomId = validate.identifier(req.params.id, 'room id');
    const body = validate.requireObject(req.body);
    const seatIndex = Number(body.seatIndex);

    if (!Number.isInteger(seatIndex) || seatIndex < 0 || seatIndex >= 8) {
      throw apiError('BAD_REQUEST', 'Invalid seat index.');
    }

    await rooms.setSeatCurse(roomId, seatIndex);
    log.info('Admin cursed seat with high cards', { admin: req.admin.username, roomId, seatIndex });
    res.json({ ok: true, roomId, cursedSeat: seatIndex, message: `Seat ${seatIndex + 1} cursed with high cards!` });
  }),
);

module.exports = router;
