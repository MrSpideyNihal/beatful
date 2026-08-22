/// The animation pieces.
///
/// Every animation here has a job: show where a card came from, show what a seat
/// just did, or draw the eye to something that changed. Nothing loops forever
/// behind the game, and nothing blocks a tap while it runs, so a fast player is
/// never waiting for the screen to catch up.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'card_face.dart';

abstract final class Anim {
  static const flight = Duration(milliseconds: 340);
  static const pop = Duration(milliseconds: 260);
  static const enter = Duration(milliseconds: 320);
  static const float = Duration(milliseconds: 1000);
  static const swap = Duration(milliseconds: 220);
  static const deal = Duration(milliseconds: 520);

  /// Long enough to read a balance ticking up, short enough not to be waited on.
  static const count = Duration(milliseconds: 560);
}

/// A number that walks to its new value instead of jumping. Used for coin
/// balances, where the change is the thing worth noticing.
class CountUp extends StatelessWidget {
  const CountUp({
    super.key,
    required this.value,
    required this.style,
    this.prefix = '',
  });

  final int value;
  final TextStyle style;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: value.toDouble(), end: value.toDouble()),
      duration: Anim.count,
      curve: Curves.easeOutCubic,
      builder: (context, shown, _) =>
          Text('$prefix${shown.round()}', style: style),
    );
  }
}

/// A one shot halo around whatever has just become the thing to look at: the
/// prompt when your turn arrives, the Pass button when passing is the only move
/// left. Runs once and leaves nothing behind, so the board is never breathing at
/// a player who is trying to think.
class AttentionPulse extends StatelessWidget {
  const AttentionPulse({
    super.key,
    required this.token,
    required this.child,
    this.radius = 14,
    this.colour = Palette.lime,
  });

  /// Change this to pulse again. Null means there is nothing to point at, and
  /// the child is returned untouched.
  final Object? token;
  final Widget child;
  final double radius;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    if (token == null) return child;
    return TweenAnimationBuilder<double>(
      key: ValueKey(token),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 720),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        // Two halves: swell out, then settle. The glow fades the whole way, so
        // the panel ends up looking exactly as it did before.
        final wave = math.sin(value * math.pi);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              BoxShadow(
                color: colour.withValues(alpha: wave * 0.7),
                blurRadius: 6 + 16 * wave,
                spreadRadius: 1 + 3 * wave,
              ),
            ],
          ),
          child: child,
        );
      },
      child: child,
    );
  }
}

/// Fade and rise into place. Used for screen content and list rows, with a delay
/// to stagger a group.
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = Anim.enter,
    this.dy = 18,
    this.dx = 0,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double dy;
  final double dx;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  Timer? _wait;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _wait = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    return AnimatedBuilder(
      animation: curve,
      builder: (context, child) => Opacity(
        opacity: curve.value,
        child: Transform.translate(
          offset: Offset(
            widget.dx * (1 - curve.value),
            widget.dy * (1 - curve.value),
          ),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Scale up from small with a slight overshoot. For panels and badges arriving.
class PopIn extends StatelessWidget {
  const PopIn({
    super.key,
    required this.child,
    this.duration = Anim.pop,
    this.from = 0.86,
  });

  final Widget child;
  final Duration duration;
  final double from;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: from, end: 1),
      duration: duration,
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Transform.scale(
        scale: value,
        child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
      ),
      child: child,
    );
  }
}

/// A short sideways shake, for a tap the game had to refuse.
class Shake extends StatelessWidget {
  const Shake({super.key, required this.token, required this.child});

  /// Change this to shake again. Null means nothing to react to.
  final Object? token;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (token == null) return child;
    return TweenAnimationBuilder<double>(
      key: ValueKey(token),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.linear,
      builder: (context, value, child) => Transform.translate(
        offset: Offset(math.sin(value * math.pi * 6) * 9 * (1 - value), 0),
        child: child,
      ),
      child: child,
    );
  }
}

/// A one shot pulse: a ring that expands and fades where a card just landed.
class LandPulse extends StatelessWidget {
  const LandPulse({super.key, required this.token, required this.child});

