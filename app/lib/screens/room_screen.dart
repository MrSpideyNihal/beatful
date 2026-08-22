/// The room, from lobby to last card.
///
/// Lobby and board are one screen on purpose. The room is a single thing that
/// changes state, so there is no navigation between them: nothing to push, nothing
/// to pop, and no way to end up looking at a lobby for a match that already
/// started.
///
/// The server owns everything shown here. This screen sends taps and draws what
/// comes back.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/engine.dart';
import '../models/room.dart';
import '../state/identity.dart';
import '../state/online.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/big_button.dart';
import '../widgets/lobby_panel.dart';
import '../widgets/screen_header.dart';
import 'game_screen.dart';
import 'rules_screen.dart';
import 'settings_screen.dart';

class RoomScreen extends ConsumerStatefulWidget {
  const RoomScreen({super.key});

  @override
  ConsumerState<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends ConsumerState<RoomScreen> {
  late final AppLifecycleListener _lifecycle;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    // Backgrounded: drop the held poll so the server can release the slot, and
    // fall back to the heartbeat that keeps this seat marked as present.
    _lifecycle = AppLifecycleListener(
      onPause: () => ref.read(onlineRoomProvider.notifier).suspend(),
      onRestart: () =>
          ref.read(onlineRoomProvider.notifier).resumeFromBackground(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  OnlineController get _control => ref.read(onlineRoomProvider.notifier);

  /* ---------------------------------------------------------------- leaving */

  Future<void> _leave({required bool ask}) async {
    if (_leaving) return;
    if (ask && !await _confirmLeave()) return;
    setState(() => _leaving = true);
    await _control.leave();
    if (mounted) Navigator.of(context).pop();
  }

  Future<bool> _confirmLeave() async {
    final room = ref.read(onlineRoomProvider).room;
    final playing = room?.isPlaying ?? false;
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(playing ? 'Leave this match?' : 'Leave this room?'),
        content: Text(
          playing
              ? 'Your cards stay at the table. Your turns keep playing out on '
                    'the timer, and the host can hand your seat to a bot.'
              : 'You can come back with the same code while the room is open.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay', style: TextStyle(fontSize: 17)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave', style: TextStyle(fontSize: 17)),
          ),
        ],
      ),
    );
    return answer == true;
  }

  /* ------------------------------------------------------------------- view */

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(onlineRoomProvider);
    final room = online.room;

    if (room == null) {
      return Scaffold(
        body: SafeArea(
          child: _NoRoom(
            stage: online.stage,
            reason: online.closedReason ?? online.notice,
            leaving: _leaving,
            onHome: () => Navigator.of(context).pop(),
          ),
        ),
      );
    }

