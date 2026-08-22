/// The shop. Card backs and table felts, and nothing that touches a rule.
///
/// The catalog, the prices and the balance all come from the server. Buying sends
/// an item id and nothing else, so a device cannot name its own price. The response
/// carries the new account, which is what updates the balance and the board.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/narrate.dart' as narrate;
import '../models/cosmetics.dart';
import '../services/api.dart';
import '../services/cues.dart';
import '../state/identity.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/big_button.dart';
import '../widgets/card_face.dart';
import '../widgets/choice_row.dart';
import '../widgets/screen_header.dart';
import 'coins_screen.dart';

/// One row of the catalog as the server described it.
@immutable
class ShopItem {
  const ShopItem({
    required this.id,
    required this.kind,
    required this.name,
    required this.price,
    required this.owned,
    required this.skin,
  });

  factory ShopItem.fromJson(Map<String, Object?> json) {
    final id = json['id'] as String? ?? '';
    final kind = json['kind'] as String? ?? 'cardBack';
    final palette = json['palette'] as List? ?? const [];
    final top = colourFromHex(palette.isNotEmpty ? palette.first : null);
    final bottom = colourFromHex(palette.length > 1 ? palette[1] : null);
    // Known ids are drawn from the local table so the swatch matches the board
    // exactly. An id from a newer server than this build still shows, using the
    // colours it sent.
    final known = kind == 'table' ? tableSkins[id] : cardBackSkins[id];
    return ShopItem(
      id: id,
      kind: kind,
      name: json['name'] as String? ?? 'Item',
      price: (json['price'] as num?)?.toInt() ?? 0,
      owned: json['owned'] == true,
      skin:
          known ??
          Skin(
            json['name'] as String? ?? 'Item',
            top ?? Palette.blue,
            bottom ?? Palette.blueDeep,
          ),
    );
  }

  final String id;
  final String kind;
  final String name;
  final int price;
  final bool owned;
  final Skin skin;

  bool get isTable => kind == 'table';
}

class ShopScreen extends ConsumerStatefulWidget {
  const ShopScreen({super.key});

