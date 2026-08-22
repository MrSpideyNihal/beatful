'use strict';

/**
 * Shop. Cosmetics only: card backs and table felts. Nothing sold here changes a
 * single rule of the game, so a paying player has no advantage over a free one.
 *
 * The catalog is static server side data. The client renders whatever it is
 * given, and a purchase is always priced from this table, never from the
 * request body.
 */

const { getStore } = require('../db');
const { apiError } = require('../lib/errors');
const coins = require('./coins');
const { publicUser } = require('./users');

const ITEMS = [
  {
    id: 'back_classic',
    kind: 'cardBack',
    name: 'Classic Blue',
    price: 0,
    palette: ['#2E6FF2', '#1B4FBF'],
    defaultOwned: true,
  },
  { id: 'back_sunrise', kind: 'cardBack', name: 'Sunrise', price: 200, palette: ['#F97316', '#B91C1C'] },
  { id: 'back_paisley', kind: 'cardBack', name: 'Paisley', price: 350, palette: ['#7C3AED', '#312E81'] },
  { id: 'back_mint', kind: 'cardBack', name: 'Fresh Mint', price: 500, palette: ['#10B981', '#065F46'] },
  {
    id: 'table_green',
    kind: 'table',
    name: 'Card Room Green',
    price: 0,
    palette: ['#14755C', '#0C5241'],
    defaultOwned: true,
  },
  { id: 'table_walnut', kind: 'table', name: 'Walnut', price: 250, palette: ['#7C4A21', '#3B1F0B'] },
  { id: 'table_slate', kind: 'table', name: 'Slate', price: 300, palette: ['#334155', '#0F172A'] },
  { id: 'table_marigold', kind: 'table', name: 'Marigold', price: 450, palette: ['#D97706', '#7C2D12'] },
];

const BY_ID = new Map(ITEMS.map((item) => [item.id, item]));

function defaultOwnedItems() {
  return ITEMS.filter((item) => item.defaultOwned).map((item) => item.id);
}

/** Catalog plus what this user already owns and has equipped. */
function catalogFor(user) {
  const owned = new Set([...(user.ownedItems || []), ...defaultOwnedItems()]);
  return {
    items: ITEMS.map((item) => ({
      id: item.id,
      kind: item.kind,
      name: item.name,
      price: item.price,
      palette: item.palette,
      owned: owned.has(item.id) || item.price === 0,
    })),
    coins: user.coins,
    selected: user.selected || { cardBack: 'back_classic', table: 'table_green' },
  };
}

async function purchase(userId, itemId) {
  const item = BY_ID.get(itemId);
  if (!item) throw apiError('ITEM_NOT_FOUND');
  if (item.price === 0) throw apiError('ALREADY_OWNED', 'That one is free and already yours.');

  const result = await getStore().users.purchaseItem(userId, itemId, item.price);
  if (!result.ok) {
    if (result.reason === 'ALREADY_OWNED') throw apiError('ALREADY_OWNED');
    if (result.reason === 'USER_NOT_FOUND') throw apiError('USER_NOT_FOUND');
    throw apiError('INSUFFICIENT_COINS');
  }
  await coins.recordTransaction({
    userId,
    type: coins.TYPES.SHOP_PURCHASE,
    amount: -item.price,
    balanceAfter: result.user.coins,
    itemId,
  });
  return { user: publicUser(result.user), item: { id: item.id, kind: item.kind, name: item.name } };
}

async function equip(userId, itemId) {
  const item = BY_ID.get(itemId);
  if (!item) throw apiError('ITEM_NOT_FOUND');
  const user = await getStore().users.findById(userId);
  if (!user) throw apiError('USER_NOT_FOUND');
  const owned = new Set([...(user.ownedItems || []), ...defaultOwnedItems()]);
  if (!owned.has(item.id)) throw apiError('FORBIDDEN', 'Buy it first, then you can use it.');
  const updated = await getStore().users.setSelected(userId, item.kind, item.id);
  return publicUser(updated);
}

module.exports = { ITEMS, BY_ID, catalogFor, purchase, equip, defaultOwnedItems };
