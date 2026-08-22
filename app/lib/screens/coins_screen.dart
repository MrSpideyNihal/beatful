/// Coins: the balance, where it came from, and the free way to get more.
///
/// Every number on this screen is the server's. The history is the ledger row per
/// change, so a balance that moved is never a mystery, and the closed loop is
/// stated in plain words rather than buried in the terms.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/narrate.dart' as narrate;
import '../services/ads.dart';
import '../services/api.dart';
import '../services/cues.dart';
import '../state/identity.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/big_button.dart';
import '../widgets/choice_row.dart';
import '../widgets/screen_header.dart';
import 'terms_screen.dart';

/// One row of the coin ledger.
@immutable
class CoinEntry {
  const CoinEntry({
    required this.id,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    required this.at,
    this.roomCode,
    this.itemId,
  });

  factory CoinEntry.fromJson(Map<String, Object?> json) => CoinEntry(
    id: json['id'] as String? ?? '',
    type: json['type'] as String? ?? '',
    amount: (json['amount'] as num?)?.toInt() ?? 0,
    balanceAfter: (json['balanceAfter'] as num?)?.toInt() ?? 0,
    at: DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal(),
    roomCode: json['roomCode'] as String?,
    itemId: json['itemId'] as String?,
  );

  final String id;
  final String type;
  final int amount;
  final int balanceAfter;
  final DateTime? at;
  final String? roomCode;
  final String? itemId;

  String get title => switch (type) {
    'signup_bonus' => 'Welcome coins',
    'match_entry' => 'Match entry',
    'match_entry_refund' => 'Entry given back',
    'match_win' => 'Match winnings',
    'ad_reward' => 'Promo reward',
    'shop_purchase' => 'Shop purchase',
    'iap' => 'Coin pack',
    _ => 'Coin change',
  };

  String? get detail => switch (type) {
    'match_entry' || 'match_entry_refund' || 'match_win' =>
      roomCode == null ? null : 'Room $roomCode',
    'shop_purchase' => itemId,
    _ => null,
  };
}

/// "4 minutes ago", then dates once that stops being useful. No intl dependency
/// for four lines of formatting.
String coinTime(DateTime? at, DateTime now) {
  if (at == null) return '';
  final gap = now.difference(at);
  if (gap.inSeconds < 90) return 'just now';
  if (gap.inMinutes < 60) return '${gap.inMinutes} minutes ago';
  if (gap.inHours < 24) {
    return gap.inHours == 1 ? 'an hour ago' : '${gap.inHours} hours ago';
  }
  if (gap.inDays == 1) return 'yesterday';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${at.day} ${months[at.month - 1]}';
}

class CoinsScreen extends ConsumerStatefulWidget {
  const CoinsScreen({super.key});

  @override
  ConsumerState<CoinsScreen> createState() => _CoinsScreenState();
}

class _CoinsScreenState extends ConsumerState<CoinsScreen> {
  List<CoinEntry> _history = const [];
  AdAllowance? _allowance;

