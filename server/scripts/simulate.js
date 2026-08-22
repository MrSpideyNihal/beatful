'use strict';

/**
 * Bot versus bot simulation runner.
 *
 *   node scripts/simulate.js
 *   node scripts/simulate.js --rounds 500 --seats 4 --bots hard,medium,easy,easy
 *   node scripts/simulate.js --rounds 200 --seats 6 --timeouts 0.2 --seed 99
 *
 * Every round is verified against the rules module while it plays, so a non zero
 * exit code means an invariant broke, not that a particular seat lost.
 */

const simulate = require('../src/game/simulate');
const { DIFFICULTIES } = require('../src/game/bots');

function parseArgs(argv) {
  const out = { rounds: 200, seats: 4, bots: null, seed: 1, timeouts: 0, quiet: false };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case '--rounds':
        out.rounds = Number(next);
        i += 1;
        break;
      case '--seats':
        out.seats = Number(next);
        i += 1;
        break;
      case '--bots':
        out.bots = String(next || '').split(',').map((entry) => entry.trim()).filter(Boolean);
        i += 1;
        break;
      case '--seed':
        out.seed = Number(next);
        i += 1;
        break;
      case '--timeouts':
        out.timeouts = Number(next);
        i += 1;
        break;
      case '--quiet':
        out.quiet = true;
        break;
      case '--help':
        out.help = true;
        break;
      default:
        throw new Error(`unknown argument ${arg}`);
    }
  }
  return out;
}

function validate(args) {
  if (!Number.isInteger(args.rounds) || args.rounds < 1 || args.rounds > 100000) {
    throw new Error('--rounds must be 1 to 100000');
  }
  if (!Number.isInteger(args.seats) || args.seats < 2 || args.seats > 8) {
    throw new Error('--seats must be 2 to 8');
  }
  if (!Number.isFinite(args.timeouts) || args.timeouts < 0 || args.timeouts > 1) {
    throw new Error('--timeouts must be 0 to 1');
  }
  if (!Number.isFinite(args.seed)) throw new Error('--seed must be a number');
  if (args.bots) {
    for (const entry of args.bots) {
      if (!DIFFICULTIES.includes(entry)) {
        throw new Error(`unknown bot difficulty ${entry}, expected one of ${DIFFICULTIES.join(', ')}`);
      }
    }
  }
}

function pad(value, width) {
  return String(value).padStart(width, ' ');
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    process.stdout.write(
      [
        'usage: node scripts/simulate.js [options]',
        '  --rounds N     rounds to play, default 200',
        '  --seats N      2 to 8, default 4',
        '  --bots list    per seat difficulties, e.g. hard,medium,easy,easy',
        '  --seed N       starting seed, default 1',
        '  --timeouts R   0 to 1, share of turns resolved by the timer',
        '  --quiet        summary only',
        '',
      ].join('\n'),
    );
    return;
  }
  validate(args);

  const difficulties = [];
  for (let seat = 0; seat < args.seats; seat += 1) {
    difficulties.push(args.bots ? args.bots[seat % args.bots.length] : DIFFICULTIES[seat % DIFFICULTIES.length]);
  }

  const startedAt = Date.now();
  const batch = simulate.runBatch({
    rounds: args.rounds,
    seatCount: args.seats,
    difficulties,
    startSeed: args.seed,
    timeoutRatio: args.timeouts,
  });
  const elapsed = Date.now() - startedAt;

  const totals = batch.results.reduce(
    (acc, result) => ({
      plays: acc.plays + result.plays,
      passes: acc.passes + result.passes,
      auto: acc.auto + result.autoResolved,
      steps: acc.steps + result.steps,
    }),
    { plays: 0, passes: 0, auto: 0, steps: 0 },
  );

  const lines = [
    `rounds ${args.rounds}  seats ${args.seats}  timeouts ${args.timeouts}  seed ${args.seed}`,
    `plays ${totals.plays}  passes ${totals.passes}  timer resolved ${totals.auto}  ms ${elapsed}`,
    '',
    'seat  bot      wins    share',
  ];
  for (let seat = 0; seat < args.seats; seat += 1) {
    const wins = batch.wins[seat];
    const share = ((wins / args.rounds) * 100).toFixed(1);
    lines.push(`${pad(seat, 4)}  ${difficulties[seat].padEnd(7)} ${pad(wins, 5)}  ${pad(`${share}%`, 7)}`);
  }

  if (!args.quiet) {
    const averagePasses = (totals.passes / args.rounds).toFixed(1);
    lines.push('', `average passes per round ${averagePasses}`);
  }
  process.stdout.write(`${lines.join('\n')}\n`);
}

try {
  main();
} catch (err) {
  process.stderr.write(`simulation failed: ${err.message}\n`);
  process.exit(1);
}
