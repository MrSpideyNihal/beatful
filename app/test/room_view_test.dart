/// Tests for the online room contract.
///
/// Every online screen reads one parsed room, so these tests hold the parser to
/// the shape the server sends and to the promise that a partial or unfamiliar
/// payload never throws at a player mid match.
library;

import 'package:beatful/game/bots.dart';
import 'package:beatful/game/narrate.dart' as narrate;
import 'package:beatful/models/room.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> lobbyRoom({
  Map<String, Object?> settings = const {},
  List<Object?> players = const [],
  List<Object?> notices = const [],
}) => {
  'roomId': 'r1',
  'roomCode': 'ABCDEF',
  'link': 'beatful://join/ABCDEF',
  'status': 'lobby',
  'version': 4,
  'hostUserId': 'u1',
  'isHost': true,
  'serverTime': 1000,
  'settings': settings,
  'players': players,
  'notices': notices,
};

Map<String, Object?> seat(
  int index, {
  String name = 'Player',
  bool you = false,
  bool host = false,
  bool bot = false,
  Object? connected,
}) => {
  'userId': 'u$index',
  'seatIndex': index,
  'name': name,
  'avatarId': index,
  'isYou': you,
  'isHost': host,
  'isBot': bot,
  // Left out entirely when the caller did not set it, which is the case an older
  // server produces.
  'connected': ?connected,
};