  bool _loading = true;
  bool _claiming = false;
  String? _error;
  String? _said;
  int _gained = 0;

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
    final api = ref.read(apiProvider);
    try {
      // Both are wanted at once, and neither is worth a second spinner.
      final results = await Future.wait([api.transactions(), api.adsStatus()]);
      if (!mounted) return;
      setState(() {
        _history = [
          for (final entry in (results[0]['transactions'] as List? ?? const []))
            if (entry is Map) CoinEntry.fromJson(Map<String, Object?>.from(entry)),
        ];
        _allowance = AdAllowance.fromJson(results[1]);
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

  Future<void> _watchForCoins() async {
    final ads = ref.read(rewardedAdsProvider);
    if (_claiming) return;
    setState(() {
      _claiming = true;
      _said = null;
    });
    try {
      if (!await ads.load()) {
        if (!mounted) return;
        setState(
          () => _said = 'Nothing to show right now. Try again in a minute.',
        );
        return;
      }
      if (!mounted) return;
      final outcome = await ads.show(context);
      if (!mounted) return;
      if (outcome != AdOutcome.completed) {
        setState(
          () => _said = outcome == AdOutcome.skipped
              ? 'Closed early, so no coins this time.'
              : 'Nothing to show right now. Try again in a minute.',
        );
        return;
      }
      final response = await ref.read(apiProvider).claimAdReward();
      ref.read(identityProvider.notifier).adopt(response['user']);
      if (!mounted) return;
      ref.read(cuesProvider).coins();
      final granted = (response['granted'] as num?)?.toInt() ?? 0;
      setState(() {
        _allowance = AdAllowance.fromJson({
          ...response,
          'rewardCoins': _allowance?.rewardCoins ?? granted,
        });
        _gained += 1;
        _said = 'Added $granted coins.';
      });
      // The list is on the server, so the new row comes from a reload rather than
      // from guessing what it will say.
      await _load();
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      ref.read(cuesProvider).denied();
      setState(() => _said = narrate.errorMessage(failure.code, failure.message));
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(identityProvider);
    final coins = ref.watch(coinsProvider);
    final now = DateTime.now();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: 'Coins',
              subtitle: 'Balance and history',
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: !identity.isReady
                  ? _Unavailable(
                      message: identity.status == LinkStatus.offline
                          ? identity.message ??
                                'Coins need the game server. Bot games do not.'
                          : 'Connecting to the game server.',
                      spinning: identity.status != LinkStatus.offline,
                      onRetry: () =>
                          ref.read(identityProvider.notifier).connect(),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                      children: [
                        _BigBalance(coins: coins, bump: _gained),
                        _FreeCoins(
                          allowance: _allowance,
                          label: ref.read(rewardedAdsProvider).label,
                          busy: _claiming,
                          loading: _loading,
                          said: _said,
                          onWatch: _watchForCoins,
                          onDismissSaid: () => setState(() => _said = null),
                        ),
                        _History(
                          entries: _history,
                          now: now,
                          loading: _loading,
                          error: _error,
                          onRetry: _load,
                        ),
                        const _ClosedLoop(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BigBalance extends StatelessWidget {
  const _BigBalance({required this.coins, required this.bump});

  final int coins;

  /// Changes when coins land, which is what makes the number pop again.
  final int bump;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: Palette.feltDark,
        borderRadius: BorderRadius.circular(Sizes.radius),
        border: Border.all(color: Palette.amber, width: 3),
      ),
      child: Semantics(
        label: 'Balance, $coins coins',
        child: ExcludeSemantics(
          child: Column(
            children: [
              const Icon(
                Icons.monetization_on_rounded,
                size: 40,
                color: Palette.amber,
              ),
              const SizedBox(height: 4),
              LandPulse(
                token: bump,
                child: CountUp(
                  value: coins,
                  style: const TextStyle(
                    fontSize: 46,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    color: Palette.cream,
                  ),
                ),
              ),
              const Text(
                'coins',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Palette.cream,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FreeCoins extends StatelessWidget {
  const _FreeCoins({
    required this.allowance,
    required this.label,
    required this.busy,
    required this.loading,
    required this.said,
    required this.onWatch,
    required this.onDismissSaid,
  });

  final AdAllowance? allowance;
  final String label;
  final bool busy;
  final bool loading;
  final String? said;
  final VoidCallback onWatch;
  final VoidCallback onDismissSaid;

  @override
  Widget build(BuildContext context) {
    final allowance = this.allowance;
    final left = allowance?.remainingToday ?? 0;
    final reward = allowance?.rewardCoins ?? 0;

    return SectionCard(
      title: 'Free coins',
      hint: allowance == null
          ? 'Checking today\'s allowance'
          : left > 0
          ? '$reward coins each, $left left today'
          : 'You have taken all ${allowance.dailyCap} today. '
                'More after midnight UTC.',
      child: Column(
        children: [
          if (said case final said?)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Shake(
                token: said,
                child: _SaidLine(message: said, onDismiss: onDismissSaid),
              ),
            ),
          BigButton(
            label: busy ? 'Working' : label,
            icon: Icons.play_circle_fill_rounded,
            colour: Palette.lime,
            subtitle: left > 0 ? 'Adds $reward coins' : 'Back tomorrow',
            onPressed: loading || busy || left <= 0 ? null : onWatch,
          ),
        ],
      ),
    );
  }
}

class _History extends StatelessWidget {
  const _History({
    required this.entries,
    required this.now,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final List<CoinEntry> entries;
  final DateTime now;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'History',
      hint: 'Newest first, last 50 changes',
      child: switch (true) {
        _ when loading => const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Center(child: CircularProgressIndicator(color: Palette.cream)),
        ),
        _ when error != null => Column(
          children: [
            Text(
              error!,
              style: const TextStyle(
                fontSize: 15,
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: Palette.cream,
              ),
            ),
            const SizedBox(height: 10),
            PillButton(
              label: 'Try again',
              icon: Icons.refresh_rounded,
              onPressed: onRetry,
            ),
          ],
        ),
        _ when entries.isEmpty => Text(
          'Nothing yet. Coin matches and free coins show up here.',
          style: TextStyle(
            fontSize: 15,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: Palette.cream.withValues(alpha: 0.85),
          ),
        ),
        _ => Column(
          children: [
            for (final entry in entries)
              _HistoryRow(entry: entry, when: coinTime(entry.at, now)),
          ],
        ),
      },
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry, required this.when});

  final CoinEntry entry;
  final String when;

  @override
  Widget build(BuildContext context) {
    final up = entry.amount >= 0;
    final sign = up ? '+' : '';
    final detail = [
      if (when.isNotEmpty) when,
      ?entry.detail,
    ].join(' · ');

    return Semantics(
      label:
          '${entry.title}, $sign${entry.amount} coins, '
          'balance ${entry.balanceAfter}${when.isEmpty ? '' : ', $when'}',
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Palette.cream.withValues(alpha: 0.12)),
            ),
          ),
          child: Row(
            children: [
              Icon(
                up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                size: 20,
                color: up ? Palette.lime : Palette.coral,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: Palette.cream,
                      ),
                    ),
                    if (detail.isNotEmpty)
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          color: Palette.cream.withValues(alpha: 0.7),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$sign${entry.amount}',
                    style: TextStyle(
                      fontSize: 18,
                      height: 1.2,
                      fontWeight: FontWeight.w900,
                      color: up ? Palette.lime : Palette.coral,
                    ),
                  ),
                  Text(
                    'left ${entry.balanceAfter}',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: Palette.cream.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClosedLoop extends StatelessWidget {
  const _ClosedLoop();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'About coins',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Coins stay inside Beatful. They pay match entry fees and shop items, '
            'and they cannot be cashed out, sold or turned back into money. '
            'They have no value outside the game.',
            style: TextStyle(
              fontSize: 15,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: Palette.cream.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 8),
          PillButton(
            label: 'Read the terms',
            icon: Icons.description_rounded,
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const TermsScreen()),
            ),
          ),
        ],
      ),
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
