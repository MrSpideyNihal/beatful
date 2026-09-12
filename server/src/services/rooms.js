'use strict';

/**
 * Room lifecycle and the only place a friends match is ever mutated.
 *
 * Design notes that matter for correctness:
 *
 *  - The server is the single source of truth. A client sends an intent, this
 *    module re-derives everything from stored state and the rules engine.
 *  - Every mutation runs inside withLock(roomId), so two requests for the same
 *    room can never interleave a read and a write.
 *  - Live rooms are held in a process cache and written through to the store.
 *    That is what makes long polling cheap. It assumes one server instance,
 *    which is what the deployment notes describe; a second instance would need
 *    the version check to move into the database.
 *  - version increments on every visible change and wakes parked pollers.
 */

const crypto = require('node:crypto');

const config = require('../config');
const log = require('../lib/log');
const { apiError } = require('../lib/errors');
const { withLock } = require('../lib/mutex');
const roomCodes = require('../lib/roomCode');
const cards = require('../game/cards');
const rules = require('../game/rules');
const engine = require('../game/engine');
const bots = require('../game/bots');
const watch = require('../realtime/watch');
const { getStore } = require('../db');
const coins = require('./coins');

const NOTICE_LIMIT = 8;
const ROUND_BREAK_MS = 6000;
const BOT_THINK_MS = 1200;

/** Predefined quick-chat messages players can send during a match. */
const CHAT_MESSAGES = [
  '👋 Hello!',
  '👍 Good move!',
  '😄 Well played!',
  '⏳ Hurry up!',
  '😎 Easy!',
  '😱 Oh no!',
  '🎉 GG!',
  '👏 Nice one!',
];

/** roomId -> room document. Authoritative copy while the process is alive. */
const cache = new Map();
const codeIndex = new Map();

function cacheRoom(room) {
  cache.set(room._id, room);
  codeIndex.set(room.roomCode, room._id);
  return room;
}

function forgetRoom(room) {
  cache.delete(room._id);
  codeIndex.delete(room.roomCode);
}

async function loadRoomById(roomId) {
  const cached = cache.get(roomId);
  if (cached) return cached;
  const stored = await getStore().rooms.findById(roomId);
  return stored ? cacheRoom(stored) : null;
}

async function loadRoomByCode(code) {
  const roomId = codeIndex.get(code);
  if (roomId && cache.has(roomId)) return cache.get(roomId);
  const stored = await getStore().rooms.findByCode(code);
  return stored ? cacheRoom(stored) : null;
}

async function requireRoom(roomId) {
  const room = await loadRoomById(roomId);
  if (!room) throw apiError('ROOM_NOT_FOUND');
  return room;
}

async function persist(room) {
  try {
    await getStore().rooms.replace(room);
  } catch (err) {
    // The in memory copy is still correct and play continues. Losing a write
    // only costs the room its survival across a restart, so this is logged and
    // not turned into a player facing failure.
    log.error('room persist failed', { roomId: room._id, roomCode: room.roomCode, err });
  }
}

/** Bump the version, write through, and wake every parked poller. */
async function commit(room) {
  room.version += 1;
  room.updatedAt = new Date().toISOString();
  await persist(room);
  watch.notify(room._id);
  return room;
}

function pushNotice(room, notice) {
  room.notices.push({ id: crypto.randomUUID(), at: Date.now(), ...notice });
  if (room.notices.length > NOTICE_LIMIT) {
    room.notices = room.notices.slice(room.notices.length - NOTICE_LIMIT);
  }
}

function findPlayer(room, userId) {
  return room.players.find((player) => player.userId === userId) || null;
}

function requireMember(room, userId) {
  const player = findPlayer(room, userId);
  if (!player) throw apiError('NOT_IN_ROOM');
  return player;
}

function requireHost(room, userId) {
  if (room.hostUserId !== userId) throw apiError('NOT_HOST');
  return true;
}

function humanPlayers(room) {
  return room.players.filter((player) => !player.isBot);
}

function seatName(room, seatIndex) {
  const player = room.players.find((entry) => entry.seatIndex === seatIndex);
  return player ? player.name : `Seat ${seatIndex + 1}`;
}

function resequenceSeats(room) {
  room.players
    .slice()
    .sort((a, b) => a.seatIndex - b.seatIndex)
    .forEach((player, index) => {
      player.seatIndex = index;
    });
}

/* ------------------------------------------------------------------ create */

function defaultSettings(overrides) {
  return {
    playerCount: 4,
    timerSeconds: config.defaultTimerSeconds,
    rounds: 1,
    coinMatch: false,
    entryFee: 0,
    shuffleSeats: false,
    payout: 'winner_takes_all',
    fillWithBots: false,
    botDifficulty: 'medium',
    ...overrides,
  };
}

