/// How to play. A reference you can pull up mid-game without leaving the table.
library;

import 'package:flutter/material.dart';

import '../game/cards.dart' as cards;
import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/card_face.dart';
import '../widgets/screen_header.dart';
import '../widgets/table_board.dart';

class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  static const _cards = <_RuleCard>[
    _RuleCard(
      title: 'The goal',
      body:
          'Be the first to play all your cards. When the round ends, everyone '
          'else is ranked by how many cards they still hold. Fewer is better.',
    ),
    _RuleCard(
      title: 'Starting the game',
      body:
          'The round always begins with the 7 of Hearts (7♥). Whoever holds '
          'it plays first. After the 7 of Hearts is down, any other 7 can open '
          'its suit and play proceeds normally.',
      example: _SevenExample(),
    ),
    _RuleCard(
      title: 'Building a suit',
      body:
          'After the 7, a suit grows outward: up toward the King, or down '
          'toward the Ace. You have to play the next card in order, so no '
          'skipping. The two directions are independent.',
      example: _SequenceExample(),
    ),
    _RuleCard(
      title: 'Your turn',
      body:
          'Play one card, or pass. Passing never skips your later turns, and '
          'nobody is ever knocked out. If your timer runs out, one of your legal '
          'cards is played for you, or you pass if you have none.',
    ),
    _RuleCard(
      title: 'Winning',
      body:
          'First player with no cards left wins the round. Over a match of '
          'several rounds, the best total placing wins.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: 'How to play',
              subtitle: 'Sevens, in five short steps',
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 20),
                itemCount: _cards.length,
                itemBuilder: (context, index) => FadeSlideIn(
                  delay: Duration(milliseconds: 50 * index),
                  child: _cards[index],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({required this.title, required this.body, this.example});

  final String title;
  final String body;
  final Widget? example;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Palette.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              fontSize: 17,
              height: 1.4,
              fontWeight: FontWeight.w500,
              color: Palette.ink,
            ),
          ),
          if (example != null) ...[const SizedBox(height: 14), example!],
        ],
      ),
    );
  }
}

/// The four sevens, which are the only four cards that can open a row.
class _SevenExample extends StatelessWidget {
  const _SevenExample();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: [
        for (final suit in cards.suits)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SuitBadge(suit: suit, size: 26),
              const SizedBox(height: 6),
              CardFace(code: cards.makeCard(suit, cards.anchorRank), width: 48),
            ],
          ),
      ],
    );
  }
}

/// One suit part way through a round, with the two cards it will take next.
class _SequenceExample extends StatelessWidget {
  const _SequenceExample();

  @override
  Widget build(BuildContext context) {
    const suit = 'H';
    const width = 42.0;

    return Column(
      children: [
        SizedBox(
          height: Sizes.cardHeightFor(width) + 4,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _Slot(width: width, label: '4'),
              const SizedBox(width: 4),
              for (final rank in [5, 6, 7, 8, 9])
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: CardFace(
                    code: cards.makeCard(suit, rank),
                    width: width,
                  ),
                ),
              const _Slot(width: width, label: '10'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Only the 4 or the 10 can go next',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Palette.inkSoft,
          ),
        ),
      ],
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({required this.width, required this.label});

  final double width;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: Sizes.cardHeightFor(width),
      decoration: BoxDecoration(
        color: Palette.mist,
        borderRadius: BorderRadius.circular(Sizes.cardRadius),
        border: Border.all(color: Palette.amberDeep, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w900,
          color: Palette.inkSoft,
        ),
      ),
    );
  }
}
