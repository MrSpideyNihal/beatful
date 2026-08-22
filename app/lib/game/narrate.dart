/// Turning a view into the sentences the board shows.
///
/// Pure functions, no widgets, so the wording is testable and identical in solo
/// and online play. Every string here is written to be read out loud by somebody
/// who has never played before.
library;

import '../models/seat_info.dart';
import 'cards.dart' as cards;
import 'engine.dart';
import 'rules.dart' as rules;

String seatName(List<SeatInfo> seats, int? index) {
  if (index == null || index < 0 || index >= seats.length) return 'Someone';
  final seat = seats[index];
  return seat.isYou ? 'You' : seat.name;
}

String _possessive(List<SeatInfo> seats, int? index) {
  final name = seatName(seats, index);
  return name == 'You' ? 'Your' : "$name's";
}

/// The line above the table: what just happened. Null while a round has not
/// started yet, so the board can show the opening hint instead.
String? describeLastAction(PublicView view, List<SeatInfo> seats) {
  final action = view.lastAction;
  if (action == null) return null;
  final who = seatName(seats, action.seatIndex);

  switch (action.type) {
    case 'play':
      final card = action.card;
      if (card == null) return null;
      final label = cards.cardLabel(card);
      if (action.auto) {
        return '${_possessive(seats, action.seatIndex)} turn timed out - auto-played $label';
      }
      return '$who played $label';
    case 'pass':
      if (action.auto) {
        return '${_possessive(seats, action.seatIndex)} turn timed out - nothing to play, passed';
      }
      return who == 'You' ? 'You passed' : '$who passed';
    case 'round_over':
      final winner = seatName(seats, action.winnerSeat);
      return winner == 'You' ? 'You won the round' : '$winner won the round';
    case 'deal':
      return 'Cards dealt';
    default:
      return null;
  }
}

/// The instruction line: what to do right now.
String turnPrompt(PublicView view, List<SeatInfo> seats) {
  if (view.status == GameStatus.finished) return 'Match over';
  if (view.status == GameStatus.roundOver) {
    return 'Round ${view.round} of ${view.rounds} finished';
  }
  if (view.isMyTurn) {
    if (view.yourLegalMoves.isEmpty) return 'No card you can play. Tap Pass.';
    if (view.yourLegalMoves.length == 1) {
      return 'Your turn. Tap the glowing card.';
    }
    return 'Your turn. Tap one of the ${view.yourLegalMoves.length} glowing cards.';
  }
  return 'Waiting for ${seatName(seats, view.currentTurnSeat)}';
}

/// Why a card cannot be played yet, in plain words. Used for the nudge when
/// somebody taps a dimmed card instead of silently ignoring the tap.
String explainIllegal(rules.TableState table, String card) {
  if (!cards.isCard(card)) return 'That is not a card.';
  final parsed = cards.parseCard(card);
  final suit = suitTitle(parsed.suit);
  final label = cards.cardLabel(card);
  if (rules.needsAnchor(table, parsed.suit)) {
    if (parsed.rank == cards.anchorRank) {
      return '$label can be played. Tap it again.';
    }
    return 'Play the 7 of ${cards.suitNames[parsed.suit]} first to open $suit.';
  }
  final needed = rules.nextNeeded(table, parsed.suit);
  final wants = <String>[];
  if (needed.down != null) {
    wants.add(cards.cardLabel(cards.makeCard(parsed.suit, needed.down!)));
  }
  if (needed.up != null) {
    wants.add(cards.cardLabel(cards.makeCard(parsed.suit, needed.up!)));
  }
  if (wants.isEmpty) return '$suit is finished. Nothing more goes there.';
  return '$suit needs ${wants.join(' or ')} next, not $label.';
}

/// Suit name at the start of a sentence.
String suitTitle(String suit) {
  final name = cards.suitNames[suit] ?? suit;
  return name[0].toUpperCase() + name.substring(1);
}