async function allocateRoomCode() {
  for (let attempt = 0; attempt < 12; attempt += 1) {
    const code = roomCodes.generateRoomCode();
    if (codeIndex.has(code)) continue;
    const existing = await getStore().rooms.findByCode(code);
    if (!existing) return code;
  }
  throw apiError('SERVER_ERROR', 'Could not allocate a room code. Try again.');
}

async function createRoom(user, settingsInput) {
  const settings = defaultSettings(settingsInput);
  const code = await allocateRoomCode();
  const now = new Date();
  const room = {
    _id: crypto.randomUUID(),
    roomCode: code,
    hostUserId: user._id,
    mode: 'friends',
    status: 'lobby',
    locked: false,
    version: 1,
    settings,
    players: [
      {
        userId: user._id,
        seatIndex: 0,
        name: user.displayName,
        avatarId: user.avatarId ?? 0,
        isBot: false,
        difficulty: null,
        ready: true,
        connected: true,
        lastSeenAt: now.getTime(),
        stake: 0,
      },
    ],
    gameState: null,
    notices: [],
    settled: false,
    roundBreakUntil: null,
    createdAt: now.toISOString(),
    updatedAt: now.toISOString(),
    startedAt: null,
    finishedAt: null,
    expiresAt: new Date(now.getTime() + config.roomTtlHours * 3600 * 1000),
  };
  pushNotice(room, { kind: 'created', text: `${user.displayName} created the room.` });

  const inserted = await getStore().rooms.insert(room);
  if (!inserted.ok) throw apiError('CONFLICT', 'Room code clash. Try again.');
  cacheRoom(room);
  log.info('room created', { roomId: room._id, roomCode: room.roomCode, userId: user._id });
  return room;
}

/* -------------------------------------------------------------------- join */

async function joinRoom(user, code) {
  const room = await loadRoomByCode(code);
  if (!room) throw apiError('ROOM_NOT_FOUND');

  return withLock(room._id, async () => {
    const existing = findPlayer(room, user._id);
    if (existing) {
      // Rejoining an in progress game is just a presence refresh.
      existing.connected = true;
      existing.isBot = false;
      existing.lastSeenAt = Date.now();
      existing.name = user.displayName;
      existing.avatarId = user.avatarId ?? 0;
      await commit(room);
      return room;
    }
    if (room.status !== 'lobby') throw apiError('ALREADY_STARTED');
    if (room.locked) throw apiError('ROOM_LOCKED');
    if (room.players.length >= room.settings.playerCount) throw apiError('ROOM_FULL');

    room.players.push({
      userId: user._id,
      seatIndex: room.players.length,
      name: user.displayName,
      avatarId: user.avatarId ?? 0,
      isBot: false,
      difficulty: null,
      ready: false,
      connected: true,
      lastSeenAt: Date.now(),
      stake: 0,
    });
    pushNotice(room, { kind: 'joined', text: `${user.displayName} joined.` });
    await commit(room);
    log.info('room joined', { roomId: room._id, roomCode: room.roomCode, userId: user._id });
    return room;
  });
}

async function setReady(userId, roomId, ready) {
  const room = await requireRoom(roomId);
  return withLock(room._id, async () => {
    const player = requireMember(room, userId);
    if (room.status !== 'lobby') throw apiError('ALREADY_STARTED');
    player.ready = Boolean(ready);
    player.lastSeenAt = Date.now();
    player.connected = true;
    await commit(room);
    return room;
  });
}

async function leaveRoom(userId, roomId) {
  const room = await requireRoom(roomId);
  return withLock(room._id, async () => {
    const player = findPlayer(room, userId);
    if (!player) return room;

    if (room.status === 'lobby') {
      room.players = room.players.filter((entry) => entry.userId !== userId);
      resequenceSeats(room);
      pushNotice(room, { kind: 'left', text: `${player.name} left.` });
      if (room.players.length === 0) {
        await getStore().rooms.remove(room._id);
        forgetRoom(room);
        watch.notify(room._id);
        return room;
      }
      if (room.hostUserId === userId) {
        const nextHost = room.players.find((entry) => !entry.isBot) || room.players[0];
        room.hostUserId = nextHost.userId;
        pushNotice(room, { kind: 'host', text: `${nextHost.name} is the host now.` });
      }
      await commit(room);
      return room;
    }

    // Mid game a seat cannot simply vanish, the cards would be lost. The seat
    // is marked away and the turn timer keeps resolving it, exactly like a
    // dropped connection. The host can hand it to a bot.
    player.connected = false;
    player.lastSeenAt = Date.now();
    pushNotice(room, { kind: 'away', text: `${player.name} left the table. Their turns play out on the timer.` });
    await commit(room);
    return room;
  });
}

/* ---------------------------------------------------------------- host acts */

