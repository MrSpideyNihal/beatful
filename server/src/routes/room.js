'use strict';

const express = require('express');

const { asyncRoute } = require('../middleware/errors');
const { requireUser } = require('../middleware/auth');
const { rateLimit } = require('../middleware/rateLimit');
const validate = require('../lib/validate');
const rooms = require('../services/rooms');
const { apiError } = require('../lib/errors');
const roomCodes = require('../lib/roomCode');

const router = express.Router();

router.use(requireUser);

/** Host creates a room. The returned code and link are what friends need. */
router.post(
  '/create',
  rateLimit({ name: 'room_create', limit: 10, windowMs: 60_000 }),
  asyncRoute(async (req, res) => {
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const settings = validate.roomSettings(body.settings || body, { partial: false });
    const room = await rooms.createRoom(req.user, settings);
    res.status(201).json({ room: rooms.roomView(room, req.user._id) });
  }),
);

/** Join by code. Also the reconnect path: rejoining a game already in progress. */
router.post(
  '/join',
  rateLimit({ name: 'room_join', limit: 30, windowMs: 60_000 }),
  asyncRoute(async (req, res) => {
    const body = validate.requireObject(req.body);
    const code = validate.roomCode(body.code);
    const room = await rooms.joinRoom(req.user, code);
    res.json({ room: rooms.roomView(room, req.user._id) });
  }),
);

/**
 * Cheap existence check for the join screen, so a mistyped code says so
 * immediately instead of after a failed join.
 */
router.get(
  '/lookup',
  rateLimit({ name: 'room_lookup', limit: 60, windowMs: 60_000 }),
  asyncRoute(async (req, res) => {
    const code = validate.roomCode(req.query.code);
    const room = await rooms.findRoomByCode(code);
    if (!room) throw apiError('ROOM_NOT_FOUND');
    res.json({
      roomCode: room.roomCode,
      link: roomCodes.deepLinkFor(room.roomCode),
      status: room.status,
      locked: room.locked,
      playerCount: room.players.length,
      maxPlayers: room.settings.playerCount,
      hostName: (room.players.find((p) => p.userId === room.hostUserId) || {}).name || 'Host',
      canJoin:
        room.status === 'lobby' &&
        !room.locked &&
        room.players.length < room.settings.playerCount,
      alreadyIn: room.players.some((p) => p.userId === req.user._id),
    });
  }),
);

/**
 * Long poll. Answers immediately when the version already moved, otherwise
 * parks until something happens or the window closes.
 *
 * Deliberately not rate limited: the client re-issues it continuously.
 */
router.get(
  '/:id/state',
  asyncRoute(async (req, res) => {
    const roomId = validate.identifier(req.params.id, 'room id');
    const since = validate.sinceVersion(req.query.since);

    // Release the parked wait as soon as the client hangs up, so a backgrounded
    // app does not hold a slot for the full window.
    const controller = new AbortController();
    const onClose = () => controller.abort();
    req.on('close', onClose);
    try {
      const result = await rooms.pollState(req.user._id, roomId, since, controller.signal);
      if (res.writableEnded) return;
      res.json(result);
    } finally {
      req.off('close', onClose);
    }
  }),
);

/** Snapshot without waiting. Used on screen open and after a reconnect. */
router.get(
  '/:id',
  asyncRoute(async (req, res) => {
    const roomId = validate.identifier(req.params.id, 'room id');
    const room = await rooms.getRoomForUser(req.user._id, roomId);
    res.json({ room });
  }),
);

router.post(
  '/:id/play',
  rateLimit({ name: 'room_play', limit: 120, windowMs: 60_000 }),
  asyncRoute(async (req, res) => {
    const roomId = validate.identifier(req.params.id, 'room id');
    const body = validate.requireObject(req.body);
    const card = validate.card(body.card);
    const room = await rooms.playCard(req.user._id, roomId, card);
    res.json({ room: rooms.roomView(room, req.user._id) });
  }),
);

router.post(
  '/:id/pass',
  rateLimit({ name: 'room_pass', limit: 120, windowMs: 60_000 }),
  asyncRoute(async (req, res) => {
    const roomId = validate.identifier(req.params.id, 'room id');
    const room = await rooms.passTurn(req.user._id, roomId);
    res.json({ room: rooms.roomView(room, req.user._id) });
  }),
);

router.post(
  '/:id/start',
  rateLimit({ name: 'room_start', limit: 20, windowMs: 60_000 }),
  asyncRoute(async (req, res) => {
    const roomId = validate.identifier(req.params.id, 'room id');
    const room = await rooms.startGame(req.user._id, roomId);
    res.json({ room: rooms.roomView(room, req.user._id) });
  }),
);

