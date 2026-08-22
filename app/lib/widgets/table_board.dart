/// The table: one row per suit, each laid out on a fixed rank grid.
///
/// A row always puts ace on the left and king on the right, so a suit visibly
/// grows outward from its 7 and the gaps show exactly which cards are still
/// missing. The next card each direction wants is outlined, which is what makes
/// the rules readable without a tutorial.
library;

import 'package:flutter/material.dart';

import '../game/cards.dart' as cards;
import '../game/narrate.dart' as narrate;
import '../game/rules.dart' as rules;
import '../theme.dart';
import 'anim.dart';
import 'card_face.dart';

/// Row geometry, in one place, because the board draws the cards and the board
/// screen has to work out where a flying card is going to land.
abstract final class TableMetrics {
  static const badge = 34.0;
  static const badgeGap = 8.0;
  static const rowGap = 3.0;

  static double rowWidth(double boardWidth, double cardWidth) =>
      (boardWidth - badge - badgeGap).clamp(cardWidth, double.infinity);

  /// Thirteen ranks share a row, so the cards overlap by a fixed step and each
  /// one still shows its own top left corner.
  static double step(double rowWidth, double cardWidth) =>
      ((rowWidth - cardWidth) / 12).clamp(6.0, cardWidth);

  static double left(double step, int rank) => (rank - 1) * step;
}

class TableBoard extends StatelessWidget {
  const TableBoard({
    super.key,
    required this.table,
    required this.cardWidth,
    this.lastCard,
    this.hiddenCard,
    this.rowKeys,
  });

  final rules.TableState table;
  final double cardWidth;

  /// The card played most recently, ringed so the eye can find it.
  final String? lastCard;

  /// Left out of the row while its flight animation is still in the air.
  final String? hiddenCard;

  /// Keys on each suit row, so the screen can find where a card lands.
  final Map<String, GlobalKey>? rowKeys;

