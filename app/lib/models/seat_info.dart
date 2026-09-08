/// Who is sitting in each seat, for display only.
///
/// The engine deals in seat numbers and knows nothing about names. This is the
/// display side of a seat, and it is shaped the same whether the seats came from
/// a solo setup screen or from a room on the server.
library;

import '../game/bots.dart';

class SeatInfo {
  const SeatInfo({
    required this.index,
    required this.name,
    required this.avatar,
    this.isBot = false,
    this.isYou = false,
    this.difficulty,
    this.connected = true,
  });

  final int index;
  final String name;
  final int avatar;
  final bool isBot;
  final bool isYou;
  final BotDifficulty? difficulty;
  final bool connected;

  SeatInfo copyWith({String? name, int? avatar, bool? connected}) => SeatInfo(
    index: index,
    name: name ?? this.name,
    avatar: avatar ?? this.avatar,
    isBot: isBot,
    isYou: isYou,
    difficulty: difficulty,
    connected: connected ?? this.connected,
  );

  /// "You played" reads better than "You plays", so callers that build sentences
  /// need to know which form to use.
  bool get isSelf => isYou;
}

/// Generic names for bot seats. Short, clear, and easy to read at a glance.
const List<String> botRoster = [
  'Bot 1',
  'Bot 2',
  'Bot 3',
  'Bot 4',
  'Bot 5',
  'Bot 6',
  'Bot 7',
  'Bot 8',
];

String botName(int slot) => botRoster[slot.abs() % botRoster.length];
