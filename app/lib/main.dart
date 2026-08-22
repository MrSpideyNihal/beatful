/// App entry point.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/friends_screen.dart';
import 'screens/home_screen.dart';
import 'screens/room_screen.dart';
import 'services/audio.dart';
import 'services/deep_links.dart';
import 'state/identity.dart';
import 'state/online.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    // The board is laid out for a tall screen: four suit rows above a hand.
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Palette.feltDark,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const ProviderScope(child: BeatfulApp()));
}

class BeatfulApp extends ConsumerStatefulWidget {
  const BeatfulApp({super.key});

  @override
  ConsumerState<BeatfulApp> createState() => _BeatfulAppState();
}

class _BeatfulAppState extends ConsumerState<BeatfulApp> {
  final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();
  late final AppLifecycleListener _lifecycle;
  bool _following = false;

  @override
  void initState() {
    super.initState();
    // Music stops when the app leaves the screen and picks up again on return,
    // without restarting the loop from the top.
    _lifecycle = AppLifecycleListener(
      onPause: () => ref.read(audioProvider).suspend(),
      onRestart: () => ref.read(audioProvider).resume(),
    );
    // Reading it once starts the music loop if the setting says so.
    ref.read(audioProvider);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /* -------------------------------------------------------------- deep links */

  /// An invite link was tapped. Joining is attempted for the player, and if it
  /// cannot be done they land on the join screen with the code already filled in
  /// and the reason on screen, rather than nowhere with nothing said.
  Future<void> _follow(PendingLink link) async {
    if (_following) return;
    _following = true;
    final links = ref.read(deepLinkProvider.notifier);
    try {
      final online = ref.read(onlineRoomProvider.notifier);
      final open = ref.read(onlineRoomProvider).room;
      if (open != null) {
        links.taken();
        if (open.roomCode == link.code) {
          _show((_) => const RoomScreen());
        } else {
          // Abandoning a room somebody is sitting in, possibly mid hand, is not
          // something a tapped link gets to do on its own.
          online.announce(
            'Leave this room first, then the link for ${link.code} will work.',
          );
        }
        return;
      }
      if (!await _waitForAccount()) {
        links.taken();
        _show(
          (_) => FriendsScreen(
            initialCode: link.code,
            initialError:
                'Could not reach the game server, so ${link.code} could not be '
                'joined. Try again in a moment.',
          ),
        );
        return;
      }
      final joined = await online.joinByCode(link.code);
      links.taken();
      if (joined) {
        _show((_) => const RoomScreen());
      } else {
        _show(
          (_) => FriendsScreen(
            initialCode: link.code,
            initialError: ref.read(onlineRoomProvider).notice,
          ),
        );
      }
    } finally {
      _following = false;
    }
  }

  /// A link can arrive before there is a guest account, which is exactly what a
  /// cold start from a link looks like. This waits for one, and gives up rather
  /// than hanging if the server cannot be reached.
  Future<bool> _waitForAccount() async {
    for (var attempt = 0; attempt < 40; attempt += 1) {
      final identity = ref.read(identityProvider);
      if (identity.isReady) return true;
      if (identity.status == LinkStatus.offline) {
        // One deliberate retry: a free tier server that was asleep is the most
        // likely reason for the first attempt failing.
        await ref.read(identityProvider.notifier).connect();
        return ref.read(identityProvider).isReady;
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    return false;
  }

  void _show(WidgetBuilder builder) {
    final navigator = _navigator.currentState;
    if (navigator == null) return;
    // A link is a fresh start, so whatever was open is closed first and Back from
    // the new screen goes to Home.
    navigator.popUntil((route) => route.isFirst);
    navigator.push<void>(MaterialPageRoute(builder: builder));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PendingLink?>(deepLinkProvider, (_, next) {
      if (next != null) unawaited(_follow(next));
    });

    return MaterialApp(
      title: 'Beatful',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigator,
      theme: buildTheme(),
      home: const HomeScreen(),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          // Large system text is honoured up to the point where the board stops
          // fitting on a phone.
          data: media.copyWith(
            textScaler: media.textScaler.clamp(maxScaleFactor: maxTextScale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
