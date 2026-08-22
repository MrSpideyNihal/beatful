/// The panel that covers the board when a round or a match ends.
///
/// Same panel for solo and online: it takes a view, the seats, and what the
/// buttons should do. Placings are printed with their number as well as their
/// order, and the winner row is marked with an icon, not just a colour.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/engine.dart';
import '../game/narrate.dart' as narrate;
import '../models/seat_info.dart';
import '../services/cues.dart';
import '../theme.dart';
import 'anim.dart';
import 'avatar_circle.dart';
import 'big_button.dart';

class RoundOverPanel extends ConsumerStatefulWidget {
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

  @override
  ConsumerState<RoundOverPanel> createState() => _RoundOverPanelState();
}

class _RoundOverPanelState extends ConsumerState<RoundOverPanel> {
  bool get _matchOver => widget.view.status == GameStatus.finished;

  List<int> _firstPlaceSeats() {
    final standings = widget.view.standings;
    if (standings == null) return const [];
    return [
      for (final standing in standings)
        if (standing.rank == 1) standing.seatIndex,
    ];
  }

  bool get _celebrate {
    final youWon =
        widget.view.winnerSeat == widget.view.yourSeat &&
        widget.view.yourSeat != null;
    final firsts = _matchOver ? _firstPlaceSeats() : const <int>[];
    final tookMatch =
        widget.view.yourSeat != null && firsts.contains(widget.view.yourSeat);
    return _matchOver ? tookMatch : youWon;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cues = ref.read(cuesProvider);
      if (_celebrate) {
        cues.win();
      } else {
        cues.lose();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final seats = widget.seats;
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

    final celebrate = _celebrate;

    return ColoredBox(
      color: Palette.inkDark.withValues(alpha: 0.82),
      child: Stack(
        children: [
          if (celebrate) const Positioned.fill(child: Celebrate(count: 48)),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: PopIn(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 480),
                    decoration: BoxDecoration(
                      color: Palette.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: celebrate ? Palette.amber : Palette.coral.withValues(alpha: 0.4),
                        width: celebrate ? 2.5 : 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: celebrate
                              ? Palette.amber.withValues(alpha: 0.35)
                              : Colors.black.withValues(alpha: 0.4),
                          blurRadius: celebrate ? 28 : 20,
                          spreadRadius: celebrate ? 4 : 1,
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Dynamic Header Banner
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                          decoration: BoxDecoration(
                            gradient: celebrate
                                ? const LinearGradient(
                                    colors: [
                                      Palette.amberDeep,
                                      Palette.amber,
                                      Color(0xFFFFD54F),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : const LinearGradient(
                                    colors: [
                                      Color(0xFF1E212B),
                                      Color(0xFF2B2D42),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                          ),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(alpha: 0.2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: (celebrate ? Palette.amber : Colors.black)
                                          .withValues(alpha: 0.3),
                                      blurRadius: 16,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  celebrate
                                      ? Icons.emoji_events_rounded
                                      : Icons.sports_score_rounded,
                                  size: 48,
                                  color: celebrate ? Colors.white : Palette.amber,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                celebrate ? (tookMatch ? 'VICTORY!' : 'ROUND WINNER!') : title,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                  color: Colors.white,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black.withValues(alpha: 0.5),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                              ),
                              if (celebrate) ...[
                                const SizedBox(height: 4),
                                Text(
                                  title,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white.withValues(alpha: 0.95),
                                  ),
                                ),
                              ],
                              if (view.rounds > 1) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'Round ${view.round} of ${view.rounds}',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ..._rows(context),
                              if (widget.footer != null) ...[
                                const SizedBox(height: 12),
                                widget.footer!,
                              ],
                              const SizedBox(height: 16),
                              if (widget.waitingFor != null)
                                Text(
                                  widget.waitingFor!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: Palette.inkSoft,
                                  ),
                                )
                              else ...[
                                if (widget.onNextRound != null)
                                  BigButton(
                                    label: 'Next round',
                                    icon: Icons.play_arrow_rounded,
                                    onPressed: widget.onNextRound,
                                  ),
                                if (widget.onPlayAgain != null)
                                  BigButton(
                                    label: 'Play again',
                                    icon: Icons.refresh_rounded,
                                    onPressed: widget.onPlayAgain,
                                  ),
                                if (widget.onLeave != null) ...[
                                  const SizedBox(height: 10),
                                  PillButton(
                                    label: 'Back to home',
                                    icon: Icons.home_rounded,
                                    colour: Palette.ink,
                                    onPressed: widget.onLeave,
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
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

  List<Widget> _rows(BuildContext context) {
    final standings = widget.view.standings;
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
              you: standing.seatIndex == widget.view.yourSeat,
            ),
          ),
      ];
    }

    final ranks = widget.view.ranks ?? const <int>[];
    final order = [for (var seat = 0; seat < widget.seats.length; seat += 1) seat]
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
            you: seat == widget.view.yourSeat,
          ),
        ),
    ];
  }

  String _cardsLeft(int seat) {
    final left = seat < widget.view.handCounts.length ? widget.view.handCounts[seat] : 0;
    if (left == 0) return 'Out of cards';
    return '$left card${left == 1 ? '' : 's'} left';
  }

  SeatInfo _seatOf(int index) => index >= 0 && index < widget.seats.length
      ? widget.seats[index]
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
    // Custom podium gradients and icons for 1st, 2nd, and 3rd place
    final (bgGradient, borderColor, placeIcon, iconColor) = switch (place) {
      1 => (
          const LinearGradient(colors: [Color(0xFFFFF9E6), Color(0xFFFFECB3)]),
          Palette.amber,
          Icons.workspace_premium_rounded,
          Palette.amberDeep,
        ),
      2 => (
          const LinearGradient(colors: [Color(0xFFF5F5F5), Color(0xFFE0E0E0)]),
          const Color(0xFFBDBDBD),
          Icons.military_tech_rounded,
          const Color(0xFF616161),
        ),
      3 => (
          const LinearGradient(colors: [Color(0xFFFFF3E0), Color(0xFFFFE0B2)]),
          const Color(0xFFFFB74D),
          Icons.military_tech_rounded,
          const Color(0xFFE65100),
        ),
      _ => (
          null,
          you ? Palette.amber : Colors.transparent,
          null,
          Palette.ink,
        ),
    };

    return Semantics(
      label:
          '${narrate.placeLabel(place)}, ${you ? 'you' : seat.name}, $detail',
      child: ExcludeSemantics(
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: bgGradient == null ? (you ? Palette.cream : Palette.mist) : null,
            gradient: bgGradient,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: you ? Palette.amber : borderColor,
              width: you ? 2.5 : (place <= 3 ? 1.5 : 1),
            ),
            boxShadow: you
                ? [
                    BoxShadow(
                      color: Palette.amber.withValues(alpha: 0.25),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 52,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (placeIcon != null)
                      Icon(
                        placeIcon,
                        size: 22,
                        color: iconColor,
                      ),
                    const SizedBox(width: 2),
                    Flexible(
                      child: Text(
                        narrate.placeLabel(place),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: place == 1 ? Palette.amberDeep : Palette.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              AvatarCircle(avatar: seat.avatar, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        you ? 'You' : seat.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: you ? FontWeight.w900 : FontWeight.w800,
                          color: Palette.ink,
                        ),
                      ),
                    ),
                    if (you) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Palette.amber,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'YOU',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
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