  /// Change this to run the pulse again. The card code works well.
  final Object token;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(token),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 460),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        final grow = 1 + 0.10 * math.sin(value * math.pi);
        return Transform.scale(
          scale: grow,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Sizes.cardRadius),
              boxShadow: [
                BoxShadow(
                  color: Palette.amber.withValues(alpha: (1 - value) * 0.85),
                  blurRadius: 6 + 14 * value,
                  spreadRadius: 1 + 4 * value,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// A card travelling from a seat, or from a hand, to its place on the table.
///
/// Returns a Positioned, so it goes straight into the board Stack. Opponent
/// cards start face down and turn over on the way, which is what makes it read
/// as their card rather than a card appearing out of nowhere.
class CardFlight extends StatefulWidget {
  const CardFlight({
    super.key,
    required this.code,
    required this.from,
    required this.to,
    required this.onDone,
    this.flip = false,
    this.duration = Anim.flight,
  });

  final String code;
  final Rect from;
  final Rect to;
  final VoidCallback onDone;
  final bool flip;
  final Duration duration;

  @override
  State<CardFlight> createState() => _CardFlightState();
}

class _CardFlightState extends State<CardFlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onDone();
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    return AnimatedBuilder(
      animation: curve,
      builder: (context, _) {
        final t = curve.value;
        final rect = Rect.lerp(widget.from, widget.to, t)!;
        // A shallow arc, highest in the middle, so the card looks thrown rather
        // than dragged along a ruler.
        final lift = -26 * math.sin(t * math.pi);
        final turn = widget.flip ? (1 - t) * math.pi : 0.0;
        final showBack = widget.flip && turn > math.pi / 2;

        return Positioned(
          left: rect.left,
          top: rect.top + lift,
          width: rect.width,
          height: rect.height,
          child: IgnorePointer(
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateY(turn),
              child: showBack
                  ? CardBack(width: rect.width)
                  : CardFace(
                      code: widget.code,
                      width: rect.width,
                      lifted: true,
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// A short label that rises off a seat and fades, for a pass or a timeout.
class FloatUpLabel extends StatefulWidget {
  const FloatUpLabel({
    super.key,
    required this.text,
    required this.anchor,
    required this.onDone,
    this.icon,
    this.colour = Palette.cream,
  });

  final String text;
  final IconData? icon;

  /// Where it starts, in the coordinate space of the surrounding Stack.
  final Rect anchor;
  final VoidCallback onDone;
  final Color colour;

  @override
  State<FloatUpLabel> createState() => _FloatUpLabelState();
}

class _FloatUpLabelState extends State<FloatUpLabel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Anim.float,
  );

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onDone();
    });
    _controller.forward();
  }

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
        final t = _controller.value;
        final fade = t < 0.15 ? t / 0.15 : (t > 0.7 ? (1 - t) / 0.3 : 1.0);
        return Positioned(
          left: widget.anchor.center.dx - 100,
          top: widget.anchor.top - 10 - 34 * Curves.easeOut.transform(t),
          width: 200,
          child: IgnorePointer(
            child: Opacity(
              opacity: fade.clamp(0.0, 1.0),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Palette.inkDark.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: widget.colour, width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, size: 16, color: widget.colour),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          widget.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            color: widget.colour,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Falling chips behind the win panel. Runs once, then stops on its own.
class Celebrate extends StatefulWidget {
  const Celebrate({super.key, this.count = 34});

  final int count;

  @override
  State<Celebrate> createState() => _CelebrateState();
}

class _CelebrateState extends State<Celebrate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..forward();

  late final List<_Chip> _chips = _build();

  List<_Chip> _build() {
    // Fixed pattern rather than a random one: it looks the same every time, and
    // nothing here needs to surprise the player.
    const colours = [
      Palette.amber,
      Palette.lime,
      Palette.coral,
      Palette.blue,
      Palette.violet,
      Palette.teal,
    ];
    return [
      for (var i = 0; i < widget.count; i += 1)
        _Chip(
          x: ((i * 37) % 100) / 100,
          delay: ((i * 17) % 60) / 100,
          size: 8 + (i % 4) * 3,
          spin: (i % 5) - 2,
          colour: colours[i % colours.length],
        ),
    ];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _ChipPainter(chips: _chips, t: _controller.value),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _Chip {
  const _Chip({
    required this.x,
    required this.delay,
    required this.size,
    required this.spin,
    required this.colour,
  });

  final double x;
  final double delay;
  final double size;
  final int spin;
  final Color colour;
}

class _ChipPainter extends CustomPainter {
  const _ChipPainter({required this.chips, required this.t});

  final List<_Chip> chips;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    for (final chip in chips) {
      final local = (t - chip.delay) / (1 - chip.delay);
      if (local <= 0) continue;
      final fall = Curves.easeIn.transform(local.clamp(0.0, 1.0));
      final y = -20 + (size.height + 40) * fall;
      final sway = math.sin((local + chip.x) * math.pi * 4) * 14;
      final x = chip.x * size.width + sway;
      final paint = Paint()
        ..color = chip.colour.withValues(
          alpha: local > 0.85 ? (1 - local) / 0.15 : 1,
        );

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(local * chip.spin * math.pi);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: chip.size,
            height: chip.size * 0.6,
          ),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ChipPainter old) => old.t != t;
}