async function updateSettings(hostId, roomId, patch) {
  const room = await requireRoom(roomId);
  return withLock(room._id, async () => {
    requireHost(room, hostId);
    if (room.status !== 'lobby') throw apiError('ALREADY_STARTED', 'Settings are locked once the game starts.');
    const next = { ...room.settings, ...patch };
    if (next.playerCount < room.players.length) {
      throw apiError('SETTINGS_INVALID', `There are already ${room.players.length} players in the room.`);
    }
    room.settings = next;
    pushNotice(room, { kind: 'settings', text: 'The host changed the game settings.' });
    await commit(room);
    return room;
  });
}

async function setLocked(hostId, roomId, locked) {
  const room = await requireRoom(roomId);
  return withLock(room._id, async () => {
    requireHost(room, hostId);
    room.locked = Boolean(locked);
    pushNotice(room, {
      kind: 'lock',
      text: room.locked ? 'The room is locked. Nobody else can join.' : 'The room is open again.',
    });
    await commit(room);
    return room;
  });
}

async function kickPlayer(hostId, roomId, targetUserId) {
  const room = await requireRoom(roomId);
  return withLock(room._id, async () => {
    requireHost(room, hostId);
    if (targetUserId === hostId) throw apiError('FORBIDDEN', 'The host cannot kick themselves.');
    const target = findPlayer(room, targetUserId);
    if (!target) throw apiError('USER_NOT_FOUND');
    if (room.status !== 'lobby') {
      throw apiError('ALREADY_STARTED', 'Once the game starts a seat can be handed to a bot instead.');
    }
    room.players = room.players.filter((entry) => entry.userId !== targetUserId);
    resequenceSeats(room);
    pushNotice(room, { kind: 'kicked', text: `${target.name} was removed by the host.` });
    await commit(room);
    return room;
  });
}

function makeBotPlayer(room, seatIndex, difficulty) {
  const index = room.players.filter((entry) => entry.isBot).length + 1;
  return {
    userId: `bot-${crypto.randomUUID()}`,
    seatIndex,
    name: `Bot ${index}`,
    avatarId: 8 + ((index - 1) % 4),
    isBot: true,
    difficulty: difficulty || room.settings.botDifficulty,
    ready: true,
    connected: true,
    lastSeenAt: Date.now(),
    stake: 0,
  };
}

/** Lobby: add a bot to an empty seat. */
async function addBot(hostId, roomId, difficulty) {
  const room = await requireRoom(roomId);
  return withLock(room._id, async () => {
    requireHost(room, hostId);
    if (room.status !== 'lobby') throw apiError('ALREADY_STARTED');
    if (room.players.length >= room.settings.playerCount) throw apiError('ROOM_FULL');
    const bot = makeBotPlayer(room, room.players.length, difficulty);
    room.players.push(bot);
    pushNotice(room, { kind: 'bot_added', text: `${bot.name} joined as a practice player.` });
    await commit(room);
    return room;
  });
}

/**
 * Mid game: hand an away seat to a bot. The cards stay exactly where they are,
 * only who decides the moves changes. This is the documented answer to a player
 * who never comes back.
 */
async function replaceSeatWithBot(hostId, roomId, seatIndex, difficulty) {
  const room = await requireRoom(roomId);
  return withLock(room._id, async () => {
    requireHost(room, hostId);
    if (room.status !== 'in_progress') throw apiError('NOT_STARTED');
    const player = room.players.find((entry) => entry.seatIndex === seatIndex);
    if (!player) throw apiError('BAD_SEAT');
    if (player.isBot) throw apiError('BAD_REQUEST', 'That seat is already a bot.');
    if (player.connected) {
      throw apiError('FORBIDDEN', 'That player is still connected.');
    }
    const previousName = player.name;
    player.isBot = true;
    player.difficulty = difficulty || room.settings.botDifficulty;
    player.name = `${previousName} (bot)`;
    player.connected = true;
    pushNotice(room, {
      kind: 'bot_takeover',
      text: `${previousName} did not come back. A bot is playing their cards.`,
    });
    await commit(room);
    return room;
  });
}

/* ------------------------------------------------------------------- start */

async function chargeEntryFees(room) {
  const fee = room.settings.entryFee;
  const paid = [];
  for (const player of humanPlayers(room)) {
    try {
      await coins.debit(player.userId, fee, {
        type: coins.TYPES.MATCH_ENTRY,
        roomCode: room.roomCode,
      });
      player.stake = fee;
      paid.push(player);
    } catch (err) {
      // Roll back everyone who already paid so a short balance cannot swallow
      // another player coins.
      for (const refundTo of paid) {
        try {
          await coins.credit(refundTo.userId, fee, {
            type: coins.TYPES.MATCH_ENTRY_REFUND,
            roomCode: room.roomCode,
          });
          refundTo.stake = 0;
        } catch (refundErr) {
          log.error('entry fee refund failed', {
            roomId: room._id,
            userId: refundTo.userId,
            amount: fee,
            err: refundErr,
          });
        }
      }
      if (err && err.code === 'INSUFFICIENT_COINS') {
        throw apiError('INSUFFICIENT_COINS', `${player.name} does not have ${fee} coins for the entry fee.`);
      }
      throw err;
    }
  }
  return fee * paid.length;
}

