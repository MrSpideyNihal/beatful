/// Tests for the layers the online and economy screens are built on.
///
/// All pure functions and plain parsing: a link that arrives from anywhere, an
/// item the server described, a ledger row, and the words that go with them. No
/// widgets and no network.
library;

import 'package:beatful/models/cosmetics.dart';
import 'package:beatful/models/room_code.dart';
import 'package:beatful/screens/coins_screen.dart';
import 'package:beatful/screens/shop_screen.dart';
import 'package:beatful/services/ads.dart';
import 'package:beatful/theme.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('room codes', () {
    test('typing habits are cleaned up rather than refused', () {
      expect(normaliseRoomCode('abc-def'), 'ABCDEF');
      expect(normaliseRoomCode(' abc def '), 'ABCDEF');
      expect(normaliseRoomCode(null), '');
      expect(isValidRoomCode('ABCDEF'), isTrue);
    });

    test('an ambiguous character is rejected and named', () {
      // O, 0, I, 1 and L are not in the alphabet, so they can only be typos.
      expect(isValidRoomCode('ABCDE0'), isFalse);
      expect(isValidRoomCode('ABCDEO'), isFalse);
      expect(confusedCharacters('ABC0IL'), '0, I, L');
      expect(confusedCharacters('ABCDEF'), isEmpty);
    });

    test('a code of the wrong length is not a code', () {
      expect(isValidRoomCode('ABCDE'), isFalse);
      expect(isValidRoomCode('ABCDEFG'), isFalse);
      expect(isValidRoomCode(''), isFalse);
    });

    test('the invite link round trips', () {
      final link = roomLinkFor('ABCDEF');
      expect(link, 'beatful://join/ABCDEF');
      expect(roomCodeFromLink(Uri.parse(link)), 'ABCDEF');
    });

    test('a code is found wherever the platform puts it', () {
      // Host on some Android versions, first path segment on others.
      expect(roomCodeFromLink(Uri.parse('beatful://ABCDEF')), 'ABCDEF');
      expect(roomCodeFromLink(Uri.parse('beatful://join/ABCDEF')), 'ABCDEF');
      expect(
        roomCodeFromLink(Uri.parse('https://beatful.app/join/ABCDEF')),
        'ABCDEF',
      );
      expect(
        roomCodeFromLink(Uri.parse('https://beatful.app/join?code=abcdef')),
        'ABCDEF',
      );
    });

    test('a link with nothing usable in it returns null', () {
      expect(roomCodeFromLink(null), isNull);
      expect(roomCodeFromLink(Uri.parse('beatful://join/')), isNull);
      expect(roomCodeFromLink(Uri.parse('beatful://join/ABC0IL')), isNull);
      expect(roomCodeFromLink(Uri.parse('https://beatful.app/')), isNull);
    });
  });

  group('cosmetics', () {
    test('an unknown id falls back to the free default, never to nothing', () {
      expect(cardBackSkin('back_from_the_future'), cardBackSkins[defaultCardBack]);
      expect(cardBackSkin(null), cardBackSkins[defaultCardBack]);
      expect(tableSkin('table_from_the_future'), tableSkins[defaultTable]);
      expect(tableSkin(null), tableSkins[defaultTable]);
    });

    test('the free defaults are the colours the board already used', () {
      expect(cardBackSkin(defaultCardBack).bottom, Palette.blueDeep);
      expect(cardBackSkin(defaultCardBack).top, Palette.blue);
      expect(tableSkin(defaultTable).top, Palette.felt);
      expect(tableSkin(defaultTable).bottom, Palette.feltDark);
    });

    test('a server colour is read in both lengths', () {
      expect(colourFromHex('#FF0000'), const Color(0xFFFF0000));
      expect(colourFromHex('FF0000'), const Color(0xFFFF0000));
      expect(colourFromHex('#80FF0000'), const Color(0x80FF0000));
    });

    test('anything that is not a colour reads as null', () {
      expect(colourFromHex(null), isNull);
      expect(colourFromHex(42), isNull);
      expect(colourFromHex('red'), isNull);
      expect(colourFromHex('#FFF'), isNull);
      expect(colourFromHex('#GGGGGG'), isNull);
    });
  });

  group('shop items', () {
    test('a known item is drawn from the local table', () {
      final item = ShopItem.fromJson(const {
        'id': 'back_sunrise',
        'kind': 'cardBack',
        'name': 'Sunrise',
        'price': 200,
        'palette': ['#000000', '#000000'],
        'owned': false,
      });

      expect(item.isTable, isFalse);
      expect(item.price, 200);
      expect(item.owned, isFalse);
      // The board draws this back from the local table, so the swatch has to
      // match that and not the palette in the response.
      expect(item.skin, cardBackSkins['back_sunrise']);
    });

    test('an item this build has never heard of still shows', () {
      final item = ShopItem.fromJson(const {
        'id': 'table_future',
        'kind': 'table',
        'name': 'Future Felt',
        'price': 900,
        'palette': ['#123456', '#654321'],
        'owned': true,
      });

      expect(item.isTable, isTrue);
      expect(item.owned, isTrue);
      expect(item.skin.top, const Color(0xFF123456));
      expect(item.skin.bottom, const Color(0xFF654321));
    });

    test('a response missing fields does not throw', () {
      final item = ShopItem.fromJson(const {});
      expect(item.id, isEmpty);
      expect(item.price, 0);
      expect(item.owned, isFalse);
      expect(item.isTable, isFalse);
      expect(item.skin.top, Palette.blue);
    });
  });

  group('coin history', () {
    CoinEntry entry(String type, {int amount = 10, String? room, String? item}) =>
        CoinEntry.fromJson({
          'id': 'x',
          'type': type,
          'amount': amount,
          'balanceAfter': 100,
          'roomCode': room,
          'itemId': item,
          'createdAt': '2026-08-22T10:00:00.000Z',
        });

    test('every ledger type has words a player can read', () {
      expect(entry('signup_bonus').title, 'Welcome coins');
      expect(entry('match_entry').title, 'Match entry');
      expect(entry('match_entry_refund').title, 'Entry given back');
      expect(entry('match_win').title, 'Match winnings');
      expect(entry('ad_reward').title, 'Promo reward');
      expect(entry('shop_purchase').title, 'Shop purchase');
      expect(entry('iap').title, 'Coin pack');
      // A type from a newer server is still shown, just without a nicer name.
      expect(entry('something_new').title, 'Coin change');
    });

    test('a match row points at its room and a purchase at its item', () {
      expect(entry('match_win', room: 'ABCDEF').detail, 'Room ABCDEF');
      expect(entry('match_entry', room: null).detail, isNull);
      expect(entry('shop_purchase', item: 'back_mint').detail, 'back_mint');
      expect(entry('signup_bonus').detail, isNull);
    });

    test('a row with no timestamp is not a crash', () {
      final row = CoinEntry.fromJson(const {'type': 'ad_reward'});
      expect(row.at, isNull);
      expect(coinTime(row.at, DateTime(2026, 8, 22)), isEmpty);
    });

    test('the time reads as words, then as a date', () {
      final now = DateTime(2026, 8, 22, 12);
      expect(coinTime(now.subtract(const Duration(seconds: 20)), now), 'just now');
      expect(
        coinTime(now.subtract(const Duration(minutes: 8)), now),
        '8 minutes ago',
      );
      expect(coinTime(now.subtract(const Duration(hours: 1)), now), 'an hour ago');
      expect(coinTime(now.subtract(const Duration(hours: 5)), now), '5 hours ago');
      expect(coinTime(now.subtract(const Duration(days: 1)), now), 'yesterday');
      expect(coinTime(DateTime(2026, 8, 12, 9), now), '12 Aug');
    });
  });

  group('ad allowance', () {
    test('the cap comes from the server, and a silent one means none left', () {
      final allowance = AdAllowance.fromJson(const {
        'claimedToday': 2,
        'dailyCap': 5,
        'remainingToday': 3,
        'rewardCoins': 25,
      });
      expect(allowance.anyLeft, isTrue);
      expect(allowance.remainingToday, 3);
      expect(allowance.rewardCoins, 25);

      final empty = AdAllowance.fromJson(const {});
      expect(empty.anyLeft, isFalse);
      expect(empty.dailyCap, 0);
    });
  });
}
