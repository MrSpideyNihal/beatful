/// App level tests: the path a first time player takes.
///
/// Home has to reach a game in one tap, so that path is walked here end to end
/// with the real providers and a silent audio service in place of the plugin.
library;

import 'package:beatful/main.dart';
import 'package:beatful/screens/game_screen.dart';
import 'package:beatful/services/audio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'support/harness.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    usePhoneSurface(tester);
    SharedPreferences.setMockInitialValues({
      'profile.has_custom_name': true,
      'profile.name': 'You',
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioProvider.overrideWithValue(SilentAudio())],
        child: const BeatfulApp(),
      ),
    );
    await settle(tester);
  }

  testWidgets('home offers both ways to play', (tester) async {
    await pumpApp(tester);

    expect(find.text('Beatful'), findsOneWidget);
    expect(find.text('The Sevens card game'), findsOneWidget);
    expect(find.text('Play vs Bots'), findsOneWidget);
    expect(find.text('Play with Friends'), findsOneWidget);
    expect(find.text('How to play'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('how to play explains the seven rule', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('How to play'));
    await settle(tester);

    expect(find.text('The goal'), findsOneWidget);
    expect(find.textContaining('7'), findsWidgets);

    await unmount(tester);
  });

  testWidgets('two taps from home to a dealt hand', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Play vs Bots'));
    await settle(tester);
    expect(find.text('Start'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await settle(tester);

    expect(find.byType(GameBoard), findsOneWidget);
    // A four seat deal gives every seat 13 cards.
    expect(find.text('Your cards: 13'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('settings edits the name the board will show', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Settings'));
    await settle(tester);

    expect(find.text('Your name'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Nihal');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    await tester.tap(find.byTooltip('Back'));
    await settle(tester);

    expect(find.text('Nihal'), findsOneWidget);

    await unmount(tester);
  });

  testWidgets('first launch shows welcome name dialog and saves chosen name', (tester) async {
    usePhoneSurface(tester);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [audioProvider.overrideWithValue(SilentAudio())],
        child: const BeatfulApp(),
      ),
    );
    await settle(tester);

    expect(find.text('Welcome to Beatful!'), findsOneWidget);
    expect(find.text("Let's Play"), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Nihal');
    await tester.tap(find.text("Let's Play"));
    await settle(tester);

    expect(find.text('Welcome to Beatful!'), findsNothing);
    expect(find.text('Nihal'), findsOneWidget);

    await unmount(tester);
  });
}
