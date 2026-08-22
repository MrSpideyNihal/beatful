/// Card rendering.
///
/// Faces come from the 52 bundled images. Backs are painted, because there is no
/// back image in the bundle and painting one means a shop theme can change it
/// without shipping new art.
///
/// Decoded size is bucketed rather than exact: the same card drawn in the table
/// row and in the hand then shares one entry in the image cache instead of two.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/cards.dart' as cards;
import '../state/cosmetics.dart';
import '../theme.dart';

const List<int> _cacheBuckets = [128, 256, 512];

int _bucketFor(double logicalWidth, double devicePixelRatio) {
  final physical = logicalWidth * devicePixelRatio;
  for (final bucket in _cacheBuckets) {
    if (physical <= bucket) return bucket;
  }
  return _cacheBuckets.last;
}

class CardFace extends StatelessWidget {
  const CardFace({
    super.key,
    required this.code,
    required this.width,
    this.highlight = false,
    this.dim = false,
    this.lifted = false,
  });

  final String code;
  final double width;

  /// Playable right now. Drawn as a bright rim and a lift, never colour alone.
  final bool highlight;

  /// Not playable. Still fully readable, just pushed back.
  final bool dim;

  /// Raised, used for the card under the finger.
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    final height = Sizes.cardHeightFor(width);
    final radius = BorderRadius.circular(width < 40 ? 4 : Sizes.cardRadius);
    final bucket = _bucketFor(width, MediaQuery.devicePixelRatioOf(context));

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Palette.white,
        borderRadius: radius,
        border: Border.all(
          color: highlight
              ? Palette.lime
              : Palette.inkDark.withValues(alpha: 0.35),
          width: highlight ? 3 : 1,
        ),
        boxShadow: [
          if (highlight)
            BoxShadow(
              color: Palette.lime.withValues(alpha: 0.55),
              blurRadius: 14,
              spreadRadius: 1,
            ),
          BoxShadow(
            color: Palette.inkDark.withValues(alpha: lifted ? 0.45 : 0.25),
            blurRadius: lifted ? 12 : 4,
            offset: Offset(0, lifted ? 6 : 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              cards.cardImageAsset(code),
              fit: BoxFit.fill,
              cacheWidth: bucket,
              filterQuality: FilterQuality.medium,
              // A missing image must not take the board down with it.
              errorBuilder: (context, error, stack) =>
                  _FallbackFace(code: code, width: width),
            ),
            if (dim)
              ColoredBox(color: Palette.feltDark.withValues(alpha: 0.42)),
          ],
        ),
      ),
    );
  }
}

/// Text only card, used if an image ever fails to load.
class _FallbackFace extends StatelessWidget {
  const _FallbackFace({required this.code, required this.width});

  final String code;
  final double width;

  @override
  Widget build(BuildContext context) {
    final parsed = cards.parseCard(code);
    return ColoredBox(
      color: Palette.white,
      child: Center(
        child: Text(
          cards.cardLabel(code),
          style: TextStyle(
            fontSize: width * 0.34,
            fontWeight: FontWeight.w800,
            color: Palette.suitColour(parsed.suit),
          ),
        ),
      ),
    );
  }
}

/// The back of a card, painted.
///
/// With no colour given it uses whatever back the player has equipped, so buying
/// one in the shop shows up on the table without every call site knowing about
/// cosmetics. Outside a provider scope it falls back to the free default.
class CardBack extends ConsumerWidget {
  const CardBack({super.key, required this.width, this.colour});

  final double width;
  final Color? colour;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = ref.watch(equippedCardBackProvider);
    final height = Sizes.cardHeightFor(width);
    final radius = BorderRadius.circular(width < 40 ? 4 : Sizes.cardRadius);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Palette.white,
        borderRadius: radius,
        border: Border.all(color: Palette.inkDark.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Palette.inkDark.withValues(alpha: 0.22),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(width * 0.07),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(width < 40 ? 2 : 4),
          child: CustomPaint(
            painter: _BackPainter(colour ?? skin.bottom, skin.top),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _BackPainter extends CustomPainter {
  const _BackPainter(this.colour, this.highlight);

  final Color colour;
  final Color highlight;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [highlight, colour],
        ).createShader(Offset.zero & size),
    );
    final line = Paint()
      ..color = Palette.white.withValues(alpha: 0.5)
      ..strokeWidth = size.width * 0.05
      ..style = PaintingStyle.stroke;
    final step = size.width * 0.36;
    for (var x = -size.height; x < size.width + size.height; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), line);
      canvas.drawLine(Offset(x + size.height, 0), Offset(x, size.height), line);
    }
  }

  @override
  bool shouldRepaint(_BackPainter old) =>
      old.colour != colour || old.highlight != highlight;
}
