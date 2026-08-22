'use strict';

/**
 * Request error boundary.
 *
 * asyncRoute wraps every handler so a rejected promise cannot become an
 * unhandled rejection. errorHandler turns whatever comes out into the single
 * documented error shape, and logs enough context to find the room and user
 * without recording request bodies or tokens.
 */

const { toResponse, ApiError } = require('../lib/errors');
const log = require('../lib/log');

function asyncRoute(handler) {
  return function wrapped(req, res, next) {
    Promise.resolve()
      .then(() => handler(req, res, next))
      .catch(next);
  };
}

function notFound(req, res) {
  res.status(404).json({ error: 'NOT_FOUND', message: 'No such endpoint.' });
}

// eslint-disable-next-line no-unused-vars
function errorHandler(err, req, res, next) {
  const { status, body } = toResponse(err);
  const known = err instanceof ApiError || (err && err.name === 'GameError');

  const meta = {
    method: req.method,
    path: req.path,
    status,
    code: body.error,
    userId: req.user ? req.user._id : undefined,
    roomId: req.params && req.params.id ? req.params.id : undefined,
  };
  if (status >= 500 || !known) {
    log.error('request failed', { ...meta, err });
  } else {
    log.debug('request rejected', meta);
  }

  if (res.headersSent) {
    res.end();
    return;
  }
  res.status(status).json(body);
}

module.exports = { asyncRoute, errorHandler, notFound };
