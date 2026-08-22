/// Opponent seats and the turn countdown.
///
/// A seat shows name, avatar and card count, and nothing else: card counts are
/// public, hands are not. The countdown ring ticks itself so a turn timer never
/// rebuilds the board ten times a second, and it always prints the seconds as
/// well, because a shrinking arc alone is not readable to everybody.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/seat_info.dart';
import '../theme.dart';
import 'anim.dart';
import 'avatar_circle.dart';
import 'card_face.dart';

class SeatStrip extends StatelessWidget {
  const SeatStrip({
    super.key,
    required this.seats,
    required this.handCounts,
    required this.currentTurnSeat,
    required this.turnDeadline,
    required this.timerSeconds,
    required this.thinkingSeat,
    this.hideSeat,
    this.roundLive = true,
    this.seatKeys,
  });

  final List<SeatInfo> seats;
  final List<int> handCounts;
  final int currentTurnSeat;

  /// Wall clock time the active turn runs out, or null when the clock is stopped.
  final int? turnDeadline;
  final int timerSeconds;
  final int? thinkingSeat;

  /// The local player, drawn by the hand area instead of here.
  final int? hideSeat;

  final bool roundLive;

  /// Keys on each badge, so the board can fly a card out of the right seat.
  final Map<int, GlobalKey>? seatKeys;

  @override
  Widget build(BuildContext context) {
    final shown = seats.where((seat) => seat.index != hideSeat).toList();
    final size = shown.length > 4 ? 42.0 : 52.0;

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 6,
      children: [
        for (final seat in shown)
          SeatBadge(
            key: seatKeys?[seat.index],
            seat: seat,
            size: size,
            cardCount: seat.index < handCounts.length
                ? handCounts[seat.index]
                : 0,
            active: roundLive && seat.index == currentTurnSeat,
            thinking: seat.index == thinkingSeat,
            deadline: turnDeadline,
            timerSeconds: timerSeconds,
          ),
      ],
    );
  }
}

class SeatBadge extends StatelessWidget {
  const SeatBadge({
    super.key,
    required this.seat,
    required this.cardCount,
    required this.active,
    required this.thinking,
    required this.deadline,
    required this.timerSeconds,
    this.size = 52,
  });

  final SeatInfo seat;
  final int cardCount;
  final bool active;
  final bool thinking;
  final int? deadline;
  final int timerSeconds;
  final double size;

  @override
  Widget build(BuildContext context) {
    final avatar = AvatarCircle(
      avatar: seat.avatar,
      size: size,
      faded: !seat.connected,
    );

    return Semantics(
      label:
          '${seat.name}, $cardCount card${cardCount == 1 ? '' : 's'}'
          '${active ? ', playing now' : ''}'
          '${seat.connected ? '' : ', disconnected'}',
      // The label above says the whole seat in one go. Without this the reader
      // would say the name and the count again on their own.
      child: ExcludeSemantics(
        child: AnimatedScale(
          scale: active ? 1 : 0.94,
          duration: Anim.swap,
          curve: Curves.easeOut,
          child: SizedBox(
            width: size + 30,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                active
                    ? TurnRing(
                        size: size + 12,
                        deadline: deadline,
                        totalMillis: timerSeconds * 1000,
                        child: avatar,
                      )
                    : Padding(padding: const EdgeInsets.all(6), child: avatar),
                const SizedBox(height: 2),
                Text(
                  seat.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.1,
                    fontWeight: active ? FontWeight.w900 : FontWeight.w600,
                    color: active ? Palette.lime : Palette.cream,
                  ),
                ),
                const SizedBox(height: 2),
                _CountPill(count: cardCount, thinking: thinking),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count, required this.thinking});

  final int count;
  final bool thinking;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Palette.feltDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Palette.cream.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (thinking) const _ThinkingDots() else const CardBack(width: 11),
          const SizedBox(width: 5),
          AnimatedSwitcher(
            duration: Anim.swap,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SizeTransition(
                sizeFactor: animation,
                axis: Axis.horizontal,
                child: child,
              ),
            ),
            child: Text(
              '$count',
              key: ValueKey(count),
              style: const TextStyle(
                fontSize: 15,
                height: 1.1,
                fontWeight: FontWeight.w800,
                color: Palette.cream,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots();

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final phase = (_controller.value * 3).floor();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i += 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == phase
                        ? Palette.lime
                        : Palette.cream.withValues(alpha: 0.4),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A ring that empties as the turn runs out, with the seconds in the corner.
class TurnRing extends StatefulWidget {
  const TurnRing({
    super.key,
    required this.size,
    required this.deadline,
    required this.totalMillis,
    required this.child,
    this.showSeconds = true,
  });

  final double size;

  /// Wall clock millis the turn ends. Null freezes the ring, for a paused game.
  final int? deadline;
  final int totalMillis;
  final Widget child;
  final bool showSeconds;

  @override
  State<TurnRing> createState() => _TurnRingState();
}

class _TurnRingState extends State<TurnRing> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(TurnRing old) {
    super.didUpdateWidget(old);
    if (old.deadline != widget.deadline) _start();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _start() {
    _ticker?.cancel();
    if (widget.deadline == null) return;
    _ticker = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (mounted) setState(() {});
    });
  }

  int get _millisLeft {
    final deadline = widget.deadline;
    if (deadline == null) return widget.totalMillis;
    final left = deadline - DateTime.now().millisecondsSinceEpoch;
    return left > 0 ? left : 0;
  }

  @override
  Widget build(BuildContext context) {
    final left = _millisLeft;
    final total = widget.totalMillis > 0 ? widget.totalMillis : 1;
    final fraction = (left / total).clamp(0.0, 1.0);
    final seconds = (left / 1000).ceil();
    final colour = fraction > 0.5
        ? Palette.lime
        : fraction > 0.25
        ? Palette.amber
        : Palette.coral;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Transform.translate(
        // The last few seconds wobble, so a player who is not watching the arc
        // still notices the clock running down.
        offset: Offset(
          left > 0 && left <= 3000 ? math.sin(left / 55) * 1.6 : 0,
          0,
        ),
        child: CustomPaint(
          painter: _RingPainter(fraction: fraction, colour: colour),
          child: Stack(
            alignment: Alignment.center,
            children: [
              widget.child,
              if (widget.showSeconds)
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: colour,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: Palette.inkDark, width: 1),
                    ),
                    child: Text(
                      widget.deadline == null ? '||' : '$seconds',
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                        color: Palette.inkDark,
                      ),
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

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.fraction, required this.colour});

  final double fraction;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final centre = rect.center;
    final radius = size.shortestSide / 2 - 2;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = Palette.feltDark.withValues(alpha: 0.8);
    canvas.drawCircle(centre, radius, track);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = colour;
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      -math.pi / 2,
      -2 * math.pi * fraction,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.colour != colour;
}
