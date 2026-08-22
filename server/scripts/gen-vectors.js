'use strict';

/**
 * Golden vector generator.
 *
 * Solo play runs offline on the device, so the rules engine exists twice: once
 * here in Node, once as a Dart port in the Flutter client. This file is the
 * contract between them. Every value in the output comes from the Node engine,
 * and the Dart test suite replays all of it against the port, so the two cannot
 * drift apart without a test going red.
 *
 *   node scripts/gen-vectors.js            write the file
 *   node scripts/gen-vectors.js --check    exit 1 when the file is out of date
 *   node scripts/gen-vectors.js --out PATH write somewhere else
 *
 * Nothing in here may call Math.random. Every seed is fixed, so the output only
 * changes when the engine changes.
 */

const fs = require('node:fs');
const path = require('node:path');

const cards = require('../src/game/cards');
const rules = require('../src/game/rules');
const engine = require('../src/game/engine');
const bots = require('../src/game/bots');

const FORMAT_VERSION = 1;
const DEFAULT_OUT = path.resolve(__dirname, '..', '..', 'app', 'test', 'vectors', 'rules_vectors.json');

const RNG_SEEDS = [0, 1, 3, 3.7, -1, -5, 7, 42, 12345, 2147483647, 4294967295];
const SHUFFLE_SEEDS = [1, 2, 7, 99, 4242, 12345];
const DEAL_SEEDS = [1, 7, 12345];

/* ------------------------------------------------------------------ helpers */

function tableFrom(plays) {
  let table = rules.createTable();
  for (const card of plays) {
    table = rules.applyMove(table, card);
  }
  return table;
}

function suitSnapshot(table) {
  const out = {};
  for (const suit of cards.SUITS) {
    out[suit] = {
      open: rules.isSuitOpen(table, suit),
      complete: rules.isSuitComplete(table, suit),
      count: rules.suitCardCount(table, suit),
      needsAnchor: rules.needsAnchor(table, suit),
      nextNeeded: rules.nextNeeded(table, suit),
    };
  }
  return out;
}

/* ------------------------------------------------------------- rng and deal */

function buildRngVectors() {
  return RNG_SEEDS.map((seed) => {
    const next = cards.createRng(seed);
    const values = [];
    for (let i = 0; i < 12; i += 1) values.push(next());
    return { seed, values };
  });
}

function buildShuffleVectors() {
  return SHUFFLE_SEEDS.map((seed) => ({
    seed,
    deck: cards.shuffle(cards.buildDeck(), cards.createRng(seed)),
  }));
}

function buildDealCountVectors() {
  const out = [];
  for (let playerCount = 1; playerCount <= 8; playerCount += 1) {
    out.push({ playerCount, counts: rules.dealCounts(playerCount) });
  }
  return out;
}

/**
 * One entry per seed and seat count. The shuffled deck itself is not repeated
 * here because it depends only on the seed and is already in the shuffles
 * section, which covers every seed used below.
 */
function buildDealVectors() {
  const out = [];
  for (const seed of DEAL_SEEDS) {
    const deck = cards.shuffle(cards.buildDeck(), cards.createRng(seed));
    for (let seatCount = 2; seatCount <= 8; seatCount += 1) {
      const rawHands = rules.dealHands(deck, seatCount);
      const hands = rawHands.map((hand) => cards.sortHand(hand));
      out.push({
        seed,
        seatCount,
        rawHands,
        hands,
        startingSeat: engine.findStartingSeat(hands),
      });
    }
  }
  return out;
}

/* ------------------------------------------------------------------- tables */

const TABLE_FIXTURES = [
  { name: 'empty', plays: [] },
  { name: 'diamond_anchor', plays: ['D7'] },
  { name: 'diamond_run', plays: ['D7', 'D8', 'D6', 'D9'] },
  { name: 'heart_down_exhausted', plays: ['H7', 'H6', 'H5', 'H4', 'H3', 'H2', 'H1'] },
  { name: 'spade_up_exhausted', plays: ['S7', 'S8', 'S9', 'S10', 'S11', 'S12', 'S13'] },
  {
    name: 'club_complete',
    plays: ['C7', 'C8', 'C6', 'C9', 'C5', 'C10', 'C4', 'C11', 'C3', 'C12', 'C2', 'C13', 'C1'],
  },
  { name: 'all_anchors', plays: ['H7', 'D7', 'C7', 'S7'] },
  {
    name: 'mixed',
    plays: ['D7', 'D6', 'D8', 'H7', 'H8', 'H9', 'S7', 'S6', 'S5', 'C7', 'C8', 'D5', 'H10'],
  },
];