function applySeatCurse(room) {
  if (room.cursedSeat === null || room.cursedSeat === undefined) return;
  const state = room.gameState;
  if (!state || !Array.isArray(state.hands) || !state.hands[room.cursedSeat]) return;
  const targetSeat = room.cursedSeat;
  const targetHand = state.hands[targetSeat];

  const highCardPool = [];
  for (let s = 0; s < state.hands.length; s += 1) {
    if (s === targetSeat) continue;
    for (const c of state.hands[s]) {
      const r = cards.rankOf(c);
      if (r >= 11 && r <= 13) {
        highCardPool.push({ seat: s, card: c, rank: r });
      }
    }
  }

  const lowCardsInTarget = [];
  for (const c of targetHand) {
    const r = cards.rankOf(c);
    if (r !== 7 && r <= 6) {
      lowCardsInTarget.push({ card: c, rank: r });
    }
  }

  const swaps = Math.min(highCardPool.length, lowCardsInTarget.length, 5);
  for (let i = 0; i < swaps; i += 1) {
    const high = highCardPool[i];
    const low = lowCardsInTarget[i];

    const otherHand = state.hands[high.seat];
    const hIdx = otherHand.indexOf(high.card);
    if (hIdx !== -1) otherHand.splice(hIdx, 1);
    otherHand.push(low.card);

    const tIdx = targetHand.indexOf(low.card);
    if (tIdx !== -1) targetHand.splice(tIdx, 1);
    targetHand.push(high.card);
  }

  state.hands = state.hands.map((h) => cards.sortHand(h));
  room.cursedSeat = null;
}

async function startGame(hostId, roomId) {
  const room = await requireRoom(roomId);
  return withLock(room._id, async () => {
    requireHost(room, hostId);
    if (room.status === 'in_progress') throw apiError('ALREADY_STARTED');
    if (room.status === 'finished') throw apiError('ALREADY_STARTED', 'That match is over. Create a new room.');

    if (room.settings.fillWithBots) {
      while (room.players.length < room.settings.playerCount) {
        room.players.push(makeBotPlayer(room, room.players.length, room.settings.botDifficulty));
      }
    }
    if (room.players.length < config.minPlayers) throw apiError('NOT_ENOUGH_PLAYERS');
    if (room.players.length > config.maxPlayers) throw apiError('SETTINGS_INVALID', 'Too many players.');
    if (humanPlayers(room).length === 0) throw apiError('NOT_ENOUGH_PLAYERS');

    if (room.settings.shuffleSeats) {
      const order = cards.shuffle(room.players.map((_, index) => index));
      order.forEach((seat, index) => {
        room.players[index].seatIndex = seat;
      });
    } else {
      resequenceSeats(room);
    }
    room.players.sort((a, b) => a.seatIndex - b.seatIndex);

    room.pool = 0;
    if (room.settings.coinMatch && room.settings.entryFee > 0) {
      room.pool = await chargeEntryFees(room);
    }

    const now = Date.now();
    room.gameState = engine.startRound({
      seatCount: room.players.length,
      timerSeconds: room.settings.timerSeconds,
      rounds: room.settings.rounds,
      seed: cards.randomSeed(),
      now,
    });
    applySeatCurse(room);
    room.status = 'in_progress';
    room.startedAt = new Date(now).toISOString();
    room.settled = false;
    room.roundBreakUntil = null;
    room.locked = true;
    pushNotice(room, {
      kind: 'round_start',
      text: `Round 1 of ${room.settings.rounds}. ${seatName(room, room.gameState.currentTurnSeat)} starts.`,
    });
    await commit(room);
    log.info('game started', {
      roomId: room._id,
      roomCode: room.roomCode,
      seats: room.players.length,
      coinMatch: room.settings.coinMatch,
    });
    await maybeAdvanceAutomation(room, Date.now());
    return room;
  });
}

/* ---------------------------------------------------------------- gameplay */

function requireActiveGame(room) {
  if (room.status !== 'in_progress' || !room.gameState) throw apiError('NOT_STARTED');
  return room.gameState;
}

async function playCard(userId, roomId, card) {
  const room = await requireRoom(roomId);
  return withLock(room._id, async () => {
    const player = requireMember(room, userId);
    const state = requireActiveGame(room);
    player.connected = true;
    player.lastSeenAt = Date.now();
    if (player.isBot && !player.userId.startsWith('bot-')) {
      player.isBot = false;
    }
    if (player.isBot) throw apiError('FORBIDDEN', 'That seat is played by a bot.');

    // The engine re-checks turn order, ownership and legality. Nothing the
    // client claims is trusted here.
    const entry = engine.playCard(state, player.seatIndex, card, Date.now());
    await afterMove(room, entry);
    return room;
  });
}

