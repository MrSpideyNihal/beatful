'use strict';

/**
 * Guest auth middleware.
 *
 * Every route except /user/init and /health needs `Authorization: Bearer
 * <token>`. The token is verified with the server secret and then the user is
 * loaded from the database, so a token for a deleted user fails cleanly rather
 * than acting on a ghost account.
 */

const { apiError } = require('../lib/errors');
const { verifyToken } = require('../lib/token');
const { getStore } = require('../db');

function readBearer(req) {
  const header = req.get('authorization') || '';
  if (!header.toLowerCase().startsWith('bearer ')) return null;
  return header.slice(7).trim();
}

async function requireUser(req, res, next) {
  try {
    const token = readBearer(req);
    if (!token) throw apiError('UNAUTHORIZED');
    const claims = verifyToken(token);
    if (!claims) throw apiError('TOKEN_INVALID');
    const user = await getStore().users.findById(claims.userId);
    if (!user) throw apiError('TOKEN_INVALID');
    req.user = user;
    next();
  } catch (err) {
    next(err);
  }
}

module.exports = { requireUser, readBearer };
