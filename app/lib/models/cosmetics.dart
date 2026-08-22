/// Cosmetics: card backs and table felts.
///
/// The server owns the catalog and the prices. This file mirrors only the colours,
/// because an equipped item has to keep looking right when there is no connection,
/// for instance during an offline game against bots. Ids the server knows about but
/// this table does not fall back to the free default rather than to nothing.
///
/// Nothing here touches a rule. A card back is a card back.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

const String defaultCardBack = 'back_classic';
const String defaultTable = 'table_green';

/// The two colours an item is drawn from, dark end last.
@immutable
class Skin {
  const Skin(this.name, this.top, this.bottom);

  final String name;
  final Color top;
  final Color bottom;

  LinearGradient get gradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [top, bottom],
  );
}

const Map<String, Skin> cardBackSkins = {
  // The two free defaults are the colours the board already uses, so a player who
  // never opens the shop sees no change at all.
  'back_classic': Skin('Classic Blue', Color(0xFF2E6FF2), Color(0xFF1B4FBF)),
  'back_sunrise': Skin('Sunrise', Color(0xFFF97316), Color(0xFFB91C1C)),
  'back_paisley': Skin('Paisley', Color(0xFF7C3AED), Color(0xFF312E81)),
  'back_mint': Skin('Fresh Mint', Color(0xFF10B981), Color(0xFF065F46)),
};

const Map<String, Skin> tableSkins = {
  'table_green': Skin('Card Room Green', Color(0xFF14755C), Color(0xFF0C5241)),
  'table_walnut': Skin('Walnut', Color(0xFF7C4A21), Color(0xFF3B1F0B)),
  'table_slate': Skin('Slate', Color(0xFF334155), Color(0xFF0F172A)),
  'table_marigold': Skin('Marigold', Color(0xFFD97706), Color(0xFF7C2D12)),
};

Skin cardBackSkin(String? id) =>
    cardBackSkins[id] ?? cardBackSkins[defaultCardBack]!;

Skin tableSkin(String? id) => tableSkins[id] ?? tableSkins[defaultTable]!;

/// Reads a colour the server sent as "#RRGGBB", so the shop can show an item this
/// build has never heard of.
Color? colourFromHex(Object? value) {
  if (value is! String) return null;
  final digits = value.replaceAll('#', '').trim();
  if (digits.length != 6 && digits.length != 8) return null;
  final parsed = int.tryParse(digits, radix: 16);
  if (parsed == null) return null;
  return Color(digits.length == 6 ? 0xFF000000 | parsed : parsed);
}