function buildTableVectors() {
  const deck = cards.buildDeck();
  return TABLE_FIXTURES.map((fixture) => {
    const table = tableFrom(fixture.plays);
    const legal = deck.filter((card) => rules.isLegalMove(table, card));
    const directions = {};
    for (const card of legal) directions[card] = rules.moveDirection(table, card);
    return {
      name: fixture.name,
      plays: fixture.plays,
      table,
      tableCards: rules.tableCardCount(table),
      valid: rules.isValidTable(table),
      legal,
      directions,
      suits: suitSnapshot(table),
    };
  });
}

/**
 * Hand order is preserved and duplicates collapse, both of which the client
 * relies on when it lays out the highlight ring, so they are pinned here.
 */
const LEGAL_MOVE_CASES = [
  { table: 'empty', hand: ['H1', 'H7', 'D13', 'S7'] },
  { table: 'empty', hand: ['H1', 'H2', 'D3'] },
  { table: 'diamond_run', hand: ['D10', 'D5', 'D7', 'D9', 'H7'] },
  { table: 'diamond_run', hand: ['D5', 'D10'] },
  { table: 'diamond_run', hand: ['D10', 'D5'] },
  { table: 'diamond_run', hand: ['D10', 'D10', 'D5', 'D5'] },
  { table: 'heart_down_exhausted', hand: ['H1', 'H2', 'H8', 'C7'] },
  { table: 'spade_up_exhausted', hand: ['S13', 'S6', 'S1'] },
  { table: 'club_complete', hand: ['C1', 'C7', 'C13'] },
  { table: 'mixed', hand: ['D4', 'D9', 'H6', 'H11', 'S4', 'S8', 'C9', 'C6', 'S13'] },
  { table: 'all_anchors', hand: [] },
];

function buildLegalMoveVectors() {
  const byName = new Map(TABLE_FIXTURES.map((fixture) => [fixture.name, tableFrom(fixture.plays)]));
  return LEGAL_MOVE_CASES.map((entry) => {
    const table = byName.get(entry.table);
    return {
      table: entry.table,
      hand: entry.hand,
      moves: rules.legalMoves(table, entry.hand),
      hasMove: rules.hasLegalMove(table, entry.hand),
    };
  });
}

/** Structurally broken tables the Dart port must also refuse. */
function buildInvalidTableVectors() {
  const base = () => rules.cloneTable(rules.createTable());
  const withSuit = (suit, pile) => {
    const table = base();
    table[suit] = pile;
    return table;
  };
  const missingSuit = base();
  delete missingSuit.S;
  return [
    { why: 'low set without high', table: withSuit('H', { low: 7, high: null }) },
    { why: 'high set without low', table: withSuit('H', { low: null, high: 7 }) },
    { why: 'low above the anchor', table: withSuit('D', { low: 8, high: 9 }) },
    { why: 'high below the anchor', table: withSuit('D', { low: 5, high: 6 }) },
    { why: 'low below ace', table: withSuit('C', { low: 0, high: 7 }) },
    { why: 'high above king', table: withSuit('C', { low: 7, high: 14 }) },
    { why: 'fractional rank', table: withSuit('S', { low: 6.5, high: 7 }) },
    { why: 'suit missing', table: missingSuit },
  ];
}

/* ------------------------------------------------------- ranks and standings */

const RANK_CASES = [
  [0, 5],
  [0, 3, 3],
  [0, 1, 2, 3],
  [0, 4, 4, 4],
  [0, 2, 2, 5, 7],
  [0, 0, 1],
  [0, 6, 6, 6, 6, 6, 6, 6],
  [0, 1, 1, 3, 3, 5, 5, 9],
  [0],
];

function buildRankVectors() {
  return RANK_CASES.map((handSizes) => ({ handSizes, ranks: rules.rankSeats(handSizes) }));
}

const SCORE_CASES = [
  [1, 2],
  [3, 1, 2],
  [4, 4, 1, 2],
  [2, 2, 2, 2],
  [6, 1, 3, 3, 5, 2],
];

