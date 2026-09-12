'use strict';

/**
 * In memory store.
 *
 * Used by the test suite and for local runs without a database. It implements
 * the exact same interface as the mongo store, including the "atomic" contract:
 * because none of these methods await anything, each one runs to completion
 * without interleaving, which is the same guarantee findOneAndUpdate gives.
 */

const crypto = require('node:crypto');

function clone(value) {
  return value === undefined ? undefined : JSON.parse(JSON.stringify(value));
}

function createMemoryStore() {
  const users = new Map();
  const usersByGuest = new Map();
  const rooms = new Map();
  const roomsByCode = new Map();
  const matches = [];
  const transactions = [];

  return {
    kind: 'memory',

    async init() {
      return this;
    },
    async close() {},
    async health() {
      return { ok: true, kind: 'memory' };
    },

    users: {
      async upsertGuest(guestId, defaults) {
        const existingId = usersByGuest.get(guestId);
        if (existingId) return { user: clone(users.get(existingId)), created: false };
        const id = crypto.randomUUID();
        const user = {
          _id: id,
          guestId,
          displayName: defaults.displayName,
          avatarId: defaults.avatarId ?? 0,
          coins: defaults.coins ?? 0,
          stats: { wins: 0, matchesPlayed: 0, roundsPlayed: 0 },
          ownedItems: defaults.ownedItems ? defaults.ownedItems.slice() : [],
          selected: { cardBack: 'back_classic', table: 'table_green' },
          adRewards: { day: null, count: 0 },
          createdAt: new Date().toISOString(),
        };
        users.set(id, user);
        usersByGuest.set(guestId, id);
        return { user: clone(user), created: true };
      },

      async findById(userId) {
        return clone(users.get(userId));
      },

      async listUsers({ query, limit = 50 } = {}) {
        let list = Array.from(users.values());
        if (query) {
          const q = String(query).toLowerCase();
          list = list.filter((u) => u._id.toLowerCase().includes(q) || (u.displayName && u.displayName.toLowerCase().includes(q)));
        }
        return list.slice(0, limit).map((u) => clone(u));
      },

      async setProfile(userId, patch) {
        const user = users.get(userId);
        if (!user) return null;
        if (patch.displayName !== undefined) user.displayName = patch.displayName;
        if (patch.avatarId !== undefined) user.avatarId = patch.avatarId;
        return clone(user);
      },

      async setSelected(userId, kind, itemId) {
        const user = users.get(userId);
        if (!user) return null;
        user.selected = { ...user.selected, [kind]: itemId };
        return clone(user);
      },

      /** Single step balance change. Refuses to go negative. */
      async adjustCoins(userId, delta) {
        const user = users.get(userId);
        if (!user) return { ok: false, reason: 'USER_NOT_FOUND' };
        if (delta < 0 && user.coins + delta < 0) {
          return { ok: false, reason: 'INSUFFICIENT_COINS', user: clone(user) };
        }
        user.coins += delta;
        return { ok: true, user: clone(user) };
      },

      async recordMatchResult(userId, { won, rounds }) {
        const user = users.get(userId);
        if (!user) return null;
        user.stats.matchesPlayed += 1;
        user.stats.roundsPlayed += rounds || 0;
        if (won) user.stats.wins += 1;
        return clone(user);
      },

      async claimAdReward(userId, dayKey, cap, amount) {
        const user = users.get(userId);
        if (!user) return { ok: false, reason: 'USER_NOT_FOUND' };
        if (user.adRewards.day !== dayKey) {
          user.adRewards = { day: dayKey, count: 1 };
          user.coins += amount;
          return { ok: true, user: clone(user), countToday: 1 };
        }
        if (user.adRewards.count >= cap) {
          return { ok: false, reason: 'DAILY_AD_LIMIT', user: clone(user), countToday: user.adRewards.count };
        }
        user.adRewards.count += 1;
        user.coins += amount;
        return { ok: true, user: clone(user), countToday: user.adRewards.count };
      },

      async purchaseItem(userId, itemId, price) {
        const user = users.get(userId);
        if (!user) return { ok: false, reason: 'USER_NOT_FOUND' };
        if (user.ownedItems.includes(itemId)) {
          return { ok: false, reason: 'ALREADY_OWNED', user: clone(user) };
        }
        if (user.coins < price) {
          return { ok: false, reason: 'INSUFFICIENT_COINS', user: clone(user) };
        }
        user.coins -= price;
        user.ownedItems.push(itemId);
        return { ok: true, user: clone(user) };
      },
    },

    rooms: {
      async insert(room) {
        if (roomsByCode.has(room.roomCode)) return { ok: false, reason: 'DUPLICATE_CODE' };
        rooms.set(room._id, clone(room));
        roomsByCode.set(room.roomCode, room._id);
        return { ok: true, room: clone(room) };
      },
      async findById(roomId) {
        return clone(rooms.get(roomId));
      },
      async findByCode(code) {
        const id = roomsByCode.get(code);
        return id ? clone(rooms.get(id)) : undefined;
      },
      async replace(room) {
        if (!rooms.has(room._id)) return { ok: false, reason: 'ROOM_NOT_FOUND' };
        rooms.set(room._id, clone(room));
        return { ok: true };
      },
      async remove(roomId) {
        const room = rooms.get(roomId);
        if (!room) return { ok: false };
        rooms.delete(roomId);
        roomsByCode.delete(room.roomCode);
        return { ok: true };
      },
      async listAll() {
        return Array.from(rooms.values()).map(clone);
      },
      async removeExpired(cutoffIso) {
        let removed = 0;
        for (const room of Array.from(rooms.values())) {
          if (room.createdAt < cutoffIso) {
            rooms.delete(room._id);
            roomsByCode.delete(room.roomCode);
            removed += 1;
          }
        }
        return removed;
      },
    },

    matches: {
      async insert(match) {
        matches.push(clone(match));
        return { ok: true };
      },
      async listForUser(userId, limit = 20) {
        return matches
          .filter((m) => m.players.some((p) => p.userId === userId))
          .slice(-limit)
          .reverse()
          .map(clone);
      },
    },

    transactions: {
      async insert(tx) {
        transactions.push(clone(tx));
        return { ok: true };
      },
      async listForUser(userId, limit = 50) {
        return transactions
          .filter((t) => t.userId === userId)
          .slice(-limit)
          .reverse()
          .map(clone);
      },
      async sumForUser(userId) {
        return transactions.filter((t) => t.userId === userId).reduce((sum, t) => sum + t.amount, 0);
      },
    },
  };
}

module.exports = { createMemoryStore };
