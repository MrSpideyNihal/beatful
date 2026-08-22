/// The panel that covers the board when a round or a match ends.
///
/// Same panel for solo and online: it takes a view, the seats, and what the
/// buttons should do. Placings are printed with their number as well as their
/// order, and the winner row is marked with an icon, not just a colour.
library;

import 'package:flutter/material.dart';

import '../game/engine.dart';
import '../game/narrate.dart' as narrate;
import '../models/seat_info.dart';
import '../theme.dart';
import 'anim.dart';
import 'avatar_circle.dart';
import 'big_button.dart';

class RoundOverPanel extends StatelessWidget {
  const RoundOverPanel({
    super.key,
    required this.view,
    required this.seats,
    this.onNextRound,
    this.onPlayAgain,
    this.onLeave,
    this.footer,
    this.waitingFor,
  });

  final PublicView view;
  final List<SeatInfo> seats;

  /// Set when another round of the same match is still to come.
  final VoidCallback? onNextRound;
  final VoidCallback? onPlayAgain;
  final VoidCallback? onLeave;

  /// Coins won or lost, or anything else that belongs under the placings.
  final Widget? footer;

  /// Shown instead of the buttons when somebody else has to act first.
  final String? waitingFor;

  bool get _matchOver => view.status == GameStatus.finished;

  @override
  Widget build(BuildContext context) {
    final youWon = view.winnerSeat == view.yourSeat && view.yourSeat != null;
    final winner = narrate.seatName(seats, view.winnerSeat);
    final firsts = _matchOver ? _firstPlaceSeats() : const <int>[];
    final tookMatch = view.yourSeat != null && firsts.contains(view.yourSeat);
    final title = _matchOver
        ? switch (firsts.length) {
            0 => 'Match over',
            1 =>
              tookMatch
                  ? 'You win the match'
                  : '${narrate.seatName(seats, firsts.single)} wins the match',
            _ => tookMatch ? 'You tie for first' : 'A tie for first place',
          }
        : (youWon ? 'You won the round' : '$winner won the round');

    // Once the match is over the confetti belongs to the match, not to whoever
    // happened to win the last round of it.
    final celebrate = _matchOver ? tookMatch : youWon;

    return ColoredBox(
      color: Palette.inkDark.withValues(alpha: 0.72),
      child: Stack(
        children: [
          if (celebrate) const Positioned.fill(child: Celebrate()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: PopIn(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 480),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Palette.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          celebrate
                              ? Icons.emoji_events_rounded
                              : Icons.flag_rounded,
                          size: 44,
                          color: Palette.amberDeep,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        if (view.rounds > 1)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Round ${view.round} of ${view.rounds}',
                              style: const TextStyle(
                                fontSize: 16,
                                color: Palette.inkSoft,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        const SizedBox(height: 14),
                        ..._rows(context),
                        if (footer != null) ...[
                          const SizedBox(height: 12),
                          footer!,
                        ],
                        const SizedBox(height: 16),
                        if (waitingFor != null)
                          Text(
                            waitingFor!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Palette.inkSoft,
                            ),
                          )
                        else ...[
                          if (onNextRound != null)
                            BigButton(
                              label: 'Next round',
                              icon: Icons.play_arrow_rounded,
                              onPressed: onNextRound,
                            ),
                          if (onPlayAgain != null)
                            BigButton(
                              label: 'Play again',
                              icon: Icons.refresh_rounded,
                              onPressed: onPlayAgain,
                            ),
                          if (onLeave != null) ...[
                            const SizedBox(height: 10),
                            PillButton(
                              label: 'Back to home',
                              icon: Icons.home_rounded,
                              colour: Palette.ink,
                              onPressed: onLeave,
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Standings arrive indexed by seat, not in finishing order, so first place is
  /// looked up by rank. More than one seat can hold it after a tied match.
  List<int> _firstPlaceSeats() {
    final standings = view.standings;
    if (standings == null) return const [];
    return [
      for (final standing in standings)
        if (standing.rank == 1) standing.seatIndex,
    ];
  }

  List<Widget> _rows(BuildContext context) {
    final standings = view.standings;
    if (_matchOver && standings != null) {
      final placed = standings.toList()
        ..sort(
          (a, b) => a.rank == b.rank
              ? a.seatIndex.compareTo(b.seatIndex)
              : a.rank.compareTo(b.rank),
        );
      return [
        for (final (index, standing) in placed.indexed)
          FadeSlideIn(
            delay: Duration(milliseconds: 60 * index),
            child: _ResultRow(
              seat: _seatOf(standing.seatIndex),
              place: standing.rank,
              detail: 'Score ${standing.score}',
              you: standing.seatIndex == view.yourSeat,
            ),
          ),
      ];
    }

    final ranks = view.ranks ?? const <int>[];
    final order = [for (var seat = 0; seat < seats.length; seat += 1) seat]
      ..sort((a, b) {
        final left = a < ranks.length ? ranks[a] : 99;
        final right = b < ranks.length ? ranks[b] : 99;
        return left == right ? a.compareTo(b) : left.compareTo(right);
      });
    return [
      for (final (index, seat) in order.indexed)
        FadeSlideIn(
          delay: Duration(milliseconds: 60 * index),
          child: _ResultRow(
            seat: _seatOf(seat),
            place: seat < ranks.length ? ranks[seat] : 0,
            detail: _cardsLeft(seat),
            you: seat == view.yourSeat,
          ),
        ),
    ];
  }

  String _cardsLeft(int seat) {
    final left = seat < view.handCounts.length ? view.handCounts[seat] : 0;
    if (left == 0) return 'Out of cards';
    return '$left card${left == 1 ? '' : 's'} left';
  }

  SeatInfo _seatOf(int index) => index >= 0 && index < seats.length
      ? seats[index]
      : SeatInfo(index: index, name: 'Seat ${index + 1}', avatar: index);
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.seat,
    required this.place,
    required this.detail,
    required this.you,
  });

  final SeatInfo seat;
  final int place;
  final String detail;
  final bool you;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          '${narrate.placeLabel(place)}, ${you ? 'you' : seat.name}, $detail',
      // The label above is the whole row. Left alone, the reader would say the
      // place, the name and the detail as three separate stops.
      child: ExcludeSemantics(
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: you ? Palette.cream : Palette.mist,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: you ? Palette.amber : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (place == 1)
                      const Icon(
                        Icons.workspace_premium_rounded,
                        size: 20,
                        color: Palette.amberDeep,
                      ),
                    Flexible(
                      child: Text(
                        narrate.placeLabel(place),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        softWrap: false,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Palette.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              AvatarCircle(avatar: seat.avatar, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  you ? 'You' : seat.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Gives way to the name rather than pushing the row over its width.
              Flexible(
                child: Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Palette.inkSoft,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
