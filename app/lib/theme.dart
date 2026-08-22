/// Colours, sizes and the single ThemeData for the app.
///
/// The look is deliberately loud: a green felt table, chunky amber buttons and
/// large text, aimed at players who have never installed a game before. Nothing
/// here relies on colour alone to carry meaning, so every state that uses colour
/// also gets an icon or a label somewhere in the widget that draws it.
library;

import 'package:flutter/material.dart';

abstract final class Palette {
  static const inkDark = Color(0xFF0F241E);
  static const ink = Color(0xFF1B3A31);
  static const inkSoft = Color(0xFF5A736B);

  static const feltDark = Color(0xFF0C5241);
  static const felt = Color(0xFF14755C);
  static const feltLight = Color(0xFF1E9270);

  static const white = Color(0xFFFFFFFF);
  static const cream = Color(0xFFFFF7E4);
  static const mist = Color(0xFFE6EEEA);

  static const amber = Color(0xFFFFB224);
  static const amberDeep = Color(0xFFD98600);
  static const blue = Color(0xFF2E6FF2);
  static const blueDeep = Color(0xFF1B4FBF);
  static const coral = Color(0xFFFF6B4A);
  static const coralDeep = Color(0xFFD8482A);
  static const lime = Color(0xFFCBF54F);
  static const violet = Color(0xFF7A5CFF);
  static const rose = Color(0xFFFF4D6D);
  static const teal = Color(0xFF17C3B2);

  /// Suit colours. Red suits stay red so the cards read the way paper cards do.
  static const red = Color(0xFFD32F2F);
  static const black = Color(0xFF20302C);

  static Color suitColour(String suit) =>
      suit == 'H' || suit == 'D' ? red : black;
}

abstract final class Sizes {
  /// Every tap target is at least this tall. The platform minimum is 48.
  static const tap = 56.0;
  static const radius = 18.0;
  static const cardRadius = 6.0;
  static const gap = 12.0;

  /// The card images are 500 x 726.
  static const cardAspect = 500 / 726;

  static double cardHeightFor(double width) => width / cardAspect;
  static double cardWidthFor(double height) => height * cardAspect;
}

/// Text scaling is honoured but capped: past about 1.5 the board itself stops
/// fitting on a phone, and a game you cannot see is worse than slightly smaller
/// type. Everything else in the app scales freely.
const double maxTextScale = 1.5;

ThemeData buildTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: Palette.amber,
    onPrimary: Palette.inkDark,
    secondary: Palette.blue,
    onSecondary: Palette.white,
    tertiary: Palette.teal,
    onTertiary: Palette.inkDark,
    error: Palette.coral,
    onError: Palette.white,
    surface: Palette.white,
    onSurface: Palette.ink,
    surfaceContainerHighest: Palette.mist,
    onSurfaceVariant: Palette.inkSoft,
    outline: Palette.inkSoft,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);

  return base.copyWith(
    scaffoldBackgroundColor: Palette.felt,
    splashColor: Palette.amber.withValues(alpha: 0.2),
    // One transition for every push in the app, set here rather than at each
    // Navigator call. It slides and fades rather than zooming, which keeps the
    // felt continuous between screens.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()},
    ),
    textTheme: base.textTheme
        .apply(bodyColor: Palette.ink, displayColor: Palette.ink)
        .copyWith(
          displaySmall: const TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            color: Palette.ink,
          ),
          headlineMedium: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: Palette.ink,
          ),
          headlineSmall: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Palette.ink,
          ),
          titleLarge: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: Palette.ink,
          ),
          titleMedium: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Palette.ink,
          ),
          bodyLarge: const TextStyle(fontSize: 18, color: Palette.ink),
          bodyMedium: const TextStyle(fontSize: 16, color: Palette.ink),
          labelLarge: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Palette.inkDark,
          ),
        ),
    iconTheme: const IconThemeData(size: 28, color: Palette.ink),
    dividerTheme: const DividerThemeData(color: Palette.mist, thickness: 2),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Palette.inkDark,
      contentTextStyle: TextStyle(fontSize: 18, color: Palette.white),
      behavior: SnackBarBehavior.floating,
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: Palette.amber,
      thumbColor: Palette.amber,
      inactiveTrackColor: Palette.mist,
      trackHeight: 10,
    ),
  );
}
