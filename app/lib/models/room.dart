/// The room, exactly as the server sends it.
///
/// One parser for every path: create, join, snapshot and long poll all return the
/// same room object, so the whole app reads a single shape. Unknown or missing
/// fields fall back to something safe rather than throwing, because a player in
/// the middle of a match should never see a parse error.
library;

import 'package:flutter/foundation.dart';

import '../game/bots.dart';
import '../game/engine.dart';
import '../models/avatar.dart';
import '../models/seat_info.dart';

enum RoomStatus { lobby, inProgress, finished }

RoomStatus _statusOf(Object? raw) => switch (raw) {
  'in_progress' => RoomStatus.inProgress,
  'finished' => RoomStatus.finished,
  _ => RoomStatus.lobby,
};

enum PayoutMode { winnerTakesAll, rankedSplit }

int _int(Object? value, [int fallback = 0]) => switch (value) {
  final int v => v,
  final num v => v.toInt(),
  final String v => int.tryParse(v) ?? fallback,
  _ => fallback,
};

bool _bool(Object? value, [bool fallback = false]) =>
    value is bool ? value : fallback;

String _str(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;

List<Map<String, Object?>> _maps(Object? value) => switch (value) {
  final List<Object?> list => [
    for (final entry in list)
      if (entry is Map) Map<String, Object?>.from(entry),
  ],
  _ => const [],
};

@immutable
class RoomSettings {
  const RoomSettings({
    this.playerCount = 4,
    this.timerSeconds = 15,
    this.rounds = 1,
    this.coinMatch = false,
    this.entryFee = 0,
    this.shuffleSeats = false,
    this.payout = PayoutMode.winnerTakesAll,
    this.fillWithBots = false,
    this.botDifficulty = BotDifficulty.medium,
  });

  factory RoomSettings.fromJson(Map<String, Object?> json) => RoomSettings(
    playerCount: _int(json['playerCount'], 4),
    timerSeconds: _int(json['timerSeconds'], 15),
    rounds: _int(json['rounds'], 1),
    coinMatch: _bool(json['coinMatch']),
    entryFee: _int(json['entryFee']),
    shuffleSeats: _bool(json['shuffleSeats']),
    payout: json['payout'] == 'ranked_split'
        ? PayoutMode.rankedSplit
        : PayoutMode.winnerTakesAll,
    fillWithBots: _bool(json['fillWithBots']),
    botDifficulty: BotDifficulty.fromWire(json['botDifficulty']),
  );

  final int playerCount;
  final int timerSeconds;
  final int rounds;
  final bool coinMatch;
  final int entryFee;
  final bool shuffleSeats;
  final PayoutMode payout;
  final bool fillWithBots;
  final BotDifficulty botDifficulty;

  Map<String, Object?> toJson() => {
    'playerCount': playerCount,
    'timerSeconds': timerSeconds,
    'rounds': rounds,
    'coinMatch': coinMatch,
    'entryFee': entryFee,
    'shuffleSeats': shuffleSeats,
    'payout': payout == PayoutMode.rankedSplit
        ? 'ranked_split'
        : 'winner_takes_all',
    'fillWithBots': fillWithBots,
    'botDifficulty': botDifficulty.wire,
  };

  RoomSettings copyWith({
    int? playerCount,
    int? timerSeconds,
    int? rounds,
    bool? coinMatch,
    int? entryFee,
    bool? shuffleSeats,
    PayoutMode? payout,
    bool? fillWithBots,
    BotDifficulty? botDifficulty,
  }) => RoomSettings(
    playerCount: playerCount ?? this.playerCount,
    timerSeconds: timerSeconds ?? this.timerSeconds,
    rounds: rounds ?? this.rounds,
    coinMatch: coinMatch ?? this.coinMatch,
    entryFee: entryFee ?? this.entryFee,
    shuffleSeats: shuffleSeats ?? this.shuffleSeats,
    payout: payout ?? this.payout,
    fillWithBots: fillWithBots ?? this.fillWithBots,
    botDifficulty: botDifficulty ?? this.botDifficulty,
  );

  String get summary {
    final parts = <String>[
      '$playerCount players',
      '${timerSeconds}s a turn',
      rounds == 1 ? '1 round' : '$rounds rounds',
      if (coinMatch) '$entryFee coin entry' else 'free',
    ];
    return parts.join(', ');
  }
}

@immutable
class RoomPlayer {
  const RoomPlayer({
    required this.userId,
    required this.seatIndex,
    required this.name,
    required this.avatarId,
    required this.isBot,
    required this.ready,
    required this.connected,
    required this.isHost,
    required this.isYou,
    required this.cardCount,
    required this.stake,
    this.difficulty,
  });

  factory RoomPlayer.fromJson(Map<String, Object?> json) => RoomPlayer(
    userId: _str(json['userId']),
    seatIndex: _int(json['seatIndex']),
    name: _str(json['name'], 'Player'),
    avatarId: _int(json['avatarId']),
    isBot: _bool(json['isBot']),
    ready: _bool(json['ready']),
    connected: _bool(json['connected'], true),
    isHost: _bool(json['isHost']),
    isYou: _bool(json['isYou']),
    cardCount: _int(json['cardCount']),
    stake: _int(json['stake']),
    difficulty: json['difficulty'] is String
        ? BotDifficulty.fromWire(json['difficulty'])
        : null,
  );

  final String userId;
  final int seatIndex;
  final String name;
  final int avatarId;
  final bool isBot;
  final bool ready;
  final bool connected;
  final bool isHost;
  final bool isYou;
  final int cardCount;
  final int stake;
  final BotDifficulty? difficulty;

  SeatInfo toSeat() => SeatInfo(
    index: seatIndex,
    name: (!isYou && (name.trim().isEmpty || name.trim().toLowerCase() == 'you'))
        ? 'Player ${seatIndex + 1}'
        : name,
    avatar: avatarId % avatarCount(),
    isBot: isBot,
    isYou: isYou,
    difficulty: difficulty,
    connected: connected,
  );
}

@immutable
class RoomNotice {
  const RoomNotice({
    required this.id,
    required this.kind,
    required this.text,
    required this.at,
    this.seatIndex,
  });

  factory RoomNotice.fromJson(Map<String, Object?> json) => RoomNotice(
    id: _str(json['id']),
    kind: _str(json['kind'], 'info'),
    text: _str(json['text']),
    at: _int(json['at']),
    seatIndex: json['seatIndex'] is num
        ? (json['seatIndex'] as num).toInt()
        : null,
  );

  final String id;
  final String kind;
  final String text;
  final int at;
  final int? seatIndex;

  /// Worth interrupting the player for, as opposed to lobby chatter.
  bool get isAlert => const {
    'disconnected',
    'away',
    'bot_takeover',
    'kicked',
    'settled',
    'chat',
  }.contains(kind);

  bool get isChat => kind == 'chat';
}

@immutable
class RoomPayout {
  const RoomPayout({required this.seatIndex, required this.amount});

  factory RoomPayout.fromJson(Map<String, Object?> json) => RoomPayout(
    seatIndex: _int(json['seatIndex']),
    amount: _int(json['amount']),
  );

  final int seatIndex;
  final int amount;
}

@immutable
class RoomResult {
  const RoomResult({
    required this.standings,
    required this.payouts,
    required this.pool,
  });

  factory RoomResult.fromJson(Map<String, Object?> json) => RoomResult(
    standings: [
      for (final entry in _maps(json['standings'])) Standing.fromJson(entry),
    ],
    payouts: [
      for (final entry in _maps(json['payouts'])) RoomPayout.fromJson(entry),
    ],
    pool: _int(json['pool']),
  );

  final List<Standing> standings;
  final List<RoomPayout> payouts;
  final int pool;

  int payoutFor(int? seatIndex) {
    if (seatIndex == null) return 0;
    for (final payout in payouts) {
      if (payout.seatIndex == seatIndex) return payout.amount;
    }
    return 0;
  }
}

@immutable
class RoomView {
  const RoomView({
    required this.roomId,
    required this.roomCode,
    required this.link,
    required this.status,
    required this.locked,
    required this.version,
    required this.hostUserId,
    required this.isHost,
    required this.settings,
    required this.players,
    required this.notices,
    required this.serverTime,
    this.yourSeat,
    this.game,
    this.result,
    this.roundBreakUntil,
  });

  factory RoomView.fromJson(Map<String, Object?> json) {
    final players = [
      for (final entry in _maps(json['players'])) RoomPlayer.fromJson(entry),
    ]..sort((a, b) => a.seatIndex.compareTo(b.seatIndex));
    final game = json['game'];
    final result = json['result'];
    return RoomView(
      roomId: _str(json['roomId']),
      roomCode: _str(json['roomCode']),
      link: _str(json['link']),
      status: _statusOf(json['status']),
      locked: _bool(json['locked']),
      version: _int(json['version']),
      hostUserId: _str(json['hostUserId']),
      isHost: _bool(json['isHost']),
      settings: RoomSettings.fromJson(
        json['settings'] is Map
            ? Map<String, Object?>.from(json['settings'] as Map)
            : const {},
      ),
      players: players,
      notices: [
        for (final entry in _maps(json['notices'])) RoomNotice.fromJson(entry),
      ],
      serverTime: _int(json['serverTime']),
      yourSeat: json['yourSeat'] is num
          ? (json['yourSeat'] as num).toInt()
          : null,
      game: game is Map
          ? PublicView.fromJson(Map<String, Object?>.from(game))
          : null,
      result: result is Map
          ? RoomResult.fromJson(Map<String, Object?>.from(result))
          : null,
      roundBreakUntil: json['roundBreakUntil'] is num
          ? (json['roundBreakUntil'] as num).toInt()
          : null,
    );
  }

  final String roomId;
  final String roomCode;
  final String link;
  final RoomStatus status;
  final bool locked;
  final int version;
  final String hostUserId;
  final bool isHost;
  final RoomSettings settings;
  final List<RoomPlayer> players;
  final List<RoomNotice> notices;

  /// The server clock when this view was built, used to line the turn ring up
  /// with the server's deadline rather than the device clock.
  final int serverTime;

  final int? yourSeat;
  final PublicView? game;
  final RoomResult? result;
  final int? roundBreakUntil;

  bool get inLobby => status == RoomStatus.lobby;

  bool get isPlaying => status == RoomStatus.inProgress;

  bool get isFinished => status == RoomStatus.finished;

  bool get isYourTurn =>
      isPlaying && game != null && yourSeat != null && game!.isMyTurn;

  int get seatsFilled => players.length;

  int get seatsFree => (settings.playerCount - players.length).clamp(0, 8);

  RoomPlayer? get you {
    for (final player in players) {
      if (player.isYou) return player;
    }
    return null;
  }

  List<SeatInfo> get seats => [
    for (final player in players) player.toSeat(),
  ];

  /// The newest notice, which is what the lobby and the board show.
  RoomNotice? get lastNotice => notices.isEmpty ? null : notices.last;
}

/// What a poll returned: a new room, or nothing changed within the window.
@immutable
class PollOutcome {
  const PollOutcome({required this.changed, this.room, required this.version});

  factory PollOutcome.fromJson(Map<String, Object?> json) {
    final room = json['room'];
    return PollOutcome(
      changed: _bool(json['changed']),
      room: room is Map
          ? RoomView.fromJson(Map<String, Object?>.from(room))
          : null,
      version: _int(json['version']),
    );
  }

  final bool changed;
  final RoomView? room;
  final int version;
}