  @override
  ConsumerState<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends ConsumerState<ShopScreen> {
  List<ShopItem> _items = const [];
  String _cardBack = defaultCardBack;
  String _table = defaultTable;

  bool _loading = true;
  String? _error;
  String? _working;
  String? _said;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await ref.read(apiProvider).shopItems();
      if (!mounted) return;
      final selected = response['selected'] is Map
          ? Map<String, Object?>.from(response['selected'] as Map)
          : const <String, Object?>{};
      setState(() {
        _items = [
          for (final entry in (response['items'] as List? ?? const []))
            if (entry is Map) ShopItem.fromJson(Map<String, Object?>.from(entry)),
        ];
        _cardBack = selected['cardBack'] as String? ?? defaultCardBack;
        _table = selected['table'] as String? ?? defaultTable;
        _loading = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = narrate.errorMessage(failure.code, failure.message);
      });
    }
  }

  Future<void> _buy(ShopItem item) async {
    if (_working != null) return;
    final coins = ref.read(coinsProvider);
    if (coins < item.price) {
      ref.read(cuesProvider).denied();
      setState(
        () => _said =
            'That costs ${item.price} coins and you have $coins. '
            'Free coins are on the coins screen.',
      );
      return;
    }
    if (!await _confirm(item)) return;
    setState(() {
      _working = item.id;
      _said = null;
    });
    try {
      final response = await ref.read(apiProvider).purchase(item.id);
      ref.read(identityProvider.notifier).adopt(response['user']);
      if (!mounted) return;
      ref.read(cuesProvider).coins();
      setState(() {
        _items = [
          for (final entry in _items)
            if (entry.id == item.id)
              ShopItem(
                id: entry.id,
                kind: entry.kind,
                name: entry.name,
                price: entry.price,
                owned: true,
                skin: entry.skin,
              )
            else
              entry,
        ];
        _working = null;
        _said = '${item.name} is yours. Tap it again to use it.';
      });
      // Bought is not worn: equipping is the second, deliberate tap.
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      ref.read(cuesProvider).denied();
      setState(() {
        _working = null;
        _said = narrate.errorMessage(failure.code, failure.message);
      });
    }
  }

  Future<void> _equip(ShopItem item) async {
    if (_working != null) return;
    setState(() {
      _working = item.id;
      _said = null;
    });
    try {
      final response = await ref.read(apiProvider).equip(item.id);
      ref.read(identityProvider.notifier).adopt(response['user']);
      if (!mounted) return;
      ref.read(cuesProvider).tap();
      setState(() {
        if (item.isTable) {
          _table = item.id;
        } else {
          _cardBack = item.id;
        }
        _working = null;
        _said = 'Using ${item.name}.';
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      ref.read(cuesProvider).denied();
      setState(() {
        _working = null;
        _said = narrate.errorMessage(failure.code, failure.message);
      });
    }
  }

  Future<bool> _confirm(ShopItem item) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Buy ${item.name}?'),
        content: Text(
          'It costs ${item.price} coins. It changes how your cards look and '
          'nothing else about the game.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now', style: TextStyle(fontSize: 17)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Buy for ${item.price}',
              style: const TextStyle(fontSize: 17),
            ),
          ),
        ],
      ),
    );
    return answer == true;
  }

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(identityProvider);
    final coins = ref.watch(coinsProvider);
    final backs = _items.where((item) => !item.isTable).toList();
    final tables = _items.where((item) => item.isTable).toList();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: 'Shop',
              subtitle: 'Looks only, never an advantage',
              onBack: () => Navigator.of(context).pop(),
              actions: [
                HeaderButton(
                  icon: Icons.monetization_on_rounded,
                  label: 'Coins',
                  tint: Palette.amber,
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const CoinsScreen()),
                  ),
                ),
              ],
            ),
            _Balance(coins: coins),
            if (_said case final said?)
              Shake(
                token: said,
                child: _SaidLine(
                  message: said,
                  onDismiss: () => setState(() => _said = null),
                ),
              ),
            Expanded(
              child: switch (true) {
                _ when !identity.isReady => _Unavailable(
                  message:
                      identity.status == LinkStatus.offline
                      ? identity.message ??
                            'The shop needs the game server. Bots still work.'
                      : 'Connecting to the game server.',
                  spinning: identity.status != LinkStatus.offline,
                  onRetry: () => ref.read(identityProvider.notifier).connect(),
                ),
                _ when _loading => const Center(
                  child: CircularProgressIndicator(color: Palette.cream),
                ),
                _ when _error != null => _Unavailable(
                  message: _error!,
                  spinning: false,
                  onRetry: _load,
                ),
                _ => ListView(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                  children: [
                    _Group(
                      title: 'Card backs',
                      hint: 'What the other players see of your hand',
                      items: backs,
                      equippedId: _cardBack,
                      working: _working,
                      coins: coins,
                      onBuy: _buy,
                      onEquip: _equip,
                    ),
                    _Group(
                      title: 'Table felts',
                      hint: 'The colour under the cards',
                      items: tables,
                      equippedId: _table,
                      working: _working,
                      coins: coins,
                      onBuy: _buy,
                      onEquip: _equip,
                    ),
                    const _NoAdvantage(),
                  ],
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Balance extends StatelessWidget {
  const _Balance({required this.coins});

  final int coins;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Palette.feltDark,
          borderRadius: BorderRadius.circular(Sizes.radius),
          border: Border.all(color: Palette.amber, width: 2),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.monetization_on_rounded,
              color: Palette.amber,
              size: 28,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Semantics(
                label: 'You have $coins coins',
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      CountUp(
                        value: coins,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Palette.cream,
                        ),
                      ),
                      const Text(
                        ' coins',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Palette.cream,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.hint,
    required this.items,
    required this.equippedId,
    required this.working,
    required this.coins,
    required this.onBuy,
    required this.onEquip,
  });

  final String title;
  final String hint;
  final List<ShopItem> items;
  final String equippedId;
  final String? working;
  final int coins;
  final ValueChanged<ShopItem> onBuy;
  final ValueChanged<ShopItem> onEquip;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: title,
      hint: hint,
      child: Column(
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: FadeSlideIn(
                key: ValueKey(item.id),
                dy: 10,
                child: _ItemRow(
                  item: item,
                  equipped: item.id == equippedId,
                  busy: working == item.id,
                  blocked: working != null && working != item.id,
                  affordable: coins >= item.price,
                  onBuy: () => onBuy(item),
                  onEquip: () => onEquip(item),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.equipped,
    required this.busy,
    required this.blocked,
    required this.affordable,
    required this.onBuy,
    required this.onEquip,
  });

  final ShopItem item;
  final bool equipped;
  final bool busy;
  final bool blocked;
  final bool affordable;
  final VoidCallback onBuy;
  final VoidCallback onEquip;

  @override
  Widget build(BuildContext context) {
    final tappable = !busy && !blocked && !equipped;
    final action = item.owned ? onEquip : onBuy;
    final state = equipped
        ? 'in use'
        : item.owned
        ? 'owned, tap to use'
        : '${item.price} coins';

    return Semantics(
      button: true,
      enabled: tappable,
      selected: equipped,
      label: '${item.name}, $state',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: tappable ? action : null,
          child: AnimatedContainer(
            duration: Anim.swap,
            constraints: const BoxConstraints(minHeight: 78),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Palette.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: equipped ? Palette.lime : Palette.mist,
                width: equipped ? 3 : 2,
              ),
            ),
            child: Row(
              children: [
                _Swatch(item: item),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Palette.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      _Tag(
                        item: item,
                        equipped: equipped,
                        affordable: affordable,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (busy)
                  const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Palette.felt,
                    ),
                  )
                else if (equipped)
                  const PopIn(
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 30,
                      color: Palette.felt,
                    ),
                  )
                else
                  PillButton(
                    label: item.owned ? 'Use' : 'Buy',
                    icon: item.owned
                        ? Icons.check_rounded
                        : Icons.shopping_bag_rounded,
                    colour: item.owned ? Palette.felt : Palette.amberDeep,
                    filled: true,
                    onPressed: tappable ? action : null,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({
    required this.item,
    required this.equipped,
    required this.affordable,
  });

  final ShopItem item;
  final bool equipped;
  final bool affordable;

  @override
  Widget build(BuildContext context) {
    final (text, colour) = equipped
        ? ('In use', Palette.felt)
        : item.owned
        ? ('Owned', Palette.inkSoft)
        : affordable
        ? ('${item.price} coins', Palette.amberDeep)
        : ('${item.price} coins, not enough yet', Palette.coralDeep);
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: colour,
      ),
    );
  }
}

/// The item itself, not a colour chip: a card back is shown as a card and a felt as
/// a patch of table, so nobody has to guess what they are buying.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.item});

  final ShopItem item;

  @override
  Widget build(BuildContext context) {
    if (!item.isTable) {
      return CardBack(width: 40, colour: item.skin.bottom);
    }
    return Container(
      width: 40,
      height: Sizes.cardHeightFor(40),
      decoration: BoxDecoration(
        gradient: item.skin.gradient,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Palette.inkDark.withValues(alpha: 0.3)),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.style_rounded, size: 18, color: Palette.cream),
    );
  }
}

class _SaidLine extends StatelessWidget {
  const _SaidLine({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: Palette.amber,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.inkDark, width: 2),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_rounded, color: Palette.inkDark, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 15,
                height: 1.25,
                fontWeight: FontWeight.w700,
                color: Palette.inkDark,
              ),
            ),
          ),
          HeaderButton(
            icon: Icons.close_rounded,
            label: 'Dismiss',
            tint: Palette.inkDark,
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({
    required this.message,
    required this.spinning,
    required this.onRetry,
  });

  final String message;
  final bool spinning;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (spinning)
              const CircularProgressIndicator(color: Palette.cream)
            else
              const Icon(Icons.wifi_off_rounded, size: 48, color: Palette.cream),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                height: 1.3,
                fontWeight: FontWeight.w700,
                color: Palette.cream,
              ),
            ),
            if (!spinning) ...[
              const SizedBox(height: 16),
              BigButton(
                label: 'Try again',
                icon: Icons.refresh_rounded,
                expand: false,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NoAdvantage extends StatelessWidget {
  const _NoAdvantage();

  @override
  Widget build(BuildContext context) {
    return const SectionCard(
      title: 'About these',
      child: Text(
        'Everything here is decoration. No item deals you better cards, gives you '
        'more time on your turn or changes a single rule. Coins are for looks and '
        'for match entry fees, and they cannot be turned back into money.',
        style: TextStyle(
          fontSize: 15,
          height: 1.35,
          fontWeight: FontWeight.w600,
          color: Palette.cream,
        ),
      ),
    );
  }
}