void main() {
  group('room settings', () {
    test('a silent server still gives a playable room', () {
      const settings = RoomSettings();
      final parsed = RoomSettings.fromJson(const {});
      expect(parsed.playerCount, settings.playerCount);
      expect(parsed.timerSeconds, 15);
      expect(parsed.rounds, 1);
      expect(parsed.coinMatch, isFalse);
      expect(parsed.payout, PayoutMode.winnerTakesAll);
      expect(parsed.botDifficulty, BotDifficulty.medium);
    });

    test('the payout mode is only ranked when the server says so', () {
      expect(
        RoomSettings.fromJson(const {'payout': 'ranked_split'}).payout,
        PayoutMode.rankedSplit,
      );
      expect(
        RoomSettings.fromJson(const {'payout': 'something_else'}).payout,
        PayoutMode.winnerTakesAll,
      );
    });

    test('the summary is the line a player reads before joining', () {
      const free = RoomSettings(playerCount: 3, timerSeconds: 20, rounds: 1);
      expect(free.summary, '3 players, 20s a turn, 1 round, free');

      const paid = RoomSettings(
        playerCount: 4,
        timerSeconds: 15,
        rounds: 3,
        coinMatch: true,
        entryFee: 50,
      );
      expect(paid.summary, '4 players, 15s a turn, 3 rounds, 50 coin entry');
    });

    test('settings survive a round trip through the wire', () {
      const original = RoomSettings(
        playerCount: 6,
        timerSeconds: 30,
        rounds: 2,
        coinMatch: true,
        entryFee: 100,
        shuffleSeats: true,
        payout: PayoutMode.rankedSplit,
        fillWithBots: true,
        botDifficulty: BotDifficulty.hard,
      );
      final back = RoomSettings.fromJson(original.toJson());
      expect(back.summary, original.summary);
      expect(back.shuffleSeats, isTrue);
      expect(back.payout, PayoutMode.rankedSplit);
      expect(back.fillWithBots, isTrue);
      expect(back.botDifficulty, BotDifficulty.hard);
    });
  });

  group('players', () {
    test('seats are ordered by seat index, not by arrival', () {
      final room = RoomView.fromJson(
        lobbyRoom(
          players: [seat(2, name: 'Meera'), seat(0, name: 'Ravi'), seat(1)],
        ),
      );
      expect([for (final p in room.players) p.seatIndex], [0, 1, 2]);
      expect(room.seats.first.name, 'Ravi');
      expect(room.seats.last.name, 'Meera');
    });

    test('a player is connected unless the server says otherwise', () {
      // The absent case matters: an older server that never sends the field must
      // not paint every seat as away.
      expect(RoomPlayer.fromJson(seat(0)).connected, isTrue);
      expect(RoomPlayer.fromJson(seat(0, connected: false)).connected, isFalse);
      expect(RoomPlayer.fromJson(const {}).name, 'Player');
    });

    test('difficulty is only set for a bot seat', () {
      expect(RoomPlayer.fromJson(seat(1)).difficulty, isNull);
      final bot = RoomPlayer.fromJson({
        ...seat(1, bot: true),
        'difficulty': 'hard',
      });
      expect(bot.difficulty, BotDifficulty.hard);
      expect(bot.toSeat().isBot, isTrue);
    });

    test('you is the seat flagged as yours, and null when there is none', () {
      final room = RoomView.fromJson(
        lobbyRoom(players: [seat(0), seat(1, name: 'Asha', you: true)]),
      );
      expect(room.you?.name, 'Asha');
      expect(RoomView.fromJson(lobbyRoom(players: [seat(0)])).you, isNull);
    });

    test('free seats count down and never go negative', () {
      final full = RoomView.fromJson(
        lobbyRoom(
          settings: const {'playerCount': 2},
          players: [seat(0), seat(1)],
        ),
      );
      expect(full.seatsFilled, 2);
      expect(full.seatsFree, 0);

      // The host lowering the count below the people already in the room is a
      // real state, and it reads as full rather than as minus one.
      final shrunk = RoomView.fromJson(
        lobbyRoom(
          settings: const {'playerCount': 2},
          players: [seat(0), seat(1), seat(2)],
        ),
      );
      expect(shrunk.seatsFree, 0);
    });
  });

  group('status', () {
    test('each wire status maps to one state', () {
      final lobby = RoomView.fromJson(lobbyRoom());
      expect(lobby.inLobby, isTrue);
      expect(lobby.isPlaying, isFalse);
      expect(lobby.isFinished, isFalse);

      final playing = RoomView.fromJson({
        ...lobbyRoom(),
        'status': 'in_progress',
      });
      expect(playing.isPlaying, isTrue);

      final done = RoomView.fromJson({...lobbyRoom(), 'status': 'finished'});
      expect(done.isFinished, isTrue);

      // Anything unrecognised is treated as a lobby, which is the state where
      // nothing can be spent or lost.
      expect(
        RoomView.fromJson({...lobbyRoom(), 'status': 'who_knows'}).inLobby,
        isTrue,
      );
    });

    test('it is your turn only when playing, seated and named', () {
      Map<String, Object?> playing(Object? yourSeat, int currentTurnSeat) => {
        ...lobbyRoom(players: [seat(0, you: true), seat(1)]),
        'status': 'in_progress',
        'yourSeat': yourSeat,
        'game': {
          'status': 'in_progress',
          'seatCount': 2,
          'currentTurnSeat': currentTurnSeat,
          'yourSeat': yourSeat,
          'handCounts': [5, 5],
          'yourHand': ['7H'],
          'yourLegalMoves': ['7H'],
          'canPass': false,
        },
      };

      expect(RoomView.fromJson(playing(0, 0)).isYourTurn, isTrue);
      expect(RoomView.fromJson(playing(0, 1)).isYourTurn, isFalse);
      // A watcher with no seat is never on turn.
      expect(RoomView.fromJson(playing(null, 0)).isYourTurn, isFalse);
      // Nor is anyone in the lobby, whatever the game object says.
      final lobby = RoomView.fromJson({
        ...playing(0, 0),
        'status': 'lobby',
      });
      expect(lobby.isYourTurn, isFalse);
    });

    test('a room with no game yet parses with a null game', () {
      final room = RoomView.fromJson(lobbyRoom());
      expect(room.game, isNull);
      expect(room.result, isNull);
      expect(room.roundBreakUntil, isNull);
      expect(room.isYourTurn, isFalse);
    });

    test('a game sent as something other than a map is ignored', () {
      final room = RoomView.fromJson({
        ...lobbyRoom(),
        'game': 'in_progress',
        'result': 7,
        'yourSeat': 'two',
        'roundBreakUntil': 'soon',
      });
      expect(room.game, isNull);
      expect(room.result, isNull);
      expect(room.yourSeat, isNull);
      expect(room.roundBreakUntil, isNull);
    });
  });

  group('notices', () {
    test('the newest notice is the one shown', () {
      final room = RoomView.fromJson(
        lobbyRoom(
          notices: [
            {'id': 'n1', 'kind': 'joined', 'text': 'Ravi joined', 'at': 1},
            {'id': 'n2', 'kind': 'away', 'text': 'Meera went away', 'at': 2},
          ],
        ),
      );
      expect(room.notices.length, 2);
      expect(room.lastNotice?.id, 'n2');
      expect(room.lastNotice?.isAlert, isTrue);
      expect(RoomView.fromJson(lobbyRoom()).lastNotice, isNull);
    });

    test('only the notices worth interrupting for are alerts', () {
      RoomNotice of(String kind) => RoomNotice.fromJson({'kind': kind});
      expect(of('disconnected').isAlert, isTrue);
      expect(of('bot_takeover').isAlert, isTrue);
      expect(of('kicked').isAlert, isTrue);
      expect(of('settled').isAlert, isTrue);
      expect(of('joined').isAlert, isFalse);
      expect(of('timeout').isAlert, isFalse);
      // A notice with nothing in it is still a notice, not a crash.
      expect(RoomNotice.fromJson(const {}).kind, 'info');
    });

    test('a notice list holding junk keeps the entries that are notices', () {
      final room = RoomView.fromJson(
        lobbyRoom(
          notices: [
            'not a notice',
            {'id': 'n1', 'kind': 'joined', 'text': 'Ravi joined'},
          ],
        ),
      );
      expect(room.notices.length, 1);
      expect(room.notices.single.at, 0);
    });
  });

  group('results', () {
    test('a payout is found by seat and is zero for anyone else', () {
      final result = RoomResult.fromJson(const {
        'pool': 100,
        'payouts': [
          {'seatIndex': 0, 'amount': 75},
          {'seatIndex': 1, 'amount': 25},
        ],
        'standings': [],
      });
      expect(result.pool, 100);
      expect(result.payoutFor(0), 75);
      expect(result.payoutFor(1), 25);
      expect(result.payoutFor(3), 0);
      // A watcher has no seat, so there is nothing to pay.
      expect(result.payoutFor(null), 0);
    });

    test('a free match result has no payouts and does not throw', () {
      final result = RoomResult.fromJson(const {});
      expect(result.pool, 0);
      expect(result.payouts, isEmpty);
      expect(result.standings, isEmpty);
      expect(result.payoutFor(0), 0);
    });
  });

  group('poll outcome', () {
    test('a changed poll carries the whole room', () {
      final outcome = PollOutcome.fromJson({
        'changed': true,
        'version': 9,
        'room': lobbyRoom(players: [seat(0, you: true, host: true)]),
      });
      expect(outcome.changed, isTrue);
      expect(outcome.version, 9);
      expect(outcome.room?.roomCode, 'ABCDEF');
      expect(outcome.room?.you?.isHost, isTrue);
    });

    test('a quiet poll is not a failure', () {
      final outcome = PollOutcome.fromJson(const {
        'changed': false,
        'version': 9,
      });
      expect(outcome.changed, isFalse);
      expect(outcome.room, isNull);
      expect(outcome.version, 9);
    });

    test('an empty poll body reads as nothing changed', () {
      final outcome = PollOutcome.fromJson(const {});
      expect(outcome.changed, isFalse);
      expect(outcome.room, isNull);
      expect(outcome.version, 0);
    });
  });

  group('error wording', () {
    test('the codes a player can act on are spelled out', () {
      expect(narrate.errorMessage('NOT_YOUR_TURN'), 'It is not your turn yet.');
      expect(
        narrate.errorMessage('MUST_PLAY'),
        'You have a card you can play, so you cannot pass.',
      );
      expect(narrate.errorMessage('ROOM_FULL'), 'That room is full.');
      expect(
        narrate.errorMessage('ROOM_NOT_FOUND'),
        'That room code does not exist.',
      );
      expect(
        narrate.errorMessage('NOT_ENOUGH_COINS'),
        'You do not have enough coins for that.',
      );
      expect(
        narrate.errorMessage('INSUFFICIENT_COINS'),
        narrate.errorMessage('NOT_ENOUGH_COINS'),
      );
      expect(
        narrate.errorMessage('ALREADY_STARTED'),
        narrate.errorMessage('ROOM_STARTED'),
      );
    });

    test('a cold server is described as waking, not as broken', () {
      expect(narrate.errorMessage('WAKING'), contains('Connecting'));
      expect(narrate.errorMessage('OFFLINE'), 'No internet connection.');
      expect(
        narrate.errorMessage('TIMEOUT'),
        'The server took too long to answer.',
      );
    });

    test('a known code beats whatever sentence the server sent', () {
      expect(
        narrate.errorMessage('ROOM_FULL', 'room capacity exceeded'),
        'That room is full.',
      );
    });

    test('an unknown code falls back to the server, then to a plain line', () {
      expect(
        narrate.errorMessage('SOMETHING_NEW', 'The host ended the match.'),
        'The host ended the match.',
      );
      expect(
        narrate.errorMessage('SOMETHING_NEW', '   '),
        'Something went wrong. Try again.',
      );
      expect(narrate.errorMessage(null), 'Something went wrong. Try again.');
    });
  });
}