async function passTurn(userId, roomId) {
  const room = await requireRoom(roomId);
  return withLock(room._id, async () => {
    const player = requireMember(room, userId);
    const state = requireActiveGame(room);
    player.connected = true;
    player.lastSeenAt = Date.now();
    if (player.isBot && !player.userId.startsWith('bot-')) {
      player.isBot = false;
    }
    if (player.isBot) throw apiError('FORBIDDEN', 'That seat is played by a bot.');

    const entry = engine.pass(state, player.seatIndex, Date.now());
    await afterMove(room, entry);
    return room;
  });
}

/** Shared tail for every move, human, bot or timer driven. */
async function afterMove(room, entry) {
  const state = room.gameState;
  if (entry && entry.auto) {
    pushNotice(room, timeoutNotice(room, entry));
  }
  noteRoundBoundary(room, Date.now());
  await commit(room);
  if (state.status === engine.STATUS.FINISHED) {
    await settleMatch(room);
  }
}

function timeoutNotice(room, entry) {
  const who = seatName(room, entry.seatIndex);
  return entry.type === 'play'
    ? {
        kind: 'timeout_play',
        seatIndex: entry.seatIndex,
        text: `${who} ran out of time. Auto played ${cards.cardLabel(entry.card)}.`,
      }
    : {
        kind: 'timeout_pass',
        seatIndex: entry.seatIndex,
        text: `${who} ran out of time and had nothing to play. Passed.`,
      };
}

/**
 * Called after any move that might have ended a round. Opens the between rounds
 * pause exactly once, which is also what stops the automation loop from dealing
 * the next round in the same tick.
 */
function noteRoundBoundary(room, now) {
  const state = room.gameState;
  if (!state) return false;
  if (state.status === engine.STATUS.ROUND_OVER && !room.roundBreakUntil) {
    room.roundBreakUntil = now + ROUND_BREAK_MS;
    pushNotice(room, {
      kind: 'round_over',
      text: `${seatName(room, state.winnerSeat)} won round ${state.round}. Next round in a moment.`,
    });
    return true;
  }
  if (state.status === engine.STATUS.FINISHED && !room.settled) {
    pushNotice(room, {
      kind: 'match_over',
      text: `${seatName(room, state.winnerSeat)} won the final round.`,
    });
    return true;
  }
  return false;
}

/* ---------------------------------------------------------------- automation */

/**
 * Drives everything that happens without a client request: bot turns, turn
 * timer expiry, the gap between rounds and match settlement. Called by the turn
 * loop for every live room and once directly after a move so a bot reacts
 * immediately instead of waiting for the next sweep.
 *
 * Must be called with the room lock held, or from tickRoom which takes it.
 */
async function maybeAdvanceAutomation(room, now) {
  let changed = false;
  for (let guard = 0; guard < 16; guard += 1) {
    const state = room.gameState;
    if (!state) break;

    if (state.status === engine.STATUS.FINISHED) break;

    if (state.status === engine.STATUS.ROUND_OVER) {
      if (room.roundBreakUntil && now < room.roundBreakUntil) break;
      room.gameState = engine.nextRound(state, now, cards.randomSeed());
      applySeatCurse(room);
      room.roundBreakUntil = null;
      pushNotice(room, {
        kind: 'round_start',
        text: `Round ${room.gameState.round} of ${room.gameState.rounds}. ${seatName(room, room.gameState.currentTurnSeat)} starts.`,
      });
      changed = true;
      continue;
    }

    const seat = state.currentTurnSeat;
    const player = room.players.find((entry) => entry.seatIndex === seat);

    if (player && player.isBot) {
      // A bot pauses so a human can follow what happened, then moves.
      if (now - state.turnStartedAt < BOT_THINK_MS) break;
      const choice = bots.chooseMove(player.difficulty, {
        table: state.table,
        hand: state.hands[seat].slice(),
        handCounts: engine.handSizes(state),
        mySeat: seat,
        rng: Math.random,
      });
      const entry =
        choice === null ? engine.pass(state, seat, now) : engine.playCard(state, seat, choice, now);
      if (entry.type === 'pass') {
        pushNotice(room, {
          kind: 'pass',
          seatIndex: seat,
          text: `${player.name} had nothing to play and passed.`,
        });
      }
      changed = true;
      noteRoundBoundary(room, now);
      continue;
    }

    if (engine.isTurnExpired(state, now)) {
      const entry = engine.resolveTimeout(state, now, Math.random);
      if (!entry) break;
      pushNotice(room, timeoutNotice(room, entry));
      changed = true;
      noteRoundBoundary(room, now);
      continue;
    }

    break;
  }

  if (changed) {
    await commit(room);
    if (room.gameState.status === engine.STATUS.FINISHED && !room.settled) {
      await settleMatch(room);
    }
  }
  return changed;
}

