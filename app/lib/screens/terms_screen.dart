/// Terms, kept short enough that somebody might actually read it.
library;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/screen_header.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  static const _sections = <(String, String)>[
    (
      'Coins are not money',
      'Coins in Beatful are a virtual currency for use inside this game only. '
          'They have no cash value. They cannot be exchanged, transferred, sold, '
          'or cashed out for real money, ever. If your coins run out you can '
          'still play every free game in the app.',
    ),
    (
      'What coins are for',
      'Coins pay entry to coin matches and buy cosmetic items in the shop. '
          'Cosmetic items change how things look and never change the rules, the '
          'cards you are dealt, or your chance of winning.',
    ),
    (
      'Your account',
      'You play as a guest. Your display name and avatar are yours to change at '
          'any time. There is no password to lose, which also means an app '
          'reinstall or a new device starts a new guest.',
    ),
    (
      'Fair play',
      'Every move is checked on the server. Cards are dealt at random. Bots play '
          'by exactly the same rules you do, with no view of your hand.',
    ),
    (
      'Rewarded ads',
      'Watching an optional ad can earn coins, up to a daily limit. Ads are never '
          'required to play.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: 'Terms',
              subtitle: 'The short version',
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 20),
                itemCount: _sections.length,
                itemBuilder: (context, index) {
                  final (title, body) = _sections[index];
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
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          body,
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                            color: Palette.ink,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