function buildStandingVectors() {
  return SCORE_CASES.map((scores) => ({
    scores,
    standings: engine.matchStandings({ scores, seatCount: scores.length }),
  }));
}

/* --------------------------------------------------------------- transcripts */

const TRANSCRIPTS = [
  { seed: 1, seatCount: 2, difficulties: ['medium', 'medium'], captureViews: true },
  { seed: 12345, seatCount: 3, difficulties: ['easy', 'medium', 'hard'], captureViews: true },
  { seed: 7, seatCount: 4, difficulties: ['hard', 'hard', 'medium', 'easy'], sample: 5 },
  { seed: 99, seatCount: 4, difficulties: ['easy', 'easy', 'easy', 'easy'], timeoutRatio: 0.35 },
  { seed: 555, seatCount: 5, difficulties: ['hard', 'medium', 'easy', 'medium', 'hard'] },
  {
    seed: 2024,
    seatCount: 6,
    difficulties: ['medium', 'hard', 'easy', 'hard', 'medium', 'easy'],
    timeoutRatio: 0.2,
    sample: 7,
  },
  {
    seed: 31337,
    seatCount: 7,
    difficulties: ['hard', 'medium', 'easy', 'hard', 'medium', 'easy', 'hard'],
  },
  { seed: 424242, seatCount: 8, difficulties: new Array(8).fill('hard'), captureViews: true },
  { seed: 8080, seatCount: 2, difficulties: ['hard', 'easy'], rounds: 2, captureViews: true },
  { seed: 616, seatCount: 3, difficulties: ['medium', 'medium', 'medium'], timeoutRatio: 0.5 },
];

/**
 * Play one round with bots and record every step.
 *
 * The replay side does not reproduce the bot decisions: it applies the recorded
 * action through playCard or pass and checks the resulting table, hand counts
 * and turn against the recording. The auto flag is therefore informational, and
 * an auto pass replays as an ordinary pass because both require an empty legal
 * move set.
 */
function recordTranscript(spec) {
  const {
    seed,
    seatCount,
    difficulties,
    timerSeconds = 15,
    rounds = 1,
    timeoutRatio = 0,
    sample = 0,
    captureViews = false,
  } = spec;

  const rng = cards.createRng(seed);
  const state = engine.startRound({ seatCount, timerSeconds, rounds, seed, now: 0 });
  const hands = state.hands.map((hand) => hand.slice());
  const startingSeat = state.currentTurnSeat;
  const steps = [];
  const positions = [];
  const views = [];
  const maxSteps = 52 + seatCount * 60;
  let now = 0;

  const captureView = (at, label) => {
    if (!captureViews) return;
    for (let seat = 0; seat < seatCount; seat += 1) {
      views.push({
        seed,
        seatCount,
        label,
        seat,
        now: at,
        view: engine.publicView(state, seat, at),
      });
    }
    // A spectator has no seat, which the client renders as a read only board.
    views.push({ seed, seatCount, label, seat: null, now: at, view: engine.publicView(state, null, at) });
  };

  captureView(0, 'deal');

  for (let step = 0; step < maxSteps; step += 1) {
    if (state.status !== engine.STATUS.IN_PROGRESS) break;

    const seat = state.currentTurnSeat;
    if (state.hands[seat].length === 0) throw new Error('an empty seat was given the turn');
    if (rules.isDeadlocked(state.table, state.hands)) throw new Error('deadlock while cards remain');

    if (sample > 0 && step % sample === 0) {
      positions.push({
        table: rules.cloneTable(state.table),
        hand: state.hands[seat].slice(),
        handCounts: engine.handSizes(state),
        mySeat: seat,
      });
    }

    const useTimeout = timeoutRatio > 0 && rng() < timeoutRatio;
    const at = useTimeout ? state.turnStartedAt + state.timerSeconds * 1000 : now + 1000;
    now = at;

    let entry;
    if (useTimeout) {
      entry = engine.resolveTimeout(state, at, rng);
      if (!entry) throw new Error('timeout resolution did nothing');
    } else {
      const choice = bots.chooseMove(difficulties[seat], {
        table: state.table,
        hand: state.hands[seat].slice(),
        handCounts: engine.handSizes(state),
        mySeat: seat,
        rng,
      });
      entry = choice === null ? engine.pass(state, seat, at) : engine.playCard(state, seat, choice, at);
    }

    const inHands = state.hands.reduce((sum, hand) => sum + hand.length, 0);
    if (inHands + rules.tableCardCount(state.table) !== 52) throw new Error('card count drifted');
    if (!rules.isValidTable(state.table)) throw new Error('table left a valid state');

    steps.push({
      seat: entry.seatIndex,
      type: entry.type,
      card: entry.card || null,
      direction: entry.direction || null,
      auto: Boolean(entry.auto),
      at,
      table: rules.cloneTable(state.table),
      handCounts: engine.handSizes(state),
      turnSeat: state.currentTurnSeat,
      passStreak: state.passStreak,
      status: state.status,
    });

    if (steps.length === 3) captureView(now, 'midround');
  }

  if (state.status === engine.STATUS.IN_PROGRESS) throw new Error('round did not finish in budget');
  captureView(now, 'final');

  return {
    transcript: {
      seed,
      seatCount,
      timerSeconds,
      rounds,
      difficulties,
      timeoutRatio,
      hands,
      startingSeat,
      result: {
        status: state.status,
        winnerSeat: state.winnerSeat,
        ranks: state.ranks,
        cardsRemaining: engine.handSizes(state),
        scores: state.scores.slice(),
        tableCards: rules.tableCardCount(state.table),
        roundResults: state.roundResults,
      },
      steps,
    },
    positions,
    views,
  };
}