  @override
  Widget build(BuildContext context) {
    final cardHeight = Sizes.cardHeightFor(cardWidth);

    return LayoutBuilder(
      builder: (context, constraints) {
        final rowWidth = TableMetrics.rowWidth(constraints.maxWidth, cardWidth);
        final step = TableMetrics.step(rowWidth, cardWidth);

        return Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final suit in cards.suits)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: TableMetrics.rowGap,
                ),
                child: Row(
                  children: [
                    SuitBadge(
                      suit: suit,
                      size: TableMetrics.badge,
                      lit: table[suit].isOpen,
                    ),
                    const SizedBox(width: TableMetrics.badgeGap),
                    _SuitRow(
                      key: rowKeys?[suit],
                      table: table,
                      suit: suit,
                      width: rowWidth,
                      height: cardHeight,
                      cardWidth: cardWidth,
                      step: step,
                      lastCard: lastCard,
                      hiddenCard: hiddenCard,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SuitRow extends StatelessWidget {
  const _SuitRow({
    super.key,
    required this.table,
    required this.suit,
    required this.width,
    required this.height,
    required this.cardWidth,
    required this.step,
    required this.lastCard,
    required this.hiddenCard,
  });

  final rules.TableState table;
  final String suit;
  final double width;
  final double height;
  final double cardWidth;
  final double step;
  final String? lastCard;
  final String? hiddenCard;

  @override
  Widget build(BuildContext context) {
    final pile = table[suit];
    final needed = rules.nextNeeded(table, suit);
    final slots = <Widget>[];

    if (!pile.isOpen) {
      slots.add(
        Positioned(
          left: TableMetrics.left(step, cards.anchorRank),
          child: _EmptySlot(
            width: cardWidth,
            height: height,
            label: cards.rankLabels[cards.anchorRank]!,
            suit: suit,
            strong: true,
          ),
        ),
      );
    } else {
      for (final rank in [needed.down, needed.up]) {
        if (rank == null) continue;
        slots.add(
          Positioned(
            left: TableMetrics.left(step, rank),
            child: _EmptySlot(
              width: cardWidth,
              height: height,
              label: cards.rankLabels[rank]!,
              suit: suit,
            ),
          ),
        );
      }
      // Ascending, so a higher card overlaps the one below it.
      for (var rank = pile.low!; rank <= pile.high!; rank += 1) {
        final code = cards.makeCard(suit, rank);
        if (code == hiddenCard) {
          slots.add(
            Positioned(
              left: TableMetrics.left(step, rank),
              child: _EmptySlot(
                width: cardWidth,
                height: height,
                label: cards.rankLabels[rank]!,
                suit: suit,
              ),
            ),
          );
          continue;
        }
        slots.add(
          Positioned(
            left: TableMetrics.left(step, rank),
            child: CardFaceRing(
              code: code,
              width: cardWidth,
              ringed: code == lastCard,
            ),
          ),
        );
      }
    }

    return Semantics(
      label: _describe(pile, needed),
      // The row is described in one sentence above. The rank labels inside the
      // waiting slots are there to be looked at, not read out one by one.
      child: ExcludeSemantics(
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(clipBehavior: Clip.none, children: slots),
        ),
      ),
    );
  }

  String _describe(rules.SuitPile pile, rules.NextNeeded needed) {
    final name = narrate.suitTitle(suit);
    if (!pile.isOpen) return '$name, not started, needs the seven';
    final wants = <String>[];
    if (needed.down != null) wants.add(cards.rankLabels[needed.down!]!);
    if (needed.up != null) wants.add(cards.rankLabels[needed.up!]!);
    final range =
        '${cards.rankLabels[pile.low!]!} to ${cards.rankLabels[pile.high!]!}';
    if (wants.isEmpty) return '$name, complete';
    return '$name, $range played, needs ${wants.join(' or ')}';
  }
}

/// A card on the table. The most recent play gets a ring and a landing pulse.
class CardFaceRing extends StatelessWidget {
  const CardFaceRing({
    super.key,
    required this.code,
    required this.width,
    this.ringed = false,
  });

  final String code;
  final double width;
  final bool ringed;

  @override
  Widget build(BuildContext context) {
    final card = CardFace(code: code, width: width);
    if (!ringed) return card;
    return LandPulse(
      token: code,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(
            width < 40 ? 4 : Sizes.cardRadius,
          ),
          boxShadow: [
            BoxShadow(
              color: Palette.amber.withValues(alpha: 0.9),
              blurRadius: 8,
              spreadRadius: 1.5,
            ),
          ],
        ),
        child: card,
      ),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot({
    required this.width,
    required this.height,
    required this.label,
    required this.suit,
    this.strong = false,
  });

  final double width;
  final double height;
  final String label;
  final String suit;

  /// The seven of a suit nobody has opened, which is the only card that can go
  /// there. Drawn louder than an ordinary waiting slot.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Palette.feltDark.withValues(alpha: strong ? 0.45 : 0.3),
        borderRadius: BorderRadius.circular(width < 40 ? 4 : Sizes.cardRadius),
        border: Border.all(
          color: strong
              ? Palette.cream.withValues(alpha: 0.85)
              : Palette.cream.withValues(alpha: 0.35),
          width: strong ? 2 : 1.5,
        ),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: width * 0.4,
            height: 1,
            fontWeight: FontWeight.w800,
            color: Palette.cream.withValues(alpha: strong ? 0.95 : 0.5),
          ),
        ),
      ),
    );
  }
}

/// The suit marker at the start of a row, and in the rules screen.
class SuitBadge extends StatelessWidget {
  const SuitBadge({
    super.key,
    required this.suit,
    this.size = 34,
    this.lit = true,
  });

  final String suit;
  final double size;

  /// A suit still waiting for its seven sits back a little.
  final bool lit;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: narrate.suitTitle(suit),
      // The suit name is the label. The glyph itself does not read well.
      child: ExcludeSemantics(
        child: AnimatedContainer(
          duration: Anim.swap,
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: lit ? Palette.cream : Palette.cream.withValues(alpha: 0.55),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Palette.inkDark.withValues(alpha: 0.25),
                blurRadius: 3,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            cards.suitSymbols[suit] ?? suit,
            style: TextStyle(
              fontSize: size * 0.62,
              height: 1,
              color: Palette.suitColour(suit),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