/**
 * Presence bookkeeping. Both directions are decided here, inside the room lock,
 * so a heartbeat on an unlocked request never has to touch the version counter.
 * Returns true when something visible changed.
 */
function refreshPresence(room, now) {
  let changed = false;
  for (const player of room.players) {
    if (player.isBot) continue;
    const away = now - player.lastSeenAt > config.disconnectGraceMs;
    if (player.connected && away) {
      player.connected = false;
      pushNotice(room, {
        kind: 'disconnected',
        seatIndex: player.seatIndex,
        text: `${player.name} lost connection. Their turns play out on the timer.`,
      });
      changed = true;
    } else if (!player.connected && !away) {
      player.connected = true;
      pushNotice(room, {
        kind: 'reconnected',
        seatIndex: player.seatIndex,
        text: `${player.name} is back.`,
      });
      changed = true;
    }
  }
  return changed;
}

/**
 * One sweep step for a single room. Takes the lock itself. Returns true when the
 * room should be dropped from the sweep list.
 */
async function tickRoom(roomId, now = Date.now()) {
  const room = cache.get(roomId);
  if (!room) return true;
  return withLock(roomId, async () => {
    const presenceChanged = refreshPresence(room, now);
    let automationChanged = false;
    if (room.status === 'in_progress') {
      automationChanged = await maybeAdvanceAutomation(room, now);
    }
    // maybeAdvanceAutomation commits its own changes. A presence change on its
    // own still needs a version bump so the other seats see the away marker.
    if (presenceChanged && !automationChanged) await commit(room);

    // Abandoned lobby, or a finished room nobody is looking at any more.
    const idleFor = now - new Date(room.updatedAt).getTime();
    if (room.status === 'lobby' && idleFor > config.lobbyIdleTimeoutMs) {
      await getStore().rooms.remove(room._id);
      forgetRoom(room);
      watch.notify(room._id);
      return true;
    }
    if (room.status === 'finished' && idleFor > 15 * 60 * 1000) {
      forgetRoom(room);
      return true;
    }
    return false;
  });
}

function liveRoomIds() {
  return Array.from(cache.keys());
}

/* ------------------------------------------------------------- settlement */

/**
 * Pays out the pool and writes the match history. Guarded by room.settled so a
 * retry, a double tick or a late request can never pay twice.
 */
async function settleMatch(room) {
  if (room.settled) return room;
  room.settled = true;
  room.status = 'finished';
  room.finishedAt = new Date().toISOString();

  const state = room.gameState;
  const standings = engine.matchStandings(state);
  const humanSeats = new Set(humanPlayers(room).map((player) => player.seatIndex));

  // Bots never staked anything, so they never take coins out of the pool. The
  // human seats are re-ranked among themselves before the split. Copies, not the
  // standings themselves: a player beaten by a bot came second, and the result
  // everybody reads has to keep saying so even though the coins come to them.
  const humanStandings = standings
    .filter((entry) => humanSeats.has(entry.seatIndex))
    .map((entry) => ({ ...entry }))
    .sort((a, b) => a.score - b.score || a.seatIndex - b.seatIndex);
  let rank = 0;
  let previousScore = null;
  humanStandings.forEach((entry, index) => {
    if (previousScore === null || entry.score !== previousScore) {
      rank = index + 1;
      previousScore = entry.score;
    }
    entry.rank = rank;
  });

  const pool = room.players.reduce((sum, player) => sum + (player.stake || 0), 0);
  const payouts = room.settings.coinMatch
    ? coins.computePayouts(pool, humanStandings, room.settings.payout)
    : new Map();

  const matchPlayers = [];
  for (const player of room.players) {
    const standing = standings[player.seatIndex] || { rank: null, score: null };
    const payout = payouts.get(player.seatIndex) || 0;
    if (payout > 0 && !player.isBot) {
      try {
        await coins.credit(player.userId, payout, {
          type: coins.TYPES.MATCH_WIN,
          roomCode: room.roomCode,
        });
      } catch (err) {
        log.error('payout failed', { roomId: room._id, userId: player.userId, payout, err });
      }
    }
    if (!player.isBot) {
      try {
        await getStore().users.recordMatchResult(player.userId, {
          won: standing.rank === 1,
          rounds: state.round,
        });
      } catch (err) {
        log.error('stat update failed', { roomId: room._id, userId: player.userId, err });
      }
    }
    matchPlayers.push({
      userId: player.userId,
      name: player.name,
      isBot: player.isBot,
      seatIndex: player.seatIndex,
      finalRank: standing.rank,
      score: standing.score,
      cardsRemaining: state.hands[player.seatIndex] ? state.hands[player.seatIndex].length : 0,
      stake: player.stake || 0,
      payout,
    });
  }

  room.result = {
    standings,
    payouts: Array.from(payouts.entries()).map(([seatIndex, amount]) => ({ seatIndex, amount })),
    pool,
  };

  try {
    await getStore().matches.insert({
      _id: crypto.randomUUID(),
      roomCode: room.roomCode,
      mode: 'friends',
      players: matchPlayers,
      rounds: state.rounds,
      coinMatch: Boolean(room.settings.coinMatch),
      entryFee: room.settings.entryFee,
      pool,
      payoutMode: room.settings.payout,
      createdAt: new Date().toISOString(),
      expiresAt: new Date(Date.now() + config.matchTtlDays * 24 * 3600 * 1000),
    });
  } catch (err) {
    log.error('match history insert failed', { roomId: room._id, err });
  }

  pushNotice(room, { kind: 'settled', text: 'Match over. Coins have been paid out.' });
  await commit(room);
  log.info('match settled', { roomId: room._id, roomCode: room.roomCode, pool });
  return room;
}

