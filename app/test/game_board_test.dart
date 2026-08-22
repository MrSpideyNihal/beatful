/// Board tests.
///
/// The board is the part a player touches, so these check the things that would
/// ruin a match if they broke: a legal card plays, an illegal one does not, Pass
/// only fires on your own turn, a card played anywhere flies to the table, and the
/// round end panel arrives with a readable ranking.
library;

import 'package:beatful/models/cosmetics.dart';
import 'package:beatful/screens/game_screen.dart';
import 'package:beatful/state/cosmetics.dart';
import 'package:beatful/widgets/anim.dart';
import 'package:beatful/widgets/round_over_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  // The board reads the equipped table and card back from providers. They are
  // pinned to the free defaults here so these tests stay about the board and
  // never reach for an account.
  Widget wrap(Widget child) => ProviderScope(
    overrides: [
      equippedCardBackProvider.overrideWithValue(cardBackSkin(null)),
      equippedTableProvider.overrideWithValue(tableSkin(null)),
    ],
    child: MaterialApp(
      home: Scaffold(body: SafeArea(child: child)),
    ),
  );

  testWidgets('a legal card plays and an illegal one is refused', (
    tester,
  ) async {
    usePhoneSurface(tester);
    final played = <String>[];
    final refused = <String>[];

    await tester.pumpWidget(
      wrap(
        GameBoard(
          header: const SizedBox.shrink(),
          view: buildView(
            handCounts: const [2, 13, 13, 13],
            yourHand: const ['H7', 'H9'],
            yourLegalMoves: const ['H7'],
            lastAction: const {'type': 'deal', 'at': 0, 'round': 1},
          ),
          seats: testSeats(),
          onPlay: played.add,
          onPass: () {},
          onRefused: refused.add,
        ),
      ),
    );
    // Past the deal stagger, so a card is where it will be when tapped.
    await settle(tester);

    expect(find.text('Your turn. Tap the glowing card.'), findsOneWidget);
    expect(find.text('Your cards: 2'), findsOneWidget);
    expect(find.text('1 playable'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('card-H7')));
    expect(played, ['H7']);
    expect(refused, isEmpty);

    await tester.tap(find.byKey(const ValueKey('card-H9')));
    expect(played, ['H7']);
    expect(refused, ['H9']);

    await unmount(tester);
  });

  testWidgets('Pass does nothing when it is not your turn', (tester) async {
    usePhoneSurface(tester);
    var passes = 0;

    await tester.pumpWidget(
      wrap(
        GameBoard(
          header: const SizedBox.shrink(),
          view: buildView(
            currentTurnSeat: 2,
            yourHand: const ['H7'],
            lastAction: const {'type': 'deal', 'at': 0, 'round': 1},
          ),
          seats: testSeats(),
          onPlay: (_) {},
          onPass: () => passes += 1,
          onRefused: (_) {},
        ),
      ),
    );
    await settle(tester);

    expect(find.text('Waiting for Bot 2'), findsOneWidget);
    await tester.tap(find.text('Pass'), warnIfMissed: false);
    await tester.pump();
    expect(passes, 0);

    await unmount(tester);
  });

  testWidgets('Pass fires on your turn, and warns while a card is playable', (
    tester,
  ) async {
    usePhoneSurface(tester);
    var passes = 0;

    Widget board({required List<String> legal}) => wrap(
      GameBoard(
        header: const SizedBox.shrink(),
        view: buildView(
          yourHand: const ['H7'],
          yourLegalMoves: legal,
          canPass: legal.isEmpty,
          lastAction: const {'type': 'deal', 'at': 0, 'round': 1},
        ),
        seats: testSeats(),
        onPlay: (_) {},
        onPass: () => passes += 1,
        onRefused: (_) {},
      ),
    );

    await tester.pumpWidget(board(legal: const ['H7']));
    await settle(tester);
    // Enabled, but it says out loud that passing is not the move.
    expect(find.text('You still have a card to play'), findsOneWidget);
    await tester.tap(find.text('Pass'));
    expect(passes, 1);

    await tester.pumpWidget(board(legal: const []));
    await settle(tester);
    expect(find.text('No card you can play. Tap Pass.'), findsOneWidget);
    expect(find.text('Nothing playable'), findsOneWidget);
    await tester.tap(find.text('Pass'));
    expect(passes, 2);

    await unmount(tester);
  });

  testWidgets('a card played by another seat flies to the table', (
    tester,
  ) async {
    usePhoneSurface(tester);
    Widget board({
      required Map<String, Object?> table,
      required Map<String, Object?>? lastAction,
    }) => wrap(
      GameBoard(
        header: const SizedBox.shrink(),
        view: buildView(
          currentTurnSeat: 2,
          table: table,
          handCounts: const [13, 12, 13, 13],
          yourHand: const ['H2', 'H3'],
          lastAction: lastAction,
        ),
        seats: testSeats(),
        onPlay: (_) {},
        onPass: () {},
        onRefused: (_) {},
      ),
    );

    await tester.pumpWidget(
      board(
        table: const {},
        lastAction: const {'type': 'deal', 'at': 0, 'round': 1},
      ),
    );
    await settle(tester);
    expect(find.byType(CardFlight), findsNothing);

    await tester.pumpWidget(
      board(
        table: {'D': pile(7, 7)},
        lastAction: const {
          'type': 'play',
          'at': 2000,
          'seatIndex': 1,
          'card': 'D7',
          'direction': 'anchor',
          'auto': false,
        },
      ),
    );
    // One frame to measure the row, one for the flight to appear.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(CardFlight), findsOneWidget);

    await tester.pump(Anim.flight);
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(CardFlight), findsNothing);

    await unmount(tester);
  });

  testWidgets('a timed out play says so on the seat that lost the turn', (
    tester,
  ) async {
    usePhoneSurface(tester);
    Widget board({required Map<String, Object?>? lastAction}) => wrap(
      GameBoard(
        header: const SizedBox.shrink(),
        view: buildView(
          currentTurnSeat: 2,
          table: lastAction?['card'] == null ? const {} : {'D': pile(7, 7)},
          yourHand: const ['H2'],
          lastAction: lastAction,
        ),
        seats: testSeats(),
        onPlay: (_) {},
        onPass: () {},
        onRefused: (_) {},
      ),
    );

    await tester.pumpWidget(
      board(lastAction: const {'type': 'deal', 'at': 0, 'round': 1}),
    );
    await settle(tester);

    await tester.pumpWidget(
      board(
        lastAction: const {
          'type': 'play',
          'at': 3000,
          'seatIndex': 1,
          'card': 'D7',
          'direction': 'anchor',
          'auto': true,
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.text('Timed out'), findsOneWidget);
    expect(
      find.text("Bot 1's turn timed out - auto-played 7♦"),
      findsOneWidget,
    );

    await unmount(tester);
  });

  testWidgets('the round end panel ranks every seat', (tester) async {
    usePhoneSurface(tester);
    var again = 0;

    await tester.pumpWidget(
      wrap(
        GameBoard(
          header: const SizedBox.shrink(),
          view: buildView(
            status: 'finished',
            handCounts: const [0, 3, 5, 5],
            ranks: const [1, 2, 3, 3],
            lastAction: const {
              'type': 'round_over',
              'at': 4000,
              'round': 1,
              'winnerSeat': 0,
            },
          ),
          seats: testSeats(),
          onPlay: (_) {},
          onPass: () {},
          onRefused: (_) {},
          onPlayAgain: () => again += 1,
        ),
      ),
    );
    await settle(tester);

    expect(find.byType(RoundOverPanel), findsOneWidget);
    expect(find.text('1st'), findsOneWidget);
    expect(find.text('Out of cards'), findsOneWidget);
    expect(find.text('3 cards left'), findsOneWidget);
    expect(find.text('3rd'), findsNWidgets(2));

    await tester.tap(find.text('Play again'));
    expect(again, 1);

    await unmount(tester);
  });

  testWidgets('the match goes to the seat holding first place, not to seat 0', (
    tester,
  ) async {
    usePhoneSurface(tester);

    await tester.pumpWidget(
      wrap(
        GameBoard(
          header: const SizedBox.shrink(),
          view: buildView(
            round: 3,
            rounds: 3,
            status: 'finished',
            handCounts: const [0, 4, 6, 6],
            ranks: const [1, 2, 3, 3],
            // You took the last round, so the round winner is you. The match
            // went elsewhere: Bot 2 has the lowest total across all three.
            winnerSeat: 0,
            standings: const [
              {'seatIndex': 0, 'score': 9, 'rank': 4},
              {'seatIndex': 1, 'score': 5, 'rank': 2},
              {'seatIndex': 2, 'score': 2, 'rank': 1},
              {'seatIndex': 3, 'score': 7, 'rank': 3},
            ],
            lastAction: const {
              'type': 'round_over',
              'at': 4000,
              'round': 3,
              'winnerSeat': 0,
            },
          ),
          seats: testSeats(),
          onPlay: (_) {},
          onPass: () {},
          onRefused: (_) {},
          onPlayAgain: () {},
        ),
      ),
    );
    await settle(tester);

    expect(find.text('Bot 2 wins the match'), findsOneWidget);
    expect(find.text('Round 3 of 3'), findsOneWidget);
    // Winning the last round of a match somebody else won is not a win.
    expect(find.byType(Celebrate), findsNothing);

    // Totals, not cards in hand, once the whole match is being reported.
    expect(find.text('Score 2'), findsOneWidget);
    expect(find.text('Score 9'), findsOneWidget);

    // Scoped to the panel: the seats behind it carry these names too.
    double rowY(String text) => tester
        .getCenter(
          find.descendant(
            of: find.byType(RoundOverPanel),
            matching: find.text(text),
          ),
        )
        .dy;
    expect(rowY('1st'), lessThan(rowY('2nd')));
    expect(rowY('2nd'), lessThan(rowY('3rd')));
    expect(rowY('3rd'), lessThan(rowY('4th')));

    // First place is Bot 2's row, and yours is last.
    expect(rowY('Bot 2'), closeTo(rowY('1st'), 4));
    expect(rowY('You'), closeTo(rowY('4th'), 4));

    await unmount(tester);
  });

  testWidgets('a notice replaces the prompt and shakes the panel', (
    tester,
  ) async {
    usePhoneSurface(tester);
    Widget board({String? notice}) => wrap(
      GameBoard(
        header: const SizedBox.shrink(),
        view: buildView(
          yourHand: const ['H7', 'H9'],
          yourLegalMoves: const ['H7'],
          lastAction: const {'type': 'deal', 'at': 0, 'round': 1},
        ),
        seats: testSeats(),
        notice: notice,
        onPlay: (_) {},
        onPass: () {},
        onRefused: (_) {},
      ),
    );

    await tester.pumpWidget(board());
    await settle(tester);
    expect(find.byType(Shake), findsOneWidget);

    await tester.pumpWidget(
      board(notice: 'Hearts needs 6♥ or 8♥ next, not 10♥.'),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Hearts needs 6♥ or 8♥ next, not 10♥.'), findsOneWidget);
    expect(find.text('Your turn. Tap the glowing card.'), findsNothing);

    await unmount(tester);
  });

  testWidgets('cards carry a spoken label, not just a glow', (tester) async {
    usePhoneSurface(tester);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      wrap(
        GameBoard(
          header: const SizedBox.shrink(),
          view: buildView(
            handCounts: const [2, 13, 13, 13],
            yourHand: const ['H7', 'H9'],
            yourLegalMoves: const ['H7'],
            lastAction: const {'type': 'deal', 'at': 0, 'round': 1},
          ),
          seats: testSeats(),
          onPlay: (_) {},
          onPass: () {},
          onRefused: (_) {},
        ),
      ),
    );
    await settle(tester);

    expect(find.bySemanticsLabel('7 of hearts, can be played'), findsOneWidget);
    expect(
      find.bySemanticsLabel('9 of hearts, cannot be played yet'),
      findsOneWidget,
    );

    // Released inside the test body: a tear down runs after the check that no
    // handle is left open.
    semantics.dispose();
    await unmount(tester);
  });
}