/// Ordinal place, for the ranking screen.
String placeLabel(int rank) {
  switch (rank) {
    case 1:
      return '1st';
    case 2:
      return '2nd';
    case 3:
      return '3rd';
    default:
      return '${rank}th';
  }
}

/// How a seat did in the round that just ended.
String roundLine(PublicView view, List<SeatInfo> seats, int seat) {
  final ranks = view.ranks;
  if (ranks == null || seat >= ranks.length) return '';
  final left = seat < view.handCounts.length ? view.handCounts[seat] : 0;
  if (left == 0) return '${placeLabel(ranks[seat])}, went out';
  return '${placeLabel(ranks[seat])}, $left card${left == 1 ? '' : 's'} left';
}

/// Spoken description of a card for screen readers, plus whether it can be
/// played, since the glow alone is not readable.
String cardSemantics(String card, {required bool playable}) {
  final spoken = cards.cardSpokenLabel(card);
  return playable ? '$spoken, can be played' : '$spoken, cannot be played yet';
}

/// Rule and request error codes in words a player can act on. The codes are the
/// same offline and from the server, so this table covers both.
///
/// A code this table knows always wins, because the wording here is written for
/// a first time player. Anything unknown falls back to the sentence the server
/// sent, and only then to a generic line.
String errorMessage(String? code, [String? serverMessage]) {
  switch (code) {
    case 'NOT_YOUR_TURN':
      return 'It is not your turn yet.';
    case 'MUST_PLAY':
      return 'You have a card you can play, so you cannot pass.';
    case 'ILLEGAL_MOVE':
      return 'That card cannot be played yet.';
    case 'CARD_NOT_IN_HAND':
      return 'That card is not in your hand.';
    case 'ROUND_NOT_ACTIVE':
      return 'The round has finished.';
    case 'BAD_CARD':
      return 'That is not a card.';
    case 'ROOM_NOT_FOUND':
      return 'That room code does not exist.';
    case 'BAD_ROOM_CODE':
      return 'A room code is 6 letters and numbers.';
    case 'ROOM_FULL':
      return 'That room is full.';
    case 'ROOM_STARTED':
    case 'ALREADY_STARTED':
      return 'That match has already started.';
    case 'NOT_STARTED':
      return 'The match has not started yet.';
    case 'ROOM_LOCKED':
      return 'The host has closed that room to new players.';
    case 'NOT_A_MEMBER':
    case 'NOT_IN_ROOM':
      return 'You are not in that room.';
    case 'NOT_HOST':
      return 'Only the host can do that.';
    case 'NOT_ENOUGH_PLAYERS':
      return 'You need at least two players to start.';
    case 'SEAT_TAKEN':
      return 'Somebody took that seat first.';
    case 'BAD_SEAT':
      return 'That seat is not in this room.';
    case 'SETTINGS_INVALID':
      return 'Those settings do not work together. Check the entry fee.';
    case 'NAME_INVALID':
      return 'That name cannot be used. Try letters and numbers.';
    case 'NOT_ENOUGH_COINS':
    case 'INSUFFICIENT_COINS':
      return 'You do not have enough coins for that.';
    case 'ITEM_NOT_FOUND':
      return 'That item is not in the shop any more.';
    case 'ALREADY_OWNED':
      return 'You already own that one.';
    case 'DAILY_AD_LIMIT':
      return 'That is all the ad coins for today. Come back tomorrow.';
    case 'RATE_LIMITED':
      return 'Too many tries. Wait a moment and try again.';
    case 'UNAUTHORIZED':
    case 'TOKEN_INVALID':
      return 'Your session expired. Restart the app to sign back in.';
    case 'WAKING':
      return 'Connecting to the game server. This can take up to a minute the '
          'first time.';
    case 'DB_UNAVAILABLE':
      return 'The game server is having trouble. Try again in a moment.';
    case 'OFFLINE':
      return 'No internet connection.';
    case 'TIMEOUT':
      return 'The server took too long to answer.';
    default:
      final message = serverMessage?.trim();
      if (message != null && message.isNotEmpty) return message;
      return 'Something went wrong. Try again.';
  }
}