/* --------------------------------------------------------------- bot choices */

/**
 * Each case carries its own rng seed, so the Dart side builds a fresh generator
 * and must land on the same card. That pins the tie break arithmetic as well as
 * the strategy, which is what keeps a tuning change on one side from silently
 * making the two bot sets play differently.
 */
function buildBotChoiceVectors(positions) {
  const out = [];
  let counter = 0;
  for (const position of positions) {
    for (const difficulty of bots.DIFFICULTIES) {
      counter += 1;
      const rngSeed = 1000 + counter * 37;
      const choice = bots.chooseMove(difficulty, {
        table: rules.cloneTable(position.table),
        hand: position.hand.slice(),
        handCounts: position.handCounts.slice(),
        mySeat: position.mySeat,
        rng: cards.createRng(rngSeed),
      });
      out.push({
        difficulty,
        rngSeed,
        mySeat: position.mySeat,
        handCounts: position.handCounts,
        table: position.table,
        hand: position.hand,
        choice,
      });
    }
  }
  return out;
}

/* -------------------------------------------------------------------- build */

function build() {
  const deck = cards.buildDeck();
  const labels = {};
  for (const card of deck) labels[card] = cards.cardLabel(card);

  const transcripts = [];
  const positions = [];
  const publicViews = [];
  for (const spec of TRANSCRIPTS) {
    const recorded = recordTranscript(spec);
    transcripts.push(recorded.transcript);
    positions.push(...recorded.positions);
    publicViews.push(...recorded.views);
  }

  return {
    formatVersion: FORMAT_VERSION,
    generator: 'server/scripts/gen-vectors.js',
    note: 'Generated from the Node rules engine. Do not edit by hand, run npm run vectors in server.',
    constants: {
      suits: cards.SUITS,
      suitNames: cards.SUIT_NAMES,
      suitSymbols: cards.SUIT_SYMBOLS,
      rankLabels: cards.RANK_LABELS,
      minRank: cards.MIN_RANK,
      maxRank: cards.MAX_RANK,
      anchorRank: cards.ANCHOR_RANK,
      deckSize: cards.DECK_SIZE,
    },
    deck,
    labels,
    invalidCards: ['', 'H', 'H0', 'H14', 'H99', 'X7', 'h7', 'H07', 'H 7', 'HH', '7H', 'D013', 'D1.0', 'D+7'],
    rng: buildRngVectors(),
    shuffles: buildShuffleVectors(),
    dealCounts: buildDealCountVectors(),
    deals: buildDealVectors(),
    tables: buildTableVectors(),
    legalMoves: buildLegalMoveVectors(),
    invalidTables: buildInvalidTableVectors(),
    ranks: buildRankVectors(),
    standings: buildStandingVectors(),
    botChoices: buildBotChoiceVectors(positions),
    publicViews,
    transcripts,
  };
}

/* ------------------------------------------------------------------- verify */

function same(a, b) {
  return JSON.stringify(a) === JSON.stringify(b);
}

