/// The player's own hand, fixed along the bottom of the board.
///
/// Cards never overlap, so every card in hand is fully visible and easy to hit.
/// The strip scrolls horizontally when a hand is too wide, and because a long
/// hand can hide the playable cards off screen there is a counter above it that
/// scrolls the next playable card into view.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../game/cards.dart' as cards;
import '../game/narrate.dart' as narrate;
import '../theme.dart';
import 'anim.dart';
import 'card_face.dart';

const double _cardGap = 5;
const double _suitGap = 18;
const double _edgePad = 12;
const Duration _exitTime = Duration(milliseconds: 240);

class HandStrip extends StatefulWidget {
  const HandStrip({
    super.key,
    required this.hand,
    required this.legal,
    required this.cardWidth,
    required this.yourTurn,
    required this.dealToken,
    required this.onPlay,
    required this.onRefused,
  });

  final List<String> hand;
  final List<String> legal;
  final double cardWidth;
  final bool yourTurn;

  /// Changes when a new hand is dealt, which is what replays the deal animation.
  final int dealToken;

  /// The rect is where the card was on screen, so the board can fly it to the
  /// table from the exact place the finger left it.
  final void Function(String card, Rect from) onPlay;
  final void Function(String card) onRefused;

  @override
  State<HandStrip> createState() => _HandStripState();
}

class _HandStripState extends State<HandStrip> {
  final ScrollController _scroll = ScrollController();
  final Map<String, double> _offsets = {};

  /// Cards in the order they were dealt, including ones on their way out.
  List<String> _display = [];
  final Set<String> _leaving = {};
  final List<Timer> _timers = [];

  double _viewport = 0;
  int _cycle = 0;
  String? _pressed;

  @override
  void initState() {
    super.initState();
    _display = List<String>.of(widget.hand);
  }