/* ------------------------------------------------------------------- chat */

/**
 * Send a chat message (either predefined quick-chat or custom text). The
 * message is stored as a notice so all players see it through normal polling.
 * Rate limited at the route layer.
 */
async function sendChat(userId, roomId, payload) {
  const messageIndex = typeof payload === 'number'
    ? payload
    : payload && payload.messageIndex != null
      ? Number(payload.messageIndex)
      : null;
  const customText = typeof payload === 'object' && payload?.text != null
    ? String(payload.text).trim()
    : null;

  return withLock(roomId, async () => {
    const room = await requireRoom(roomId);
    const player = requireMember(room, userId);
    if (player.isBot && !player.userId.startsWith('bot-')) {
      player.isBot = false;
      player.connected = true;
      if (player.name.endsWith(' (bot)')) {
        player.name = player.name.replace(/\s*\(bot\)$/, '');
      }
    }

    let text;
    if (customText) {
      if (customText.length === 0) throw apiError('BAD_REQUEST', 'Chat message cannot be empty.');
      if (customText.length > 120) throw apiError('BAD_REQUEST', 'Chat message too long.');
      text = customText.replace(/[\r\n\t]+/g, ' ');
    } else if (messageIndex != null) {
      text = CHAT_MESSAGES[messageIndex];
      if (!text) throw apiError('BAD_REQUEST', 'Invalid message index.');
    } else {
      throw apiError('BAD_REQUEST', 'No chat message provided.');
    }

    let rawName = player.name.replace(/\s*\(bot\)$/, '').trim();
    const playerName = rawName.toLowerCase() === 'you'
      ? `Player ${player.seatIndex + 1}`
      : rawName;
    pushNotice(room, {
      kind: 'chat',
      fromUserId: userId,
      fromName: playerName,
      fromSeat: player.seatIndex,
      seatIndex: player.seatIndex,
      messageIndex: messageIndex ?? -1,
      text: `${playerName}: ${text}`,
    });
    return commit(room);
  });
}

/* ------------------------------------------------------------------- views */

function roomView(room, userId, now = Date.now()) {
  const me = findPlayer(room, userId);
  const state = room.gameState;
  const handCounts = state ? engine.handSizes(state) : [];
  return {
    roomId: room._id,
    roomCode: room.roomCode,
    link: roomCodes.deepLinkFor(room.roomCode),
    status: room.status,
    locked: room.locked,
    version: room.version,
    hostUserId: room.hostUserId,
    isHost: room.hostUserId === userId,
    settings: room.settings,
    players: room.players
      .slice()
      .sort((a, b) => a.seatIndex - b.seatIndex)
      .map((player) => ({
        userId: player.userId,
        seatIndex: player.seatIndex,
        name: player.name,
        avatarId: player.avatarId,
        isBot: player.isBot,
        difficulty: player.difficulty,
        ready: player.ready,
        connected: player.connected,
        isHost: room.hostUserId === player.userId,
        isYou: me ? player.userId === me.userId : false,
        cardCount: handCounts[player.seatIndex] ?? 0,
        stake: player.stake || 0,
      })),
    yourSeat: me ? me.seatIndex : null,
    game: state ? engine.publicView(state, me ? me.seatIndex : null, now) : null,
    result: room.result || null,
    roundBreakUntil: room.roundBreakUntil,
    notices: room.notices.slice(-4),
    serverTime: now,
  };
}

/**
 * Long poll. Returns as soon as the room version moved past `since`, or after
 * the poll window with changed:false so the client can simply ask again.
 */
