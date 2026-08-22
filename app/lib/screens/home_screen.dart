/// Home. Two ways to play, and everything else out of the way.
///
/// The rule the whole screen is built around: from here, one tap reaches a game.
/// Play vs Bots starts with the setup you used last time already selected, and
/// Play with Friends goes straight to create or join.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/avatar.dart';
import '../state/identity.dart';
import '../state/profile.dart';
import '../state/solo_config.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/avatar_circle.dart';
import '../widgets/big_button.dart';
import 'coins_screen.dart';
import 'friends_screen.dart';
import 'rules_screen.dart';
import 'settings_screen.dart';
import 'shop_screen.dart';
import 'solo_setup_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider);
    final config = ref.watch(soloConfigProvider);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              // Fills the screen when it fits and scrolls when it does not. The
              // intrinsic pass is what gives the spacers a height to divide.
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                  child: Column(
                    children: [
                      FadeSlideIn(
                        dy: -12,
                        child: _TopRow(
                          name: profile.name,
                          avatar: profile.avatar,
                          coins: ref.watch(coinsProvider),
                          coinsKnown: ref.watch(identityProvider).isReady,
                          onProfile: () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => const SettingsScreen(),
                            ),
                          ),
                          onCoins: () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => const CoinsScreen(),
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      const FadeSlideIn(
                        delay: Duration(milliseconds: 60),
                        child: _Title(),
                      ),
                      const SizedBox(height: 28),
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 140),
                        child: BigButton(
                          label: 'Play vs Bots',
                          icon: Icons.smart_toy_rounded,
                          minHeight: 84,
                          subtitle:
                              '${config.seatCount} players, '
                              '${config.difficulty.label.toLowerCase()}',
                          onPressed: () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => const SoloSetupScreen(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 200),
                        child: BigButton(
                          label: 'Play with Friends',
                          icon: Icons.groups_rounded,
                          colour: Palette.blue,
                          foreground: Palette.white,
                          minHeight: 84,
                          subtitle: 'Share a code, up to 8 players',
                          onPressed: () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => const FriendsScreen(),
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      FadeSlideIn(
                        delay: const Duration(milliseconds: 260),
                        dy: 24,
                        child: _BottomRow(
                          onRules: () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => const RulesScreen(),
                            ),
                          ),
                          onShop: () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => const ShopScreen(),
                            ),
                          ),
                          onSettings: () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => const SettingsScreen(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          'Beatful',
          style: TextStyle(
            fontSize: 54,
            height: 1.05,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
            color: Palette.amber,
          ),
        ),
        Text(
          'The Sevens card game',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            color: Palette.cream.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }
}

/// Your name and picture, which is also the way into settings, and the balance,
/// which is the way into coins.
class _TopRow extends StatelessWidget {
  const _TopRow({
    required this.name,
    required this.avatar,
    required this.coins,
    required this.coinsKnown,
    required this.onProfile,
    required this.onCoins,
  });

  final String name;
  final int avatar;
  final int coins;

  /// False until the server has answered, so a real zero is never confused with
  /// a balance nobody has looked up yet.
  final bool coinsKnown;
  final VoidCallback onProfile;
  final VoidCallback onCoins;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Expanded, not Spacer: a long name shortens itself instead of pushing
        // the balance off the screen.
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Semantics(
              button: true,
              label:
                  'You are $name, picture ${avatarStyle(avatar).name}. '
                  'Tap to change.',
              child: ExcludeSemantics(
                child: GestureDetector(
                  onTap: onProfile,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: Sizes.tap),
                    padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
                    decoration: BoxDecoration(
                      color: Palette.feltDark,
                      borderRadius: BorderRadius.circular(Sizes.tap / 2),
                      border: Border.all(
                        color: Palette.cream.withValues(alpha: 0.25),
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AvatarCircle(avatar: avatar, size: 40),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Palette.cream,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.edit_rounded,
                          size: 18,
                          color: Palette.cream.withValues(alpha: 0.7),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _CoinPill(coins: coins, known: coinsKnown, onPressed: onCoins),
      ],
    );
  }
}

class _CoinPill extends StatelessWidget {
  const _CoinPill({
    required this.coins,
    required this.known,
    required this.onPressed,
  });

  final int coins;
  final bool known;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: known ? '$coins coins. Tap for history.' : 'Coins, still loading',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onPressed,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: Sizes.tap,
              minWidth: 84,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Palette.feltDark,
              borderRadius: BorderRadius.circular(Sizes.tap / 2),
              border: Border.all(color: Palette.amber, width: 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.monetization_on_rounded,
                  size: 24,
                  color: Palette.amber,
                ),
                const SizedBox(width: 6),
                if (known)
                  CountUp(
                    value: coins,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Palette.cream,
                    ),
                  )
                else
                  const Text(
                    '...',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Palette.cream,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomRow extends StatelessWidget {
  const _BottomRow({
    required this.onRules,
    required this.onShop,
    required this.onSettings,
  });

  final VoidCallback onRules;
  final VoidCallback onShop;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: _HomeTile(
            icon: Icons.help_outline_rounded,
            label: 'How to play',
            onPressed: onRules,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _HomeTile(
            icon: Icons.shopping_bag_rounded,
            label: 'Shop',
            onPressed: onShop,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _HomeTile(
            icon: Icons.settings_rounded,
            label: 'Settings',
            onPressed: onSettings,
          ),
        ),
      ],
    );
  }
}

class _HomeTile extends StatelessWidget {
  const _HomeTile({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onPressed,
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: Palette.feltDark.withValues(alpha: enabled ? 1 : 0.5),
              borderRadius: BorderRadius.circular(Sizes.radius),
              border: Border.all(
                color: Palette.cream.withValues(alpha: enabled ? 0.25 : 0.12),
                width: 2,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 26,
                  color: Palette.cream.withValues(alpha: enabled ? 1 : 0.5),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    color: Palette.cream.withValues(alpha: enabled ? 1 : 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
