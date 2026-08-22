/// What the player has equipped, ready for the board to draw.
///
/// Derived from the account, which the server owns, so buying or equipping
/// something updates every screen the moment the response lands. Offline it stays
/// on the free defaults, which is also what a brand new account has.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/cosmetics.dart';
import 'identity.dart';

final equippedCardBackProvider = Provider<Skin>((ref) {
  return cardBackSkin(ref.watch(identityProvider).account?.cardBack);
});

final equippedTableProvider = Provider<Skin>((ref) {
  return tableSkin(ref.watch(identityProvider).account?.table);
});