    final canPop = _leaving || room.isFinished;
    return Scaffold(
      body: SafeArea(
        child: PopScope(
          canPop: canPop,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _leave(ask: true);
          },
          child: room.inLobby ? _lobby(room, online) : _board(room, online),
        ),
      ),
    );
  }

  Widget _header(RoomView room, {String? subtitle}) => ScreenHeader(
    title: room.inLobby ? 'Room ${room.roomCode}' : _matchTitle(room),
    subtitle: subtitle,
    onBack: () => _leave(ask: !room.isFinished),
    actions: [
      HeaderButton(
        icon: Icons.help_outline_rounded,
        label: 'How to play',
        onPressed: () => Navigator.of(
          context,
        ).push<void>(MaterialPageRoute(builder: (_) => const RulesScreen())),
      ),
      HeaderButton(
        icon: Icons.settings_rounded,
        label: 'Settings',
        onPressed: () => Navigator.of(
          context,
        ).push<void>(MaterialPageRoute(builder: (_) => const SettingsScreen())),
      ),
    ],
  );

  String _matchTitle(RoomView room) {
    final game = room.game;
    if (game == null || game.rounds <= 1) return 'Room ${room.roomCode}';
    return 'Round ${game.round} of ${game.rounds}';
  }

  /* ------------------------------------------------------------------ lobby */

  Widget _lobby(RoomView room, OnlineRoom online) {
    return Column(
      children: [
        _header(room, subtitle: room.settings.summary),
        if (online.trouble case final trouble?)
          _Banner(
            message: trouble,
            colour: Palette.coralDeep,
            icon: Icons.wifi_off_rounded,
            onRetry: _control.refresh,
          ),
        if (online.notice case final notice?)
          Shake(
            token: notice,
            child: _Banner(
              message: notice,
              colour: Palette.amber,
              foreground: Palette.inkDark,
              icon: Icons.info_rounded,
              onDismiss: _control.clearNotice,
            ),
          ),
        Expanded(
          child: LobbyPanel(
            room: room,
            coins: ref.watch(coinsProvider),
            busy: online.busy,
            onReady: _control.setReady,
            onStart: _control.start,
            onSettings: _control.applySettings,
            onAddBot: (level) => _control.addBot(level.wire),
            onKick: _control.kick,
            onLock: _control.setLocked,
            onCopied: _control.announce,
          ),
        ),
      ],
    );
  }

  /* ------------------------------------------------------------------ board */

  Widget _board(RoomView room, OnlineRoom online) {
    final game = room.game;
    if (game == null) {
      return Column(
        children: [
          _header(room),
          const Expanded(
            child: Center(
              child: CircularProgressIndicator(color: Palette.cream),
            ),
          ),
        ],
      );
    }

    final away = room.isPlaying && room.isHost
        ? room.players.where((p) => !p.isBot && !p.connected).toList()
        : const <RoomPlayer>[];

    return GameBoard(
      header: _header(room, subtitle: _boardSubtitle(room, game)),
      view: game,
      seats: room.seats,
      notice: online.notice,
      thinkingSeat: online.thinkingSeat,
      banner: _boardBanner(online, away),
      onPlay: _control.play,
      onPass: _control.passTurn,
      onRefused: (card) {
        HapticFeedback.selectionClick();
        _control.play(card);
      },
      // The server deals the next round on its own timer, so there is no button
      // for it. Play again is a new room, which only the host can make.
      onPlayAgain: room.isFinished && room.isHost && !online.busy
          ? _playAgain
          : null,
      onLeave: () => _leave(ask: false),
      waitingFor: _waitingFor(room, game),
      footer: _footer(room, game),
    );
  }

  String _boardSubtitle(RoomView room, PublicView game) {
    if (room.isFinished) return 'Match over';
    final left = room.players.where((p) => !p.isBot && !p.connected).length;
    if (left > 0) {
      return left == 1 ? '1 player is away' : '$left players are away';
    }
    return '${room.players.length} players, ${game.timerSeconds}s a turn';
  }

  Widget? _boardBanner(OnlineRoom online, List<RoomPlayer> away) {
    final parts = <Widget>[
      if (online.trouble case final trouble?)
        _Banner(
          message: trouble,
          colour: Palette.coralDeep,
          icon: Icons.wifi_off_rounded,
          onRetry: _control.refresh,
        ),
      for (final player in away)
        _Banner(
          key: ValueKey('away-${player.userId}'),
          message:
              '${player.name} has gone quiet. Their turns are playing out on '
              'the timer.',
          colour: Palette.violet,
          icon: Icons.cloud_off_rounded,
          actionLabel: 'Hand to a bot',
          onRetry: online.busy
              ? null
              : () => _control.handSeatToBot(player.seatIndex),
        ),
    ];
    if (parts.isEmpty) return null;
    return Column(mainAxisSize: MainAxisSize.min, children: parts);
  }

  /// Between rounds the server deals again on its own, so the panel says so
  /// instead of showing a button that would only race it.
  String? _waitingFor(RoomView room, PublicView game) {
    if (game.status != GameStatus.roundOver) return null;
    return 'The next round deals in a moment.';
  }

  Widget? _footer(RoomView room, PublicView game) {
    if (game.status != GameStatus.finished) return null;
    final result = room.result;
    final coinMatch = room.settings.coinMatch;
    final lines = <Widget>[];

    if (coinMatch && result != null) {
      final won = result.payoutFor(room.yourSeat);
      final staked = room.you?.stake ?? room.settings.entryFee;
      lines.add(_CoinLine(staked: staked, won: won, pool: result.pool));
    }
    if (room.isHost) {
      lines.add(
        const Text(
          'Play again makes a new room with these settings. Share the new code.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.25,
            fontWeight: FontWeight.w600,
            color: Palette.inkSoft,
          ),
        ),
      );
    } else {
      lines.add(
        const Text(
          'A finished room cannot be replayed. Ask the host for a new code.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.25,
            fontWeight: FontWeight.w600,
            color: Palette.inkSoft,
          ),
        ),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: lines);
  }

  Future<void> _playAgain() async {
    final made = await _control.playAgain();
    if (!made && mounted) {
      // playAgain already put the reason in the notice, which the lobby and the
      // board both show, so there is nothing more to say here.
      setState(() {});
    }
  }
}

