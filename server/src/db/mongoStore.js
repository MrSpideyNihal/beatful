'use strict';

/**
 * MongoDB store.
 *
 * Every balance change is one conditional findOneAndUpdate, so two concurrent
 * requests can never both pass a "do you have enough coins" check. There is no
 * read then write anywhere in this file.
 *
 * TTL indexes on rooms.expiresAt and matches.expiresAt let mongo clean up after
 * itself, so there is no cleanup cron to forget about.
 */

const crypto = require('node:crypto');
const { MongoClient } = require('mongodb');

const config = require('../config');
const log = require('../lib/log');

function createMongoStore(uri = config.mongoUri, dbName = config.mongoDbName) {
  let client = null;
  let db = null;

  const collections = () => ({
    users: db.collection('users'),
    rooms: db.collection('rooms'),
    matches: db.collection('matches'),
    transactions: db.collection('transactions'),
  });

  const store = {
    kind: 'mongo',

    async init() {
      client = new MongoClient(uri, {
        serverSelectionTimeoutMS: 10000,
        maxPoolSize: 20,
        retryWrites: true,
      });
      await client.connect();
      db = client.db(dbName);
      const c = collections();
      await Promise.all([
        c.users.createIndex({ guestId: 1 }, { unique: true }),
        c.rooms.createIndex({ roomCode: 1 }, { unique: true }),
        c.rooms.createIndex({ expiresAt: 1 }, { expireAfterSeconds: 0 }),
        c.rooms.createIndex({ status: 1 }),
        c.matches.createIndex({ expiresAt: 1 }, { expireAfterSeconds: 0 }),
        c.matches.createIndex({ 'players.userId': 1, createdAt: -1 }),
        c.transactions.createIndex({ userId: 1, createdAt: -1 }),
      ]);
      log.info('mongo connected', { db: dbName });
      return store;
    },

    async close() {
      if (client) await client.close();
      client = null;
      db = null;
    },

    async health() {
      if (!db) return { ok: false, kind: 'mongo', reason: 'not connected' };
      await db.command({ ping: 1 });
      return { ok: true, kind: 'mongo' };
    },

    users: {
      async upsertGuest(guestId, defaults) {
        const c = collections();
        const now = new Date().toISOString();
        const user = await c.users.findOneAndUpdate(
          { guestId },
          {
            $setOnInsert: {
              _id: crypto.randomUUID(),
              guestId,
              displayName: defaults.displayName,
              avatarId: defaults.avatarId ?? 0,
              coins: defaults.coins ?? 0,
              stats: { wins: 0, matchesPlayed: 0, roundsPlayed: 0 },
              ownedItems: defaults.ownedItems ? defaults.ownedItems.slice() : [],
              selected: { cardBack: 'back_classic', table: 'table_green' },
              adRewards: { day: null, count: 0 },
              createdAt: now,
            },
          },
          { upsert: true, returnDocument: 'after' },
        );
        // createdAt is only ever written by the insert branch above, so matching
        // it tells us whether this call created the account.
        return { user, created: Boolean(user) && user.createdAt === now };
      },

      async findById(userId) {
        return collections().users.findOne({ _id: userId });
      },

      async listUsers({ query, limit = 50 } = {}) {
        const c = collections();
        let filter = {};
        if (query) {
          const regex = new RegExp(String(query).replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
          filter = {
            $or: [
              { _id: query },
              { displayName: { $regex: regex } }
            ]
          };
        }
        return c.users.find(filter).sort({ createdAt: -1 }).limit(limit).toArray();
      },

      async setProfile(userId, patch) {
        const set = {};
        if (patch.displayName !== undefined) set.displayName = patch.displayName;
        if (patch.avatarId !== undefined) set.avatarId = patch.avatarId;
        if (Object.keys(set).length === 0) return collections().users.findOne({ _id: userId });
        return collections().users.findOneAndUpdate({ _id: userId }, { $set: set }, { returnDocument: 'after' });
      },

      async setSelected(userId, kind, itemId) {
        return collections().users.findOneAndUpdate(
          { _id: userId },
          { $set: { [`selected.${kind}`]: itemId } },
          { returnDocument: 'after' },
        );
      },

      /**
       * Atomic balance change. The coins >= -delta guard is part of the filter,
       * so a deduction either happens once with a sufficient balance or does not
       * happen at all. Concurrent deductions cannot both succeed past zero.
       */
      async adjustCoins(userId, delta) {
        const filter = delta < 0 ? { _id: userId, coins: { $gte: -delta } } : { _id: userId };
        const updated = await collections().users.findOneAndUpdate(
          filter,
          { $inc: { coins: delta } },
          { returnDocument: 'after' },
        );
        if (updated) return { ok: true, user: updated };
        const exists = await collections().users.findOne({ _id: userId }, { projection: { coins: 1 } });
        if (!exists) return { ok: false, reason: 'USER_NOT_FOUND' };
        return { ok: false, reason: 'INSUFFICIENT_COINS', user: exists };
      },

      async recordMatchResult(userId, { won, rounds }) {
        return collections().users.findOneAndUpdate(
          { _id: userId },
          {
            $inc: {
              'stats.matchesPlayed': 1,
              'stats.roundsPlayed': rounds || 0,
              'stats.wins': won ? 1 : 0,
            },
          },
          { returnDocument: 'after' },
        );
      },

      /**
       * Daily capped reward in two conditional updates, never a read then write.
       * The first claims the first grant of a new day, the second increments an
       * existing day only while it is under the cap.
       */
      async claimAdReward(userId, dayKey, cap, amount) {
        const c = collections();
        const fresh = await c.users.findOneAndUpdate(
          { _id: userId, 'adRewards.day': { $ne: dayKey } },
          { $set: { adRewards: { day: dayKey, count: 1 } }, $inc: { coins: amount } },
          { returnDocument: 'after' },
        );
        if (fresh) return { ok: true, user: fresh, countToday: 1 };

        const bumped = await c.users.findOneAndUpdate(
          { _id: userId, 'adRewards.day': dayKey, 'adRewards.count': { $lt: cap } },
          { $inc: { 'adRewards.count': 1, coins: amount } },
          { returnDocument: 'after' },
        );
        if (bumped) return { ok: true, user: bumped, countToday: bumped.adRewards.count };

        const existing = await c.users.findOne({ _id: userId });
        if (!existing) return { ok: false, reason: 'USER_NOT_FOUND' };
        return {
          ok: false,
          reason: 'DAILY_AD_LIMIT',
          user: existing,
          countToday: existing.adRewards ? existing.adRewards.count : cap,
        };
      },

      async purchaseItem(userId, itemId, price) {
        const c = collections();
        const updated = await c.users.findOneAndUpdate(
          { _id: userId, coins: { $gte: price }, ownedItems: { $ne: itemId } },
          { $inc: { coins: -price }, $addToSet: { ownedItems: itemId } },
          { returnDocument: 'after' },
        );
        if (updated) return { ok: true, user: updated };
        const existing = await c.users.findOne({ _id: userId });
        if (!existing) return { ok: false, reason: 'USER_NOT_FOUND' };
        if (existing.ownedItems && existing.ownedItems.includes(itemId)) {
          return { ok: false, reason: 'ALREADY_OWNED', user: existing };
        }
        return { ok: false, reason: 'INSUFFICIENT_COINS', user: existing };
      },
    },

    rooms: {
      async insert(room) {
        try {
          await collections().rooms.insertOne(room);
          return { ok: true, room };
        } catch (err) {
          if (err && err.code === 11000) return { ok: false, reason: 'DUPLICATE_CODE' };
          throw err;
        }
      },
      async findById(roomId) {
        return collections().rooms.findOne({ _id: roomId });
      },
      async findByCode(code) {
        return collections().rooms.findOne({ roomCode: code });
      },
      async replace(room) {
        const result = await collections().rooms.replaceOne({ _id: room._id }, room, { upsert: false });
        if (result.matchedCount === 0) return { ok: false, reason: 'ROOM_NOT_FOUND' };
        return { ok: true };
      },
      async remove(roomId) {
        const result = await collections().rooms.deleteOne({ _id: roomId });
        return { ok: result.deletedCount > 0 };
      },
      async listAll() {
        return collections().rooms.find({}).toArray();
      },
      async removeExpired(cutoffIso) {
        const result = await collections().rooms.deleteMany({ createdAt: { $lt: cutoffIso } });
        return result.deletedCount;
      },
    },

    matches: {
      async insert(match) {
        await collections().matches.insertOne(match);
        return { ok: true };
      },
      async listForUser(userId, limit = 20) {
        return collections()
          .matches.find({ 'players.userId': userId })
          .sort({ createdAt: -1 })
          .limit(limit)
          .toArray();
      },
    },

    transactions: {
      async insert(tx) {
        await collections().transactions.insertOne(tx);
        return { ok: true };
      },
      async listForUser(userId, limit = 50) {
        return collections()
          .transactions.find({ userId })
          .sort({ createdAt: -1 })
          .limit(limit)
          .toArray();
      },
      async sumForUser(userId) {
        const rows = await collections()
          .transactions.aggregate([
            { $match: { userId } },
            { $group: { _id: null, total: { $sum: '$amount' } } },
          ])
          .toArray();
        return rows.length ? rows[0].total : 0;
      },
    },
  };

  return store;
}

module.exports = { createMongoStore };
