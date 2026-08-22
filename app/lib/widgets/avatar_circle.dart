/// Avatar circle, drawn from the preset icon and colour.
library;

import 'package:flutter/material.dart';

import '../models/avatar.dart';
import '../theme.dart';

class AvatarCircle extends StatelessWidget {
  const AvatarCircle({
    super.key,
    required this.avatar,
    this.size = 52,
    this.faded = false,
  });

  final int avatar;
  final double size;

  /// Used for a seat that has dropped out, so the badge still reads but sits back.
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final style = avatarStyle(avatar);
    return Semantics(
      label: style.name,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: faded ? Palette.inkSoft : style.colour,
          shape: BoxShape.circle,
          border: Border.all(color: Palette.cream, width: size * 0.05),
          boxShadow: [
            BoxShadow(
              color: Palette.inkDark.withValues(alpha: 0.25),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Icon(style.icon, size: size * 0.52, color: Palette.white),
      ),
    );
  }
}
