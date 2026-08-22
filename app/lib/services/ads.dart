/// Rewarded video, kept behind one small interface.
///
/// The reward itself is not decided here. The device reports that a view finished
/// and the server grants the coins, counting them against a daily cap held in the
/// database, so a replayed call or a reinstall cannot mint anything.
///
/// No ad network is bundled with this build. [HousePromoAds] stands in for one and
/// says so on screen, which keeps the whole path exercisable: view, then claim,
/// then a balance that came from the server. Swapping in a real SDK means writing
/// one more [RewardedAds] and changing [rewardedAdsProvider], nothing else.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/big_button.dart';

enum AdOutcome {
  /// Watched to the end. Only this one is worth claiming.
  completed,

  /// Closed early, so nothing is owed.
  skipped,

  /// Nothing to show right now.
  unavailable,
}

abstract interface class RewardedAds {
  /// What to call this on a button, since "ad" is not always the honest word.
  String get label;

  /// Fetches an ad if the host needs to. False means do not offer it.
  Future<bool> load();

  /// Shows it and resolves when it closes. A real SDK will not need the context;
  /// it is here because a placeholder that draws itself does.
  Future<AdOutcome> show(BuildContext context);
}

/// The stand in. A short house promo with an honest label and a real countdown,
/// so the claim button is reached the same way it would be after a video.
class HousePromoAds implements RewardedAds {
  const HousePromoAds({this.seconds = 5});

  final int seconds;

  @override
  String get label => 'Watch a short promo';

  @override
  Future<bool> load() async => true;

  @override
  Future<AdOutcome> show(BuildContext context) async {
    final outcome = await showDialog<AdOutcome>(
      context: context,
      barrierDismissible: false,
      barrierColor: Palette.inkDark.withValues(alpha: 0.92),
      builder: (context) => _HousePromo(seconds: seconds),
    );
    return outcome ?? AdOutcome.skipped;
  }
}

class _HousePromo extends StatefulWidget {
  const _HousePromo({required this.seconds});

  final int seconds;

  @override
  State<_HousePromo> createState() => _HousePromoState();
}

class _HousePromoState extends State<_HousePromo> {
  late int _left = widget.seconds;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _left -= 1);
      if (_left <= 0) _ticker?.cancel();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final done = _left <= 0;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: PopIn(
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Palette.feltDark,
            borderRadius: BorderRadius.circular(Sizes.radius),
            border: Border.all(color: Palette.amber, width: 3),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Beatful',
                style: TextStyle(
                  fontSize: 40,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                  color: Palette.amber,
                ),
              ),
              const Text(
                'Sevens with your friends, free',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Palette.cream,
                ),
              ),
              const SizedBox(height: 14),
              // Said plainly, because a fake video pretending to be a paid one
              // would be the dishonest version of this screen.
              Text(
                'No ad network is switched on in this build, so this house promo '
                'stands in for the video. The coins it pays are real.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                  color: Palette.cream.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(height: 16),
              if (done)
                BigButton(
                  label: 'Collect',
                  icon: Icons.monetization_on_rounded,
                  onPressed: () =>
                      Navigator.of(context).pop(AdOutcome.completed),
                )
              else ...[
                Text(
                  '$_left',
                  style: const TextStyle(
                    fontSize: 34,
                    height: 1.1,
                    fontWeight: FontWeight.w900,
                    color: Palette.lime,
                  ),
                ),
                Text(
                  _left == 1 ? 'second left' : 'seconds left',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Palette.cream,
                  ),
                ),
                const SizedBox(height: 10),
                PillButton(
                  label: 'Close, no coins',
                  onPressed: () =>
                      Navigator.of(context).pop(AdOutcome.skipped),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// What the server says about today's allowance.
@immutable
class AdAllowance {
  const AdAllowance({
    required this.claimedToday,
    required this.dailyCap,
    required this.remainingToday,
    required this.rewardCoins,
  });

  factory AdAllowance.fromJson(Map<String, Object?> json) => AdAllowance(
    claimedToday: (json['claimedToday'] as num?)?.toInt() ?? 0,
    dailyCap: (json['dailyCap'] as num?)?.toInt() ?? 0,
    remainingToday: (json['remainingToday'] as num?)?.toInt() ?? 0,
    rewardCoins: (json['rewardCoins'] as num?)?.toInt() ?? 0,
  );

  final int claimedToday;
  final int dailyCap;
  final int remainingToday;
  final int rewardCoins;

  bool get anyLeft => remainingToday > 0;
}

final rewardedAdsProvider = Provider<RewardedAds>(
  (ref) => const HousePromoAds(),
);