router.post(
  '/:id/settings',
  rateLimit({ name: 'room_settings', limit: 60, windowMs: 60_000 }),
  asyncRoute(async (req, res) => {
    const roomId = validate.identifier(req.params.id, 'room id');
    const current = (await rooms.requireRoom(roomId)).settings;
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const patch = validate.roomSettings(body.settings || body, { partial: true, current });
    const room = await rooms.updateSettings(req.user._id, roomId, patch);
    res.json({ room: rooms.roomView(room, req.user._id) });
  }),
);

router.post(
  '/:id/ready',
  rateLimit({ name: 'room_ready', limit: 60, windowMs: 60_000 }),
  asyncRoute(async (req, res) => {
    const roomId = validate.identifier(req.params.id, 'room id');
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const room = await rooms.setReady(req.user._id, roomId, body.ready !== false);
    res.json({ room: rooms.roomView(room, req.user._id) });
  }),
);

router.post(
  '/:id/kick',
  rateLimit({ name: 'room_kick', limit: 30, windowMs: 60_000 }),
  asyncRoute(async (req, res) => {
    const roomId = validate.identifier(req.params.id, 'room id');
    const body = validate.requireObject(req.body);
    const targetUserId = validate.identifier(body.userId, 'user id');
    const room = await rooms.kickPlayer(req.user._id, roomId, targetUserId);
    res.json({ room: rooms.roomView(room, req.user._id) });
  }),
);

router.post(
  '/:id/lock',
  rateLimit({ name: 'room_lock', limit: 30, windowMs: 60_000 }),
  asyncRoute(async (req, res) => {
    const roomId = validate.identifier(req.params.id, 'room id');
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const room = await rooms.setLocked(req.user._id, roomId, body.locked !== false);
    res.json({ room: rooms.roomView(room, req.user._id) });
  }),
);

/** Lobby: add a practice bot to a free seat. */
router.post(
  '/:id/bot',
  rateLimit({ name: 'room_bot', limit: 30, windowMs: 60_000 }),
  asyncRoute(async (req, res) => {
    const roomId = validate.identifier(req.params.id, 'room id');
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    const difficulty = validate.difficulty(body.difficulty, undefined);
    const room = await rooms.addBot(req.user._id, roomId, difficulty);
    res.json({ room: rooms.roomView(room, req.user._id) });
  }),
);

/** Mid game: hand a seat that never came back to a bot. */
router.post(
  '/:id/bot-takeover',
  rateLimit({ name: 'room_takeover', limit: 30, windowMs: 60_000 }),
  asyncRoute(async (req, res) => {
    const roomId = validate.identifier(req.params.id, 'room id');
    const body = validate.requireObject(req.body);
    const seat = validate.seatIndex(body.seatIndex);
    const difficulty = validate.difficulty(body.difficulty, undefined);
    const room = await rooms.replaceSeatWithBot(req.user._id, roomId, seat, difficulty);
    res.json({ room: rooms.roomView(room, req.user._id) });
  }),
);

router.post(
  '/:id/leave',
  rateLimit({ name: 'room_leave', limit: 30, windowMs: 60_000 }),
  asyncRoute(async (req, res) => {
    const roomId = validate.identifier(req.params.id, 'room id');
    await rooms.leaveRoom(req.user._id, roomId);
    res.json({ ok: true });
  }),
);

/** Chat: send predefined quick-chat or custom text message to all players. */
router.post(
  '/:id/chat',
  rateLimit({ name: 'room_chat', limit: 20, windowMs: 60_000 }),
  asyncRoute(async (req, res) => {
    const roomId = validate.identifier(req.params.id, 'room id');
    const body = req.body && typeof req.body === 'object' ? req.body : {};
    let payload;

    const rawText = body.text != null ? body.text : body.message;
    if (rawText != null) {
      if (typeof rawText !== 'string' || rawText.trim().length === 0) {
        throw apiError('BAD_REQUEST', 'Chat message cannot be empty.');
      }
      if (rawText.trim().length > 120) {
        throw apiError('BAD_REQUEST', 'Chat message is too long (max 120 characters).');
      }
      payload = { text: rawText.trim() };
    } else if (body.messageIndex != null) {
      const messageIndex = Number(body.messageIndex);
      if (!Number.isInteger(messageIndex) || messageIndex < 0 || messageIndex > 7) {
        throw apiError('BAD_REQUEST', 'Invalid chat message index.');
      }
      payload = { messageIndex };
    } else {
      throw apiError('BAD_REQUEST', 'Missing chat message or index.');
    }

    const room = await rooms.sendChat(req.user._id, roomId, payload);
    res.json({ room: rooms.roomView(room, req.user._id) });
  }),
);

/** Host starts a rematch in the same room. Resets to lobby with same room code. */
router.post(
  '/:id/rematch',
  rateLimit({ name: 'room_rematch', limit: 20, windowMs: 60_000 }),
  asyncRoute(async (req, res) => {
    const roomId = validate.identifier(req.params.id, 'room id');
    const room = await rooms.rematchRoom(req.user._id, roomId);
    res.json({ room: rooms.roomView(room, req.user._id) });
  }),
);

module.exports = router;
