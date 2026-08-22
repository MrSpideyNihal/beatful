/// The signed in guest, as the server sees them.
///
/// Guests only: there is no email, no password and nothing behind a signup wall.
/// The server owns the coin balance, so this object is always replaced from a
/// server response rather than edited locally.
library;

import 'package:flutter/foundation.dart';

@immutable
class PlayerStats {
  const PlayerStats({
    this.wins = 0,
    this.matchesPlayed = 0,
    this.roundsPlayed = 0,
  });

  factory PlayerStats.fromJson(Map<String, Object?> json) => PlayerStats(
    wins: (json['wins'] as num?)?.toInt() ?? 0,
    matchesPlayed: (json['matchesPlayed'] as num?)?.toInt() ?? 0,
    roundsPlayed: (json['roundsPlayed'] as num?)?.toInt() ?? 0,
  );

  final int wins;
  final int matchesPlayed;
  final int roundsPlayed;
}

@immutable
class Account {
  const Account({
    required this.userId,
    required this.displayName,
    required this.avatarId,
    required this.coins,
    this.stats = const PlayerStats(),
    this.ownedItems = const [],
    this.cardBack = 'back_classic',
    this.table = 'table_green',
    this.adsClaimedToday = 0,
  });

  factory Account.fromJson(Map<String, Object?> json) {
    final selected = json['selected'] is Map
        ? Map<String, Object?>.from(json['selected'] as Map)
        : const <String, Object?>{};
    final ads = json['adRewards'] is Map
        ? Map<String, Object?>.from(json['adRewards'] as Map)
        : const <String, Object?>{};
    return Account(
      userId: json['userId'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'You',
      avatarId: (json['avatarId'] as num?)?.toInt() ?? 0,
      coins: (json['coins'] as num?)?.toInt() ?? 0,
      stats: json['stats'] is Map
          ? PlayerStats.fromJson(Map<String, Object?>.from(json['stats'] as Map))
          : const PlayerStats(),
      ownedItems: [
        for (final entry in (json['ownedItems'] as List? ?? const []))
          if (entry is String) entry,
      ],
      cardBack: selected['cardBack'] as String? ?? 'back_classic',
      table: selected['table'] as String? ?? 'table_green',
      adsClaimedToday: (ads['count'] as num?)?.toInt() ?? 0,
    );
  }

  final String userId;
  final String displayName;
  final int avatarId;
  final int coins;
  final PlayerStats stats;
  final List<String> ownedItems;
  final String cardBack;
  final String table;
  final int adsClaimedToday;

  bool owns(String itemId) => ownedItems.contains(itemId);

  Account copyWith({String? displayName, int? avatarId, int? coins}) => Account(
    userId: userId,
    displayName: displayName ?? this.displayName,
    avatarId: avatarId ?? this.avatarId,
    coins: coins ?? this.coins,
    stats: stats,
    ownedItems: ownedItems,
    cardBack: cardBack,
    table: table,
    adsClaimedToday: adsClaimedToday,
  );
}

/// One row of the coin ledger, so a balance change is never a mystery.
@immutable
class CoinEntry {
  const CoinEntry({
    required this.type,
    required this.amount,
    required this.balanceAfter,
    this.roomCode,
    this.itemId,
    this.at,
  });

  factory CoinEntry.fromJson(Map<String, Object?> json) => CoinEntry(
    type: json['type'] as String? ?? 'adjustment',
    amount: (json['amount'] as num?)?.toInt() ?? 0,
    balanceAfter: (json['balanceAfter'] as num?)?.toInt() ?? 0,
    roomCode: json['roomCode'] as String?,
    itemId: json['itemId'] as String?,
    at: DateTime.tryParse(json['createdAt'] as String? ?? ''),
  );

  final String type;
  final int amount;
  final int balanceAfter;
  final String? roomCode;
  final String? itemId;
  final DateTime? at;

  /// Ledger types in words, since the wire names are not for reading.
  String get label => switch (type) {
    'signup_bonus' => 'Welcome coins',
    'ad_reward' => 'Watched an ad',
    'match_entry' =>
      roomCode == null ? 'Match entry' : 'Entry fee, room $roomCode',
    'match_entry_refund' => 'Entry fee refunded',
    'match_win' =>
      roomCode == null ? 'Match winnings' : 'Winnings, room $roomCode',
    'shop_purchase' => 'Shop purchase',
    _ => 'Adjustment',
  };
}
