/// Shared helpers for the widget tests.
///
/// Two things every board test needs: audio that never touches a platform
/// channel, and a way to build an exact PublicView without playing a whole round
/// to get to the position under test.
library;

import 'package:beatful/game/engine.dart';
import 'package:beatful/models/seat_info.dart';
import 'package:beatful/services/audio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Audio with the speakers taken out. The real class talks to a plugin that does
/// not exist in a test binding, so every method here is a no-op.
class SilentAudio extends Audio {
  final List<String> played = [];

  @override
  void play(String asset, {double volume = 1}) => played.add(asset);

  @override
  void setMusic({required bool on, required double volume}) {}

  @override
  void previewMusic(double volume) {}

  @override
  void suspend() {}

  @override
  void resume() {}

  @override
  Future<void> dispose() async {}
}

/// A 360x780 logical phone, which is the size the layout is designed against.
/// The 800x600 test default is not a shape any player holds.
void usePhoneSurface(WidgetTester tester) {
  final view = tester.view;
  view.physicalSize = const Size(1080, 2340);
  view.devicePixelRatio = 3;
  addTearDown(() {
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });
}

/// Runs the entrance animations out.
///
/// pumpAndSettle would spin for ever here, because the playable badge and the
/// turn ring repeat by design. Entrances are staggered by a timer, so a single
/// long pump only starts them: the first pump fires the delays, the later ones
/// carry the animations to their end.
Future<void> settle(WidgetTester tester, [int frames = 4]) async {
  for (var frame = 0; frame < frames; frame += 1) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

/// Unmounts the tree so provider and animation timers are cancelled before the
/// test ends and the pending timer check runs.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

/// A view built straight from JSON, which is the same path an online match uses,
/// so a test position cannot drift from a real server payload.
PublicView buildView({
  int round = 1,
  int rounds = 1,
  String status = 'in_progress',
  int seatCount = 4,
  Map<String, Object?> table = const {},
  List<int> handCounts = const [13, 13, 13, 13],
  int currentTurnSeat = 0,
  int turnStartedAt = 0,
  int timerSeconds = 15,
  int millisLeft = 15000,
  int? yourSeat = 0,
  List<String> yourHand = const [],
  List<String> yourLegalMoves = const [],
  bool canPass = false,
  Map<String, Object?>? lastAction,
  List<int> scores = const [0, 0, 0, 0],
  List<int>? ranks,
  int? winnerSeat,
  // Seat indexed, the way the server sends them: the entry at position 0 is
  // seat 0's, whatever place seat 0 came.
  List<Map<String, Object?>>? standings,
}) {
  return PublicView.fromJson({
    'round': round,
    'rounds': rounds,
    'status': status,
    'seatCount': seatCount,
    'table': {
      for (final suit in ['H', 'D', 'C', 'S'])
        suit: table[suit] ?? {'low': null, 'high': null},
    },
    'handCounts': handCounts,
    'currentTurnSeat': currentTurnSeat,
    'turnStartedAt': turnStartedAt,
    'timerSeconds': timerSeconds,
    'millisLeft': millisLeft,
    'yourSeat': yourSeat,
    'yourHand': yourHand,
    'yourLegalMoves': yourLegalMoves,
    'canPass': canPass,
    'lastAction': lastAction,
    'log': const <Object?>[],
    'scores': scores,
    'roundResults': const <Object?>[],
    'winnerSeat': winnerSeat,
    'ranks': ranks,
    'standings': standings,
  });
}

/// An open suit pile, for the table map above.
Map<String, Object?> pile(int low, int high) => {'low': low, 'high': high};

List<SeatInfo> testSeats([int count = 4]) => [
  const SeatInfo(index: 0, name: 'You', avatar: 0, isYou: true),
  for (var seat = 1; seat < count; seat += 1)
    SeatInfo(index: seat, name: 'Bot $seat', avatar: seat, isBot: true),
];