/**
 * Self check. Everything the Dart test will assert is asserted here first
 * against the same engine, so a broken generator fails loudly rather than
 * shipping vectors that pin the wrong behaviour.
 */
function verify(vectors) {
  const problems = [];
  const fail = (message) => problems.push(message);

  if (vectors.deck.length !== 52 || new Set(vectors.deck).size !== 52) fail('deck is not 52 unique cards');
  for (const code of vectors.invalidCards) {
    if (cards.isCard(code)) fail(`invalid card accepted: ${JSON.stringify(code)}`);
  }
  for (const entry of vectors.invalidTables) {
    if (rules.isValidTable(entry.table)) fail(`invalid table accepted: ${entry.why}`);
  }
  for (const entry of vectors.tables) {
    if (!rules.isValidTable(entry.table)) fail(`fixture ${entry.name} is not a valid table`);
    for (const card of vectors.deck) {
      const legal = entry.legal.includes(card);
      if (rules.isLegalMove(entry.table, card) !== legal) fail(`legality drift at ${entry.name} ${card}`);
    }
  }
  for (const entry of vectors.deals) {
    const total = entry.hands.reduce((sum, hand) => sum + hand.length, 0);
    if (total !== 52) fail(`deal for seed ${entry.seed} seats ${entry.seatCount} lost cards`);
    if (!same(entry.hands.map((hand) => hand.length), rules.dealCounts(entry.seatCount))) {
      fail(`deal sizes wrong for seats ${entry.seatCount}`);
    }
  }
  for (const entry of vectors.botChoices) {
    const options = rules.legalMoves(entry.table, entry.hand);
    if (entry.choice === null) {
      if (options.length > 0) fail(`${entry.difficulty} passed with ${options.length} legal moves`);
    } else if (!options.includes(entry.choice)) {
      fail(`${entry.difficulty} chose the illegal card ${entry.choice}`);
    }
  }

  for (const entry of vectors.publicViews) {
    const view = entry.view;
    const where = `view seed ${entry.seed} ${entry.label} seat ${entry.seat}`;
    if (JSON.stringify(view).includes('"hands"')) fail(`${where}: leaked the hands array`);
    if (entry.seat === null) {
      if (view.yourSeat !== null || view.yourHand.length > 0) fail(`${where}: spectator carries a hand`);
      continue;
    }
    if (view.yourSeat !== entry.seat) fail(`${where}: wrong seat`);
    if (view.yourHand.length !== view.handCounts[entry.seat]) fail(`${where}: hand length disagrees`);
    for (const card of view.yourLegalMoves) {
      if (!view.yourHand.includes(card)) fail(`${where}: legal move ${card} is not in the hand`);
      if (!rules.isLegalMove(view.table, card)) fail(`${where}: ${card} is not actually legal`);
    }
  }

  // Replay every transcript exactly the way the Dart test will.
  for (const transcript of vectors.transcripts) {
    const state = engine.startRound({
      seatCount: transcript.seatCount,
      timerSeconds: transcript.timerSeconds,
      rounds: transcript.rounds,
      seed: transcript.seed,
      now: 0,
    });
    if (!same(state.hands, transcript.hands)) fail(`replay seed ${transcript.seed}: hands differ`);
    if (state.currentTurnSeat !== transcript.startingSeat) {
      fail(`replay seed ${transcript.seed}: starting seat differs`);
    }
    transcript.steps.forEach((step, index) => {
      const where = `replay seed ${transcript.seed} step ${index}`;
      if (state.currentTurnSeat !== step.seat) fail(`${where}: wrong seat on turn`);
      if (step.type === 'play') {
        if (rules.moveDirection(state.table, step.card) !== step.direction) fail(`${where}: direction differs`);
        engine.playCard(state, step.seat, step.card, step.at);
      } else {
        engine.pass(state, step.seat, step.at);
      }
      if (!same(rules.cloneTable(state.table), step.table)) fail(`${where}: table differs`);
      if (!same(engine.handSizes(state), step.handCounts)) fail(`${where}: hand counts differ`);
      if (state.currentTurnSeat !== step.turnSeat) fail(`${where}: next seat differs`);
      if (state.passStreak !== step.passStreak) fail(`${where}: pass streak differs`);
      if (state.status !== step.status) fail(`${where}: status differs`);
    });
    if (state.winnerSeat !== transcript.result.winnerSeat) fail(`replay seed ${transcript.seed}: winner differs`);
    if (!same(state.scores, transcript.result.scores)) fail(`replay seed ${transcript.seed}: scores differ`);
    if (!same(engine.handSizes(state), transcript.result.cardsRemaining)) {
      fail(`replay seed ${transcript.seed}: cards remaining differ`);
    }
  }

  return problems;
}

