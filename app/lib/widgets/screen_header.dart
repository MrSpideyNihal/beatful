/// The header row used instead of an AppBar.
///
/// A plain AppBar gives a 24dp back arrow in a 40dp box. This one is 56dp, says
/// what it goes back to where that is not obvious, and leaves room for the round
/// counter and the two board buttons.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

class ScreenHeader extends StatelessWidget {
  const ScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;

  /// Null hides the back button, for a screen you cannot walk out of.
  final VoidCallback? onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          if (onBack != null)
            HeaderButton(
              icon: Icons.arrow_back_rounded,
              label: 'Back',
              onPressed: onBack,
            )
          else
            const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 21,
                      height: 1.15,
                      fontWeight: FontWeight.w900,
                      color: Palette.cream,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                        color: Palette.cream.withValues(alpha: 0.8),
                      ),
                    ),
                ],
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class HeaderButton extends StatelessWidget {
  const HeaderButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tint = Palette.cream,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    // No Semantics wrapper: the tooltip is already the button's spoken label,
    // and a wrapper would have the reader say it twice.
    return IconButton(
      onPressed: onPressed,
      tooltip: label,
      iconSize: 28,
      constraints: const BoxConstraints(
        minWidth: Sizes.tap,
        minHeight: Sizes.tap,
      ),
      style: IconButton.styleFrom(
        foregroundColor: tint,
        backgroundColor: Palette.feltDark.withValues(alpha: 0.6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: Icon(icon, color: tint),
    );
  }
}