  @override
  void didUpdateWidget(HandStrip old) {
    super.didUpdateWidget(old);

    if (widget.dealToken != old.dealToken) {
      _leaving.clear();
      _display = List<String>.of(widget.hand);
    } else {
      // A hand only ever shrinks during a round. A card that has gone keeps its
      // place for a moment and collapses, so the row does not jump.
      for (final code in _display) {
        if (!widget.hand.contains(code) && _leaving.add(code)) {
          final timer = Timer(_exitTime, () {
            if (!mounted) return;
            setState(() {
              _leaving.remove(code);
              _display.remove(code);
            });
          });
          _timers.add(timer);
        }
      }
      for (final code in widget.hand) {
        if (!_display.contains(code)) _display.add(code);
      }
    }

    final becameOurs = widget.yourTurn && !old.yourTurn;
    final legalChanged = widget.legal.join(',') != old.legal.join(',');
    if (widget.yourTurn && (becameOurs || legalChanged)) {
      _cycle = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealLegal());
    }
  }

  @override
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _revealLegal({bool advance = false}) {
    if (!mounted || widget.legal.isEmpty || !_scroll.hasClients) return;
    if (advance) _cycle = (_cycle + 1) % widget.legal.length;
    final target = _offsets[widget.legal[_cycle % widget.legal.length]];
    if (target == null) return;
    final max = _scroll.position.maxScrollExtent;
    if (max <= 0) return;
    final to = (target - _viewport / 2 + widget.cardWidth / 2).clamp(0.0, max);
    _scroll.animateTo(
      to,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
    );
  }

  /// Cards in dealt order, grouped by suit, with the left offset of each card
  /// recorded so the reveal button knows where to scroll.
  List<Widget> _buildCards() {
    _offsets.clear();
    final children = <Widget>[];
    var x = _edgePad;
    String? previousSuit;
    var index = 0;

    for (final code in _display) {
      if (_leaving.contains(code)) {
        // Holds the gap open for a moment, then closes it.
        children.add(
          TweenAnimationBuilder<double>(
            key: ValueKey('gap-$code'),
            tween: Tween(begin: widget.cardWidth + _cardGap, end: 0),
            duration: _exitTime,
            curve: Curves.easeInCubic,
            builder: (context, value, _) => SizedBox(width: value),
          ),
        );
        continue;
      }

      final suit = cards.suitOf(code);
      if (previousSuit != null && suit != previousSuit) {
        children.add(const SizedBox(width: _suitGap - _cardGap));
        x += _suitGap - _cardGap;
      }
      previousSuit = suit;
      _offsets[code] = x;

      final playable = widget.legal.contains(code);
      children.add(
        Padding(
          key: ValueKey('card-$code'),
          padding: const EdgeInsets.only(right: _cardGap),
          child: FadeSlideIn(
            key: ValueKey('in-${widget.dealToken}-$code'),
            // Dealt one after another, left to right.
            delay: Duration(milliseconds: 24 * index),
            duration: Anim.deal,
            dy: -40,
            child: _HandCard(
              code: code,
              width: widget.cardWidth,
              playable: playable,
              yourTurn: widget.yourTurn,
              pressed: _pressed == code,
              onPressChange: (down) =>
                  setState(() => _pressed = down ? code : null),
              onTap: (rect) {
                if (playable && widget.yourTurn) {
                  widget.onPlay(code, rect);
                } else {
                  widget.onRefused(code);
                }
              },
            ),
          ),
        ),
      );
      x += widget.cardWidth + _cardGap;
      index += 1;
    }
    return children;
  }

  @override
  Widget build(BuildContext context) {
    final cardHeight = Sizes.cardHeightFor(widget.cardWidth);
    final count = widget.legal.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _HandHeader(
          cardCount: widget.hand.length,
          legalCount: count,
          yourTurn: widget.yourTurn,
          onReveal: count > 0 ? () => _revealLegal(advance: true) : null,
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: cardHeight + 14,
          child: LayoutBuilder(
            builder: (context, constraints) {
              _viewport = constraints.maxWidth;
              return SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(width: _edgePad - _cardGap),
                      ..._buildCards(),
                      const SizedBox(width: _edgePad - _cardGap),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HandCard extends StatelessWidget {
  const _HandCard({
    required this.code,
    required this.width,
    required this.playable,
    required this.yourTurn,
    required this.pressed,
    required this.onPressChange,
    required this.onTap,
  });

  final String code;
  final double width;
  final bool playable;
  final bool yourTurn;
  final bool pressed;
  final void Function(bool down) onPressChange;
  final void Function(Rect from) onTap;

  Rect _rectOf(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return Rect.zero;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: narrate.cardSemantics(code, playable: playable && yourTurn),
      child: GestureDetector(
        onTapDown: (_) => onPressChange(true),
        onTapCancel: () => onPressChange(false),
        onTap: () {
          final rect = _rectOf(context);
          onPressChange(false);
          onTap(rect);
        },
        child: AnimatedSlide(
          offset: Offset(0, pressed ? -0.06 : 0),
          duration: const Duration(milliseconds: 110),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CardFace(
                code: code,
                width: width,
                highlight: playable && yourTurn,
                dim: !playable,
                lifted: pressed,
              ),
              if (playable && yourTurn)
                const Positioned(top: -4, right: -4, child: _PlayableTick()),
            ],
          ),
        ),
      ),
    );
  }
}

/// The badge on a playable card. It breathes gently so a player who cannot see
/// the glow still has movement telling them where to tap.
class _PlayableTick extends StatefulWidget {
  const _PlayableTick();

  @override
  State<_PlayableTick> createState() => _PlayableTickState();
}

class _PlayableTickState extends State<_PlayableTick>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) =>
          Transform.scale(scale: 0.92 + 0.12 * _controller.value, child: child),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(
          color: Palette.lime,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.arrow_upward_rounded,
          size: 14,
          color: Palette.inkDark,
        ),
      ),
    );
  }
}

class _HandHeader extends StatelessWidget {
  const _HandHeader({
    required this.cardCount,
    required this.legalCount,
    required this.yourTurn,
    required this.onReveal,
  });

  final int cardCount;
  final int legalCount;
  final bool yourTurn;
  final VoidCallback? onReveal;

  @override
  Widget build(BuildContext context) {
    final playable = legalCount > 0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Both sides give way rather than overflow, because large system text can
        // make either of them wider than half the screen.
        Flexible(
          child: Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Text(
              'Your cards: $cardCount',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Palette.cream,
              ),
            ),
          ),
        ),
        if (playable)
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: TextButton.icon(
                onPressed: onReveal,
                style: TextButton.styleFrom(
                  foregroundColor: Palette.inkDark,
                  backgroundColor: yourTurn ? Palette.lime : Palette.mist,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  minimumSize: const Size(0, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
                icon: const Icon(Icons.search_rounded, size: 20),
                label: Text(
                  '$legalCount playable',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          )
        else
          const Flexible(
            child: Padding(
              padding: EdgeInsets.only(right: 14),
              child: Text(
                'Nothing playable',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Palette.cream,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