/* ---------------------------------------------------------------- serialise */

/**
 * One record per line. The file is generated, but it still lands in git, and a
 * one line per case layout keeps a rules change reviewable in a diff.
 */
function serialiseTranscript(transcript) {
  const { steps, ...rest } = transcript;
  const head = JSON.stringify(rest);
  const rows = steps.map((step) => `   ${JSON.stringify(step)}`).join(',\n');
  const prefix = head === '{}' ? '{' : `${head.slice(0, -1)},`;
  return `${prefix}"steps":[\n${rows}\n  ]}`;
}

function serialise(vectors) {
  const parts = [];
  for (const [key, value] of Object.entries(vectors)) {
    const isRecordList =
      Array.isArray(value) && value.length > 0 && typeof value[0] === 'object' && value[0] !== null;
    if (key === 'transcripts') {
      const rows = value.map((entry) => `  ${serialiseTranscript(entry)}`).join(',\n');
      parts.push(`${JSON.stringify(key)}: [\n${rows}\n ]`);
    } else if (isRecordList) {
      const rows = value.map((entry) => `  ${JSON.stringify(entry)}`).join(',\n');
      parts.push(`${JSON.stringify(key)}: [\n${rows}\n ]`);
    } else {
      parts.push(`${JSON.stringify(key)}: ${JSON.stringify(value)}`);
    }
  }
  return `{\n ${parts.join(',\n ')}\n}\n`;
}

/* ------------------------------------------------------------------- runner */

function parseArgs(argv) {
  const out = { out: DEFAULT_OUT, check: false, help: false };
  for (let i = 0; i < argv.length; i += 1) {
    switch (argv[i]) {
      case '--out':
        if (!argv[i + 1]) throw new Error('--out needs a path');
        out.out = path.resolve(argv[i + 1]);
        i += 1;
        break;
      case '--check':
        out.check = true;
        break;
      case '--help':
        out.help = true;
        break;
      default:
        throw new Error(`unknown argument ${argv[i]}`);
    }
  }
  return out;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    process.stdout.write(
      [
        'usage: node scripts/gen-vectors.js [options]',
        '  --out PATH   output file, default app/test/vectors/rules_vectors.json',
        '  --check      do not write, exit 1 if the file on disk is out of date',
        '',
      ].join('\n'),
    );
    return;
  }

  const vectors = build();
  const problems = verify(vectors);
  if (problems.length > 0) {
    throw new Error(`self check failed:\n  ${problems.slice(0, 10).join('\n  ')}`);
  }

  const text = serialise(vectors);
  JSON.parse(text); // the file must parse as JSON, whatever the layout

  if (args.check) {
    const existing = fs.existsSync(args.out) ? fs.readFileSync(args.out, 'utf8') : null;
    if (existing !== text) {
      throw new Error(`${args.out} is out of date, run npm run vectors`);
    }
    process.stdout.write(`vectors up to date: ${args.out}\n`);
    return;
  }

  fs.mkdirSync(path.dirname(args.out), { recursive: true });
  fs.writeFileSync(args.out, text);

  const steps = vectors.transcripts.reduce((sum, entry) => sum + entry.steps.length, 0);
  process.stdout.write(
    [
      `wrote ${args.out}`,
      `  ${(text.length / 1024).toFixed(1)} kb, format version ${FORMAT_VERSION}`,
      `  ${vectors.rng.length} rng, ${vectors.shuffles.length} shuffles, ${vectors.deals.length} deals`,
      `  ${vectors.tables.length} tables, ${vectors.legalMoves.length} legal move cases, ${vectors.invalidTables.length} invalid tables`,
      `  ${vectors.ranks.length} rank cases, ${vectors.standings.length} standings, ${vectors.botChoices.length} bot choices`,
      `  ${vectors.publicViews.length} public views, ${vectors.transcripts.length} transcripts, ${steps} recorded steps`,
      '',
    ].join('\n'),
  );
}

try {
  main();
} catch (err) {
  process.stderr.write(`vector generation failed: ${err.message}\n`);
  process.exit(1);
}