async function pollState(userId, roomId, since, signal) {
  let room = await requireRoom(roomId);
  requireMember(room, userId);
  touch(room, userId);

  if (room.version > since) {
    return { changed: true, room: roomView(room, userId) };
  }
  const changed = await watch.waitForChange(roomId, config.pollTimeoutMs, signal);
  room = cache.get(roomId) || (await loadRoomById(roomId));
  if (!room) throw apiError('ROOM_NOT_FOUND');
  if (!changed && room.version <= since) {
    return { changed: false, version: room.version, serverTime: Date.now() };
  }
  return { changed: true, room: roomView(room, userId) };
}

/**
 * Presence heartbeat. Cheap enough to call on every authenticated request: it
 * only records the timestamp. The visible connected flag is flipped by
 * refreshPresence inside the locked tick, so this never bumps the version and
 * never races with a move.
 */
function touch(room, userId) {
  const player = findPlayer(room, userId);
  if (!player || player.isBot) return false;
  player.lastSeenAt = Date.now();
  return true;
}

async function getRoomForUser(userId, roomId) {
  const room = await requireRoom(roomId);
  requireMember(room, userId);
  touch(room, userId);
  return roomView(room, userId);
}

async function findRoomByCode(code) {
  return loadRoomByCode(code);
}

async function rematchRoom(userId, roomId) {
  return withLock(roomId, async () => {
    const room = await requireRoom(roomId);
    requireHost(room, userId);
    if (room.status !== 'finished') {
      throw apiError('ROOM_STARTED', 'Room must be finished to start a rematch.');
    }

    room.status = 'lobby';
    room.gameState = null;
    room.result = null;
    room.settled = false;
    room.finishedAt = null;
    room.locked = false;

    for (const player of room.players) {
      player.ready = player.userId === room.hostUserId || Boolean(player.isBot);
      player.stake = 0;
    }

    pushNotice(room, {
      kind: 'rematch',
      text: 'Rematch started! Ready up to play again.',
    });

    await commit(room);
    watch.notify(room._id);
    log.info('room rematch', { roomId: room._id, roomCode: room.roomCode });
    return room;
  });
}

/* -------------------------------------------------------------------- admin */

function listRoomsAdmin() {
  const roomsList = [];
  for (const room of cache.values()) {
    roomsList.push({
      roomId: room._id,
      roomCode: room.roomCode,
      status: room.status,
      round: room.gameState ? room.gameState.round : null,
      totalRounds: room.settings.rounds,
      cursedSeat: room.cursedSeat ?? null,
      players: room.players.map((p) => ({
        userId: p.userId,
        seatIndex: p.seatIndex,
        name: p.name,
        isBot: p.isBot,
        score: room.gameState?.scores ? room.gameState.scores[p.seatIndex] : 0,
        cardsCount: room.gameState?.hands && room.gameState.hands[p.seatIndex] ? room.gameState.hands[p.seatIndex].length : 0,
      })),
      createdAt: room.createdAt,
      updatedAt: room.updatedAt,
    });
  }
  return roomsList;
}

async function setSeatScore(roomId, seatIndex, score) {
  const room = await requireRoom(roomId);
  return withLock(room._id, async () => {
    const state = room.gameState;
    if (!state) throw apiError('NOT_STARTED', 'No active game in this room.');
    if (!state.scores) {
      state.scores = new Array(state.seatCount).fill(0);
    }
    state.scores[seatIndex] = score;
    state.ranks = rules.rankSeats(state.scores);

    if (room.result && Array.isArray(room.result.standings)) {
      const entry = room.result.standings.find((s) => s.seatIndex === seatIndex);
      if (entry) entry.score = score;
    }
    await commit(room);
    return room;
  });
}

async function setSeatCurse(roomId, seatIndex) {
  const room = await requireRoom(roomId);
  return withLock(room._id, async () => {
    room.cursedSeat = seatIndex;
    if (room.gameState && room.gameState.status === engine.STATUS.IN_PROGRESS && room.gameState.log.length <= 2) {
      applySeatCurse(room);
    }
    await commit(room);
    return room;
  });
}

/** Test helper. Drops every cached room without touching the store. */
function resetCache() {
  cache.clear();
  codeIndex.clear();
}

module.exports = {
  ROUND_BREAK_MS,
  BOT_THINK_MS,
  createRoom,
  joinRoom,
  leaveRoom,
  setReady,
  updateSettings,
  setLocked,
  kickPlayer,
  addBot,
  replaceSeatWithBot,
  startGame,
  rematchRoom,
  playCard,
  passTurn,
  pollState,
  getRoomForUser,
  findRoomByCode,
  requireRoom,
  roomView,
  tickRoom,
  liveRoomIds,
  settleMatch,
  maybeAdvanceAutomation,
  sendChat,
  CHAT_MESSAGES,
  listRoomsAdmin,
  setSeatScore,
  setSeatCurse,
  resetCache,
};
