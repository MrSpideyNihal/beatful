/// Wording tests.
///
/// Every line the board shows comes from narrate.dart, so the sentences a player
/// reads are checked here rather than by looking at a screen. Pure functions, no
/// widgets.
library;

import 'package:beatful/game/cards.dart' as cards;
import 'package:beatful/game/engine.dart' as engine;
import 'package:beatful/game/narrate.dart' as narrate;
import 'package:beatful/game/rules.dart' as rules;
import 'package:beatful/models/seat_info.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

const seats = <SeatInfo>[
  SeatInfo(index: 0, name: 'You', avatar: 0, isYou: true),
  SeatInfo(index: 1, name: 'Raj', avatar: 1, isBot: true),
  SeatInfo(index: 2, name: 'Akshay', avatar: 2, isBot: true),
  SeatInfo(index: 3, name: 'Piya', avatar: 3, isBot: true),
];

/// An unshuffled four seat deal: seat 0 holds every heart, seat 1 every diamond,
/// seat 2 every club, seat 3 every spade. Seat 1 opens, because it holds the
/// seven of diamonds.
engine.GameState fixedDeal() => engine.startRound(
  seatCount: 4,
  timerSeconds: 15,
  seed: 1,
  now: 1000,
  shuffled: false,
);

void main() {
  group('seat names', () {
    test('your own seat reads as You', () {
      expect(narrate.seatName(seats, 0), 'You');
    });

    test('other seats read as their name', () {
      expect(narrate.seatName(seats, 2), 'Akshay');
    });

    test('an unknown seat does not crash the sentence', () {
      expect(narrate.seatName(seats, null), 'Someone');
      expect(narrate.seatName(seats, 9), 'Someone');
      expect(narrate.seatName(seats, -1), 'Someone');
    });
  });

  group('describeLastAction', () {
    test('a fresh deal', () {
      final state = fixedDeal();
      final view = engine.publicView(state, 0, 1000);
      expect(narrate.describeLastAction(view, seats), 'Cards dealt');
    });

    test('a card somebody else played', () {
      final state = fixedDeal();
      engine.playCard(state, 1, 'D7', 2000);
      final view = engine.publicView(state, 0, 2000);
      expect(narrate.describeLastAction(view, seats), 'Raj played 7♦');
    });

    test('a card you played', () {
      final state = fixedDeal();
      engine.playCard(state, 1, 'D7', 2000);
      engine.playCard(state, 2, 'C7', 3000);
      engine.playCard(state, 3, 'S7', 4000);
      engine.playCard(state, 0, 'H7', 5000);
      final view = engine.publicView(state, 0, 5000);
      expect(narrate.describeLastAction(view, seats), 'You played 7♥');
    });

    test('a timed out turn says what was auto-played', () {
      final state = fixedDeal();
      // Only D7 is legal for seat 1, so the auto-play is deterministic.
      engine.resolveTimeout(state, 1000 + 15000, cards.createRng(7));
      final view = engine.publicView(state, 0, 16000);
      expect(
        narrate.describeLastAction(view, seats),
        "Raj's turn timed out - auto-played 7♦",
      );
    });

    test('a timed out turn with nothing to play says it passed', () {
      final view = buildView(
        currentTurnSeat: 2,
        lastAction: {'type': 'pass', 'at': 1, 'seatIndex': 1, 'auto': true},
      );
      expect(
        narrate.describeLastAction(view, seats),
        "Raj's turn timed out - nothing to play, passed",
      );
    });

    test('your own timed out turn uses Your', () {
      final view = buildView(
        lastAction: {'type': 'pass', 'at': 1, 'seatIndex': 0, 'auto': true},
      );
      expect(
        narrate.describeLastAction(view, seats),
        "Your turn timed out - nothing to play, passed",
      );
    });

    test('a deliberate pass', () {
      final view = buildView(
        lastAction: {'type': 'pass', 'at': 1, 'seatIndex': 3, 'auto': false},
      );
      expect(narrate.describeLastAction(view, seats), 'Piya passed');
    });

    test('the end of a round', () {
      final view = buildView(
        status: 'round_over',
        lastAction: {'type': 'round_over', 'at': 1, 'winnerSeat': 0},
      );
      expect(narrate.describeLastAction(view, seats), 'You won the round');
    });
  });

  group('turnPrompt', () {
    test('one playable card points at it', () {
      final view = buildView(
        yourHand: const ['H7', 'H9'],
        yourLegalMoves: const ['H7'],
      );
      expect(
        narrate.turnPrompt(view, seats),
        'Your turn. Tap the glowing card.',
      );
    });

    test('several playable cards say how many', () {
      final view = buildView(
        yourHand: const ['H6', 'H8', 'D7'],
        yourLegalMoves: const ['H6', 'H8', 'D7'],
      );
      expect(
        narrate.turnPrompt(view, seats),
        'Your turn. Tap one of the 3 glowing cards.',
      );
    });

    test('no playable card sends you to Pass', () {
      final view = buildView(yourHand: const ['H2'], canPass: true);
      expect(
        narrate.turnPrompt(view, seats),
        'No card you can play. Tap Pass.',
      );
    });

    test('somebody else is thinking', () {
      final view = buildView(currentTurnSeat: 2);
      expect(narrate.turnPrompt(view, seats), 'Waiting for Akshay');
    });

    test('between rounds', () {
      final view = buildView(status: 'round_over', round: 2, rounds: 3);
      expect(narrate.turnPrompt(view, seats), 'Round 2 of 3 finished');
    });

    test('match over', () {
      final view = buildView(status: 'finished');
      expect(narrate.turnPrompt(view, seats), 'Match over');
    });
  });

  group('explainIllegal', () {
    test('a closed suit asks for the seven', () {
      final table = rules.createTable();
      expect(
        narrate.explainIllegal(table, 'H9'),
        'Play the 7 of hearts first to open Hearts.',
      );
    });

    test('the seven of a closed suit is playable, so it says so', () {
      final table = rules.createTable();
      expect(
        narrate.explainIllegal(table, 'H7'),
        '7♥ can be played. Tap it again.',
      );
    });

    test('an open suit names both ranks it will take', () {
      final table = rules.applyMove(rules.createTable(), 'H7');
      expect(
        narrate.explainIllegal(table, 'H10'),
        'Hearts needs 6♥ or 8♥ next, not 10♥.',
      );
    });

    test('an exhausted side names only the open one', () {
      var table = rules.createTable();
      for (final card in ['H7', 'H6', 'H5', 'H4', 'H3', 'H2', 'H1']) {
        table = rules.applyMove(table, card);
      }
      expect(
        narrate.explainIllegal(table, 'H12'),
        'Hearts needs 8♥ next, not Q♥.',
      );
    });

    test('a finished suit says nothing more goes there', () {
      var table = rules.createTable();
      table = rules.applyMove(table, 'H7');
      for (var rank = 6; rank >= 1; rank -= 1) {
        table = rules.applyMove(table, 'H$rank');
      }
      for (var rank = 8; rank <= 13; rank += 1) {
        table = rules.applyMove(table, 'H$rank');
      }
      expect(
        narrate.explainIllegal(table, 'H5'),
        'Hearts is finished. Nothing more goes there.',
      );
    });

    test('junk is rejected without throwing', () {
      expect(
        narrate.explainIllegal(rules.createTable(), 'X9'),
        'That is not a card.',
      );
    });
  });

  group('round results', () {
    test('places read as ordinals', () {
      expect(narrate.placeLabel(1), '1st');
      expect(narrate.placeLabel(2), '2nd');
      expect(narrate.placeLabel(3), '3rd');
      expect(narrate.placeLabel(4), '4th');
      expect(narrate.placeLabel(11), '11th');
    });

    test('the winner went out, the rest count their cards', () {
      final view = buildView(
        status: 'round_over',
        handCounts: const [0, 1, 4, 4],
        ranks: const [1, 2, 3, 3],
      );
      expect(narrate.roundLine(view, seats, 0), '1st, went out');
      expect(narrate.roundLine(view, seats, 1), '2nd, 1 card left');
      expect(narrate.roundLine(view, seats, 2), '3rd, 4 cards left');
    });

    test('a view with no ranking yields an empty line', () {
      expect(narrate.roundLine(buildView(), seats, 0), '');
    });
  });

  group('screen reader labels', () {
    test('a playable card says it can be played', () {
      expect(
        narrate.cardSemantics('H1', playable: true),
        'ace of hearts, can be played',
      );
    });

    test('a card that is not playable says why not in short', () {
      expect(
        narrate.cardSemantics('S13', playable: false),
        'king of spades, cannot be played yet',
      );
    });
  });

  group('error messages', () {
    test('every engine error code has a sentence of its own', () {
      const codes = [
        'NOT_YOUR_TURN',
        'MUST_PLAY',
        'ILLEGAL_MOVE',
        'CARD_NOT_IN_HAND',
        'ROUND_NOT_ACTIVE',
        'BAD_CARD',
        'ROOM_NOT_FOUND',
        'ROOM_FULL',
        'ROOM_STARTED',
        'NOT_A_MEMBER',
        'NOT_HOST',
        'NOT_ENOUGH_COINS',
        'RATE_LIMITED',
        'OFFLINE',
        'TIMEOUT',
      ];
      final seen = <String>{};
      for (final code in codes) {
        final message = narrate.errorMessage(code);
        expect(
          message,
          isNot('Something went wrong. Try again.'),
          reason: code,
        );
        expect(
          seen.add(message),
          isTrue,
          reason: 'duplicate wording for $code',
        );
      }
    });

    test('an unknown code still says something useful', () {
      expect(narrate.errorMessage('WAT'), 'Something went wrong. Try again.');
      expect(narrate.errorMessage(null), 'Something went wrong. Try again.');
    });
  });

  test('no message contains an em dash', () {
    final strings = <String>[
      for (final seat in [0, 1, 2, 3])
        narrate.roundLine(
          buildView(
            status: 'round_over',
            handCounts: const [0, 1, 4, 4],
            ranks: const [1, 2, 3, 3],
          ),
          seats,
          seat,
        ),
      narrate.explainIllegal(rules.createTable(), 'H9'),
      narrate.errorMessage('MUST_PLAY'),
      narrate.describeLastAction(
        buildView(
          lastAction: {'type': 'pass', 'at': 1, 'seatIndex': 1, 'auto': true},
        ),
        seats,
      )!,
    ];
    for (final line in strings) {
      expect(line.contains('—'), isFalse, reason: line);
      expect(line.contains('–'), isFalse, reason: line);
    }
  });
}