/// Coins in and coins out, spelled out rather than left as a balance change.
class _CoinLine extends StatelessWidget {
  const _CoinLine({
    required this.staked,
    required this.won,
    required this.pool,
  });

  final int staked;
  final int won;
  final int pool;

  @override
  Widget build(BuildContext context) {
    final net = won - staked;
    final up = net > 0;
    final colour = net == 0
        ? Palette.inkSoft
        : up
        ? Palette.feltDark
        : Palette.coralDeep;
    final headline = net == 0
        ? 'You got your $staked coins back'
        : up
        ? 'You won $net coins'
        : 'You lost ${-net} coins';

    return PopIn(
      // Arrives just after the placings have settled, since the coins are the
      // part of a coin match a player waits for.
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Palette.mist,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colour, width: 2),
        ),
        child: Row(
          children: [
            Icon(
              up ? Icons.trending_up_rounded : Icons.monetization_on_rounded,
              size: 26,
              color: colour,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    headline,
                    style: TextStyle(
                      fontSize: 17,
                      height: 1.2,
                      fontWeight: FontWeight.w900,
                      color: colour,
                    ),
                  ),
                  Text(
                    'Entry $staked, paid out $won, pot of $pool',
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                      color: Palette.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line across the top of the room, for a connection problem or a seat that
/// has gone quiet. Never covers anything that can be tapped.
class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.message,
    required this.colour,
    required this.icon,
    this.foreground = Palette.white,
    this.actionLabel,
    this.onRetry,
    this.onDismiss,
  });

  final String message;
  final Color colour;
  final IconData icon;
  final Color foreground;
  final String? actionLabel;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return FadeSlideIn(
      dy: -10,
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 2, 10, 4),
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        decoration: BoxDecoration(
          color: colour,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: foreground.withValues(alpha: 0.6),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: foreground),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                ),
              ),
            ),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, Sizes.tap),
                  foregroundColor: foreground,
                ),
                child: Text(
                  actionLabel ?? 'Retry',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: foreground,
                  ),
                ),
              ),
            if (onDismiss != null)
              IconButton(
                onPressed: onDismiss,
                tooltip: 'Dismiss',
                iconSize: 22,
                constraints: const BoxConstraints(
                  minWidth: Sizes.tap,
                  minHeight: Sizes.tap,
                ),
                style: IconButton.styleFrom(foregroundColor: foreground),
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
      ),
    );
  }
}

/// The room has gone: kicked, closed, or left. Says which, and gives one way out.
class _NoRoom extends StatelessWidget {
  const _NoRoom({
    required this.stage,
    required this.reason,
    required this.leaving,
    required this.onHome,
  });

  final RoomStage stage;
  final String? reason;
  final bool leaving;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
    if (stage == RoomStage.joining || leaving) {
      return const Center(
        child: CircularProgressIndicator(color: Palette.cream),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: PopIn(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.meeting_room_outlined,
                size: 56,
                color: Palette.cream,
              ),
              const SizedBox(height: 12),
              Text(
                reason ?? 'That room has closed.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 19,
                  height: 1.3,
                  fontWeight: FontWeight.w800,
                  color: Palette.cream,
                ),
              ),
              const SizedBox(height: 20),
              BigButton(
                label: 'Back',
                icon: Icons.arrow_back_rounded,
                expand: false,
                onPressed: onHome,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
