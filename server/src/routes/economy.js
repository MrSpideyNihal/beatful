'use strict';

const express = require('express');

const { asyncRoute } = require('../middleware/errors');
const { requireUser } = require('../middleware/auth');
const { rateLimit } = require('../middleware/rateLimit');
const validate = require('../lib/validate');
const shop = require('../services/shop');
const ads = require('../services/ads');

const router = express.Router();

router.get(
  '/shop/items',
  requireUser,
  asyncRoute(async (req, res) => {
    res.json(shop.catalogFor(req.user));
  }),
);

router.post(
  '/shop/purchase',
  requireUser,
  rateLimit({ name: 'shop_purchase', limit: 20, windowMs: 60_000 }),
  asyncRoute(async (req, res) => {
    const body = validate.requireObject(req.body);
    const itemId = validate.itemId(body.itemId);
    const result = await shop.purchase(req.user._id, itemId);
    res.json(result);
  }),
);

router.post(
  '/shop/equip',
  requireUser,
  rateLimit({ name: 'shop_equip', limit: 60, windowMs: 60_000 }),
  asyncRoute(async (req, res) => {
    const body = validate.requireObject(req.body);
    const itemId = validate.itemId(body.itemId);
    const user = await shop.equip(req.user._id, itemId);
    res.json({ user });
  }),
);

router.get(
  '/ads/status',
  requireUser,
  asyncRoute(async (req, res) => {
    res.json(await ads.status(req.user._id));
  }),
);

/**
 * Called after the device reports a completed rewarded ad view. The daily cap
 * lives in the database, so replaying this endpoint cannot mint coins beyond it.
 */
router.post(
  '/ads/reward',
  requireUser,
  rateLimit({ name: 'ads_reward', limit: 10, windowMs: 60_000 }),
  asyncRoute(async (req, res) => {
    res.json(await ads.claimReward(req.user._id));
  }),
);

module.exports = router;
