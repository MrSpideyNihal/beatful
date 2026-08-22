/// The Dart engine against golden vectors from the Node engine.
///
/// Solo play runs offline, so the rules exist in both languages. Everything in
/// test/vectors/rules_vectors.json was produced by server/src/game, and every
/// case below re-derives it here. If the two ever disagree, whichever side moved
/// is wrong, and the fix is to make them match and regenerate the file with
/// `npm run vectors` in server.
library;

import 'dart:convert';
import 'dart:io';

import 'package:beatful/game/bots.dart' as bots;
import 'package:beatful/game/cards.dart' as cards;
import 'package:beatful/game/engine.dart' as engine;
import 'package:beatful/game/rules.dart' as rules;
import 'package:flutter_test/flutter_test.dart';

late final Map<String, dynamic> vectors;

List<Map<String, dynamic>> section(String name) =>
    (vectors[name] as List).cast<Map<String, dynamic>>();

List<String> stringList(Object? value) => (value as List).cast<String>();

List<int> intList(Object? value) => [
  for (final entry in value as List) (entry as num).toInt(),
];

rules.TableState tableFromPlays(List<String> plays) {
  var table = rules.createTable();
  for (final card in plays) {
    table = rules.applyMove(table, card);
  }
  return table;
}

void main() {
  setUpAll(() {
    final file = File('test/vectors/rules_vectors.json');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'run "npm run vectors" in server to generate ${file.path}',
    );
    vectors = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(
      vectors['formatVersion'],
      1,
      reason: 'vector format changed, update this test',
    );
  });

  group('constants', () {
    test('suits, ranks and deck size match', () {
      final constants = vectors['constants'] as Map<String, dynamic>;
      expect(cards.suits, stringList(constants['suits']));
      expect(cards.minRank, constants['minRank']);
      expect(cards.maxRank, constants['maxRank']);
      expect(cards.anchorRank, constants['anchorRank']);
      expect(cards.deckSize, constants['deckSize']);
      final labels = (constants['rankLabels'] as Map).cast<String, String>();
      for (final entry in labels.entries) {
        expect(cards.rankLabels[int.parse(entry.key)], entry.value);
      }
      final symbols = (constants['suitSymbols'] as Map).cast<String, String>();
      expect(cards.suitSymbols, symbols);
      expect(
        cards.suitNames,
        (constants['suitNames'] as Map).cast<String, String>(),
      );
    });

    test('the deck is built in the same order', () {
      expect(cards.buildDeck(), stringList(vectors['deck']));
    });

    test('every card label matches', () {
      final labels = (vectors['labels'] as Map).cast<String, String>();
      expect(labels.length, 52);
      for (final entry in labels.entries) {
        expect(cards.cardLabel(entry.key), entry.value, reason: entry.key);
      }
    });

    test('malformed codes are refused', () {
      for (final code in stringList(vectors['invalidCards'])) {
        expect(
          cards.isCard(code),
          isFalse,
          reason: 'accepted ${jsonEncode(code)}',
        );
      }
      for (final code in cards.buildDeck()) {
        expect(cards.isCard(code), isTrue, reason: code);
      }
    });

    test('every card has an image in the bundle', () {
      for (final code in cards.buildDeck()) {
        final path = cards.cardImageAsset(code);
        expect(File(path).existsSync(), isTrue, reason: '$code needs $path');
      }
    });
  });

  group('random', () {
    test('the generator produces identical streams', () {
      for (final entry in section('rng')) {
        final rng = cards.createRng(entry['seed'] as num);
        final expected = entry['values'] as List;
        for (var i = 0; i < expected.length; i += 1) {
          expect(
            rng(),
            (expected[i] as num).toDouble(),
            reason: 'seed ${entry['seed']} value $i',
          );
        }
      }
    });

    test('shuffles land in the same order', () {
      for (final entry in section('shuffles')) {
        final shuffled = cards.shuffle(
          cards.buildDeck(),
          cards.createRng(entry['seed'] as num),
        );
        expect(
          shuffled,
          stringList(entry['deck']),
          reason: 'seed ${entry['seed']}',
        );
      }
    });
  });

  group('dealing', () {
    test('hand sizes split the deck the same way', () {
      for (final entry in section('dealCounts')) {
        final counts = rules.dealCounts(entry['playerCount'] as int);
        expect(
          counts,
          intList(entry['counts']),
          reason: '${entry['playerCount']} players',
        );
        expect(counts.reduce((a, b) => a + b), 52);
      }
    });

    test('deals and the opening seat match', () {
      final decks = {
        for (final entry in section('shuffles'))
          entry['seed'] as num: stringList(entry['deck']),
      };
      for (final entry in section('deals')) {
        final deck = decks[entry['seed'] as num];
        expect(
          deck,
          isNotNull,
          reason: 'no recorded shuffle for seed ${entry['seed']}',
        );
        final seatCount = entry['seatCount'] as int;
        final where = 'seed ${entry['seed']} seats $seatCount';
        final raw = rules.dealHands(deck!, seatCount);
        expect(
          raw,
          (entry['rawHands'] as List).map(stringList).toList(),
          reason: where,
        );
        final sorted = raw.map(cards.sortHand).toList();
        expect(
          sorted,
          (entry['hands'] as List).map(stringList).toList(),
          reason: where,
        );
        expect(
          engine.findStartingSeat(sorted),
          entry['startingSeat'],
          reason: where,
        );
      }
    });
  });

  group('table', () {
    test('fixtures build to the same table and legality', () {
      final deck = cards.buildDeck();
      for (final entry in section('tables')) {
        final where = entry['name'] as String;
        final table = tableFromPlays(stringList(entry['plays']));
        expect(table.toJson(), entry['table'], reason: where);
        expect(rules.tableCardCount(table), entry['tableCards'], reason: where);
        expect(rules.isValidTable(table.toJson()), isTrue, reason: where);

        final legal = stringList(entry['legal']);
        for (final card in deck) {
          expect(
            rules.isLegalMove(table, card),
            legal.contains(card),
            reason: '$where $card',
          );
        }
        final directions = (entry['directions'] as Map).cast<String, String>();
        for (final card in legal) {
          expect(
            rules.moveDirection(table, card)?.wire,
            directions[card],
            reason: '$where $card',
          );
        }

        final suitInfo = (entry['suits'] as Map).cast<String, dynamic>();
        for (final suit in cards.suits) {
          final expected = suitInfo[suit] as Map<String, dynamic>;
          final label = '$where $suit';
          expect(
            rules.isSuitOpen(table, suit),
            expected['open'],
            reason: label,
          );
          expect(
            rules.isSuitComplete(table, suit),
            expected['complete'],
            reason: label,
          );
          expect(
            rules.suitCardCount(table, suit),
            expected['count'],
            reason: label,
          );
          expect(
            rules.needsAnchor(table, suit),
            expected['needsAnchor'],
            reason: label,
          );
          final needed = rules.nextNeeded(table, suit);
          final expectedNeeded = expected['nextNeeded'] as Map<String, dynamic>;
          expect(needed.down, expectedNeeded['down'], reason: '$label down');
          expect(needed.up, expectedNeeded['up'], reason: '$label up');
        }
      }
    });

    test('legal move lists keep hand order and drop duplicates', () {
      final tables = {
        for (final entry in section('tables'))
          entry['name'] as String: tableFromPlays(stringList(entry['plays'])),
      };
      for (final entry in section('legalMoves')) {
        final table = tables[entry['table'] as String]!;
        final hand = stringList(entry['hand']);
        final where = '${entry['table']} ${hand.join(',')}';
        expect(
          rules.legalMoves(table, hand),
          stringList(entry['moves']),
          reason: where,
        );
        expect(
          rules.hasLegalMove(table, hand),
          entry['hasMove'],
          reason: where,
        );
      }
    });

    test('broken tables are refused', () {
      for (final entry in section('invalidTables')) {
        expect(
          rules.isValidTable(entry['table']),
          isFalse,
          reason: entry['why'] as String,
        );
      }
    });
  });

  group('scoring', () {
    test('round ranks match', () {
      for (final entry in section('ranks')) {
        final sizes = intList(entry['handSizes']);
        expect(
          rules.rankSeats(sizes),
          intList(entry['ranks']),
          reason: sizes.join(','),
        );
      }
    });

    test('match standings match', () {
      for (final entry in section('standings')) {
        final scores = intList(entry['scores']);
        final standings = engine.computeStandings(scores);
        expect(
          [for (final standing in standings) standing.toJson()],
          entry['standings'],
          reason: scores.join(','),
        );
      }
    });
  });

  group('bots', () {
    test('every tier picks the same card from the same position', () {
      for (final entry in section('botChoices')) {
        final table = rules.TableState.fromJson(entry['table']);
        final hand = stringList(entry['hand']);
        final choice = bots.chooseMove(
          bots.BotDifficulty.fromWire(entry['difficulty']),
          bots.BotContext(
            table: table,
            hand: hand,
            handCounts: intList(entry['handCounts']),
            mySeat: entry['mySeat'] as int,
            rng: cards.createRng(entry['rngSeed'] as num),
          ),
        );
        expect(
          choice,
          entry['choice'],
          reason:
              '${entry['difficulty']} seed ${entry['rngSeed']} hand ${hand.join(',')}',
        );
      }
    });
  });

  group('public view', () {
    test('a locally built view equals the recorded server view', () {
      for (final entry in section('publicViews')) {
        final where =
            'seed ${entry['seed']} ${entry['label']} seat ${entry['seat']}';
        final recorded = entry['view'] as Map<String, dynamic>;

        // Rebuild the same position, then compare field for field.
        final state = replayTo(entry['seed'] as int, entry['label'] as String);
        final view = engine.publicView(
          state,
          entry['seat'] as int?,
          entry['now'] as int,
        );
        expect(view.toJson(), recorded, reason: where);

        // The same payload has to survive a round trip through the wire parser.
        final parsed = engine.PublicView.fromJson(recorded);
        expect(parsed.toJson(), recorded, reason: '$where reparsed');
        expect(parsed.table, view.table, reason: '$where table');
        expect(parsed.isMyTurn, view.isMyTurn, reason: '$where turn');
        expect(parsed.canPass, view.canPass, reason: '$where pass');
      }
    });

    test('no view carries another seat cards', () {
      for (final entry in section('publicViews')) {
        final view = engine.PublicView.fromJson(
          entry['view'] as Map<String, dynamic>,
        );
        final seat = entry['seat'] as int?;
        if (seat == null) {
          expect(view.yourSeat, isNull);
          expect(view.yourHand, isEmpty);
          expect(view.canPass, isFalse);
          continue;
        }
        expect(view.yourSeat, seat);
        expect(view.yourHand.length, view.handCounts[seat]);
        for (final card in view.yourLegalMoves) {
          expect(view.yourHand, contains(card));
          expect(rules.isLegalMove(view.table, card), isTrue);
        }
      }
    });
  });

  group('transcripts', () {
    test('every recorded round replays move for move', () {
      for (final transcript in section('transcripts')) {
        final seed = transcript['seed'] as int;
        final where = 'seed $seed';
        final state = engine.startRound(
          seatCount: transcript['seatCount'] as int,
          timerSeconds: transcript['timerSeconds'] as int,
          rounds: transcript['rounds'] as int,
          seed: seed,
          now: 0,
        );
        expect(
          state.hands,
          (transcript['hands'] as List).map(stringList).toList(),
          reason: where,
        );
        expect(
          state.currentTurnSeat,
          transcript['startingSeat'],
          reason: where,
        );

        final steps = (transcript['steps'] as List)
            .cast<Map<String, dynamic>>();
        for (var index = 0; index < steps.length; index += 1) {
          final step = steps[index];
          final at = step['at'] as int;
          final seat = step['seat'] as int;
          final label = '$where step $index';
          expect(state.currentTurnSeat, seat, reason: '$label seat');

          if (step['type'] == 'play') {
            final card = step['card'] as String;
            expect(
              rules.moveDirection(state.table, card)?.wire,
              step['direction'],
              reason: label,
            );
            final entry = engine.playCard(state, seat, card, at);
            expect(entry.card, card, reason: label);
          } else {
            // An auto pass replays as an ordinary pass: both need an empty legal
            // move set, which is exactly what the engine checks.
            engine.pass(state, seat, at);
          }

          expect(state.table.toJson(), step['table'], reason: '$label table');
          expect(
            engine.handSizes(state),
            intList(step['handCounts']),
            reason: '$label counts',
          );
          expect(
            state.currentTurnSeat,
            step['turnSeat'],
            reason: '$label next seat',
          );
          expect(
            state.passStreak,
            step['passStreak'],
            reason: '$label pass streak',
          );
          expect(state.status.wire, step['status'], reason: '$label status');
          if (state.status == engine.GameStatus.inProgress) {
            // The next seat timer starts the moment the action lands. Once the
            // round is over the clock stops instead of rolling forward.
            expect(state.turnStartedAt, at, reason: '$label turn clock');
          }
        }

        final result = transcript['result'] as Map<String, dynamic>;
        expect(state.status.wire, result['status'], reason: where);
        expect(state.winnerSeat, result['winnerSeat'], reason: where);
        expect(state.ranks, intList(result['ranks']), reason: where);
        expect(
          engine.handSizes(state),
          intList(result['cardsRemaining']),
          reason: where,
        );
        expect(state.scores, intList(result['scores']), reason: where);
        expect(
          rules.tableCardCount(state.table),
          result['tableCards'],
          reason: where,
        );
        expect(
          [for (final round in state.roundResults) round.toJson()],
          result['roundResults'],
          reason: where,
        );
        expect(
          state.hands[state.winnerSeat!],
          isEmpty,
          reason: '$where winner still holds cards',
        );
      }
    });

    test('a hand never gains or loses a card', () {
      for (final transcript in section('transcripts')) {
        final seatCount = transcript['seatCount'] as int;
        for (final step
            in (transcript['steps'] as List).cast<Map<String, dynamic>>()) {
          final counts = intList(step['handCounts']);
          final table = rules.TableState.fromJson(step['table']);
          expect(counts.length, seatCount);
          expect(
            counts.reduce((a, b) => a + b) + rules.tableCardCount(table),
            52,
            reason: 'seed ${transcript['seed']} lost a card',
          );
        }
      }
    });
  });
}

/// Replay a recorded transcript up to the point a public view was captured.
engine.GameState replayTo(int seed, String label) {
  final transcript = section(
    'transcripts',
  ).firstWhere((entry) => entry['seed'] == seed);
  final state = engine.startRound(
    seatCount: transcript['seatCount'] as int,
    timerSeconds: transcript['timerSeconds'] as int,
    rounds: transcript['rounds'] as int,
    seed: seed,
    now: 0,
  );
  if (label == 'deal') return state;

  final steps = (transcript['steps'] as List).cast<Map<String, dynamic>>();
  final limit = label == 'midround' ? 3 : steps.length;
  for (var index = 0; index < limit; index += 1) {
    final step = steps[index];
    final at = step['at'] as int;
    final seat = step['seat'] as int;
    if (step['type'] == 'play') {
      engine.playCard(state, seat, step['card'] as String, at);
    } else {
      engine.pass(state, seat, at);
    }
  }
  return state;
}
