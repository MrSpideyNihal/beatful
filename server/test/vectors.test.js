'use strict';

/**
 * The checked in golden vectors must match this engine.
 *
 * The Dart port is tested against app/test/vectors/rules_vectors.json. That
 * catches drift on the client side, but only while the file itself is current,
 * so this test regenerates the vectors and fails when the file on disk differs.
 * A rules change therefore has to be regenerated and reviewed, not forgotten.
 */

const test = require('node:test');
const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const script = path.resolve(__dirname, '..', 'scripts', 'gen-vectors.js');
const vectorFile = path.resolve(__dirname, '..', '..', 'app', 'test', 'vectors', 'rules_vectors.json');

test('the golden vector file is up to date with the engine', () => {
  assert.ok(fs.existsSync(vectorFile), `${vectorFile} is missing, run npm run vectors`);
  let output;
  try {
    output = execFileSync(process.execPath, [script, '--check'], { encoding: 'utf8', stdio: 'pipe' });
  } catch (err) {
    assert.fail(`${err.stderr || err.message}`.trim());
  }
  assert.match(output, /vectors up to date/);
});

test('the golden vector file parses and carries every section', () => {
  const vectors = JSON.parse(fs.readFileSync(vectorFile, 'utf8'));
  assert.equal(vectors.formatVersion, 1);
  assert.equal(vectors.deck.length, 52);
  for (const section of [
    'rng',
    'shuffles',
    'dealCounts',
    'deals',
    'tables',
    'legalMoves',
    'invalidTables',
    'ranks',
    'standings',
    'botChoices',
    'publicViews',
    'transcripts',
  ]) {
    assert.ok(Array.isArray(vectors[section]) && vectors[section].length > 0, `empty section ${section}`);
  }
  // Every seat count the game supports has to be represented in the deals.
  const seatCounts = new Set(vectors.deals.map((entry) => entry.seatCount));
  for (let seats = 2; seats <= 8; seats += 1) assert.ok(seatCounts.has(seats), `no deal for ${seats} seats`);
  const transcriptSeats = new Set(vectors.transcripts.map((entry) => entry.seatCount));
  for (let seats = 2; seats <= 8; seats += 1) {
    assert.ok(transcriptSeats.has(seats), `no transcript for ${seats} seats`);
  }
});
