/// The board: the reusable playing surface, and the solo screen that drives it.
///
/// GameBoard knows nothing about where its state came from, so the same widget
/// serves the offline match and, later, an online room. Everything it animates is
/// worked out from the view it is handed: a card that appears on the table gets
/// flown in from the seat that played it, a pass floats a label off that seat.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/cards.dart' as cards;
import '../game/engine.dart';
import '../game/narrate.dart' as narrate;
import '../models/seat_info.dart';
import '../state/cosmetics.dart';
import '../state/solo.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/avatar_circle.dart';
import '../widgets/big_button.dart';
import '../widgets/hand_strip.dart';
import '../widgets/round_over_panel.dart';
import '../widgets/screen_header.dart';
import '../widgets/seat_badge.dart';
import '../widgets/table_board.dart';
import 'rules_screen.dart';
import 'settings_screen.dart';

class GameBoard extends StatefulWidget {
  const GameBoard({
    super.key,
    required this.header,
    required this.view,
    required this.seats,
    required this.onPlay,
    required this.onPass,
    required this.onRefused,
    this.notice,
    this.thinkingSeat,
    this.paused = false,
    this.banner,
    this.onNextRound,
    this.onPlayAgain,
    this.onLeave,
    this.waitingFor,
    this.footer,
  });

  final Widget header;
  final PublicView view;
  final List<SeatInfo> seats;

  final void Function(String card) onPlay;
  final VoidCallback onPass;

  /// A tap on a card that cannot be played. The owner decides what to say.
  final void Function(String card) onRefused;

  final String? notice;
  final int? thinkingSeat;
  final bool paused;

  /// Connection state and similar, shown above the seats.
  final Widget? banner;

  final VoidCallback? onNextRound;
  final VoidCallback? onPlayAgain;
  final VoidCallback? onLeave;
  final String? waitingFor;
  final Widget? footer;

  @override
  State<GameBoard> createState() => _GameBoardState();
}

class _GameBoardState extends State<GameBoard> {
  final GlobalKey _stackKey = GlobalKey();
  final GlobalKey _youKey = GlobalKey();
  final Map<String, GlobalKey> _rowKeys = {
    for (final suit in cards.suits) suit: GlobalKey(),
  };
  final Map<int, GlobalKey> _seatKeys = {};
  final List<_Floater> _floaters = [];

  _Flight? _flight;
  String? _hiddenCard;
  int _flightToken = 0;
  double _tableCardWidth = 40;

  _PassNotice? _passNotice;
  int _passToken = 0;
  Timer? _passTimer;

  /// Where the finger left the card, so your own play starts from the card you
  /// actually touched rather than from somewhere near the middle.
  Rect? _tapRect;

  String? _actionKey;

  @override
  void initState() {
    super.initState();
    _actionKey = _keyOf(widget.view.lastAction);
  }

  @override
  void dispose() {
    _passTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(GameBoard old) {
    super.didUpdateWidget(old);
    final action = widget.view.lastAction;
    final key = _keyOf(action);
    if (key == _actionKey) return;
    _actionKey = key;
    if (action == null) return;

    if (action.isPlay && action.card != null) {
      // Hidden from this build onwards, so the card is not in two places while
      // it is still in the air.
      _hiddenCard = action.card;
      final entry = action;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fly(entry));
    } else if (action.isPass) {
      final entry = action;
      WidgetsBinding.instance.addPostFrameCallback((_) => _float(entry));
    }
  }

  String? _keyOf(ActionEntry? action) => action == null
      ? null
      : '${action.type}:${action.at}:${action.seatIndex}:${action.card}';

  RenderBox? get _stackBox =>
      _stackKey.currentContext?.findRenderObject() as RenderBox?;

  Rect? _localRect(GlobalKey? key) {
    final box = key?.currentContext?.findRenderObject() as RenderBox?;
    final stack = _stackBox;
    if (box == null || stack == null || !box.hasSize || !stack.hasSize) {
      return null;
    }
    return stack.globalToLocal(box.localToGlobal(Offset.zero)) & box.size;
  }

  Rect? _toLocal(Rect global) {
    final stack = _stackBox;
    if (stack == null || !stack.hasSize) return null;
    return stack.globalToLocal(global.topLeft) & global.size;
  }

  void _fly(ActionEntry action) {
    if (!mounted) return;
    final card = action.card!;
    final parsed = cards.parseCard(card);
    final rowRect = _localRect(_rowKeys[parsed.suit]);
    if (rowRect == null) {
      setState(() => _hiddenCard = null);
      return;
    }

    final width = _tableCardWidth;
    final step = TableMetrics.step(rowRect.width, width);
    final target = Rect.fromLTWH(
      rowRect.left + TableMetrics.left(step, parsed.rank),
      rowRect.top,
      width,
      Sizes.cardHeightFor(width),
    );

    Rect? from;
    var flip = false;
    if (action.seatIndex == widget.view.yourSeat && _tapRect != null) {
      from = _toLocal(_tapRect!);
      _tapRect = null;
    } else {
      final seatRect = _localRect(_seatKeys[action.seatIndex]);
      if (seatRect != null) {
        from = Rect.fromCenter(
          center: seatRect.center,
          width: target.width * 0.55,
          height: target.height * 0.55,
        );
        flip = true;
      }
    }
    // Nothing to measure, for instance a seat that is not on screen. Come up
    // from under the table instead of skipping the animation.
    from ??= target.shift(const Offset(0, 120));

    if (action.auto) _pushFloater(action, 'Timed out', Icons.timer_off_rounded);

    _flightToken += 1;
    final token = _flightToken;
    setState(() {
      _flight = _Flight(
        token: token,
        card: card,
        from: from!,
        to: target,
        flip: flip,
      );
    });
  }

  void _float(ActionEntry action) {
    if (!mounted) return;
    _pushFloater(
      action,
      action.auto ? 'Timed out, passed' : 'Pass',
      action.auto ? Icons.timer_off_rounded : Icons.block_rounded,
    );

    final seatName = action.seatIndex == widget.view.yourSeat
        ? 'You'
        : narrate.seatName(widget.seats, action.seatIndex);
    final text = action.auto
        ? '$seatName timed out — passed'
        : '$seatName passed!';

    _passToken += 1;
    final token = _passToken;
    setState(() {
      _passNotice = _PassNotice(
        token: token,
        text: text,
        isAuto: action.auto,
      );
    });

    _passTimer?.cancel();
    _passTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted || _passToken != token) return;
      setState(() => _passNotice = null);
    });
  }

  void _pushFloater(ActionEntry action, String text, IconData icon) {
    final anchor = action.seatIndex == widget.view.yourSeat
        ? _localRect(_youKey)
        : _localRect(_seatKeys[action.seatIndex]);
    if (anchor == null) return;
    final floater = _Floater(
      id: UniqueKey(),
      text: text,
      icon: icon,
      anchor: anchor,
      colour: action.auto ? Palette.coral : Palette.cream,
    );
    setState(() => _floaters.add(floater));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      // The felt is the one thing a table theme changes. Everything drawn on top
      // keeps its own colours, so contrast never depends on what was bought.
      builder: (context, ref, _) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: ref.watch(equippedTableProvider).gradient,
        ),
        child: _board(context),
      ),
    );
  }

  Widget _board(BuildContext context) {
    final view = widget.view;
    final live = view.status == GameStatus.inProgress;
    final yourTurn = live && view.isMyTurn;
    final deadline = live && !widget.paused
        ? view.turnStartedAt + view.timerSeconds * 1000
        : null;

    for (final seat in widget.seats) {
      _seatKeys.putIfAbsent(seat.index, GlobalKey.new);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Held sideways there is width to spare and no height at all, so the
        // seats move into a side rail and the table folds into two columns of two
        // suits. Cards stay close to the size they are in portrait.
        final wide = constraints.maxWidth > constraints.maxHeight;
        final handWidth = _handCardWidth(constraints, wide: wide);
        final columns = wide ? 2 : 1;
        final rail = _railWidth(constraints);

        final seats = Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SeatStrip(
            seats: widget.seats,
            handCounts: view.handCounts,
            currentTurnSeat: view.currentTurnSeat,
            turnDeadline: deadline,
            timerSeconds: view.timerSeconds,
            thinkingSeat: widget.thinkingSeat,
            hideSeat: view.yourSeat,
            roundLive: live,
            seatKeys: _seatKeys,
          ),
        );

        final table = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: LayoutBuilder(
            builder: (context, tableBox) {
              _tableCardWidth = _tableWidthFor(tableBox, columns);
              return TableBoard(
                table: view.table,
                cardWidth: _tableCardWidth,
                columns: columns,
                lastCard: _lastPlayedCard(view),
                hiddenCard: _hiddenCard,
                rowKeys: _rowKeys,
              );
            },
          ),
        );

        final status = _StatusPanel(
          view: view,
          seats: widget.seats,
          notice: widget.notice,
          paused: widget.paused,
        );

        final hand = HandStrip(
          hand: view.yourHand,
          legal: yourTurn ? view.yourLegalMoves : const [],
          cardWidth: handWidth,
          yourTurn: yourTurn,
          dealToken: view.round * 1000 + view.seatCount,
          onPlay: (card, rect) {
            _tapRect = rect;
            widget.onPlay(card);
          },
          onRefused: widget.onRefused,
        );

        final bottom = _BottomBar(
          youKey: _youKey,
          seat: _yourSeat(),
          cardCount: _yourCount(view),
          yourTurn: yourTurn,
          deadline: deadline,
          timerSeconds: view.timerSeconds,
          hasLegalMove: view.yourLegalMoves.isNotEmpty,
          onPass: widget.onPass,
        );

        return Stack(
          key: _stackKey,
          children: [
            if (wide)
              Column(
                children: [
                  widget.header,
                  if (widget.banner != null) widget.banner!,
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: table),
                        // A full table of eight scrolls its seats rather than
                        // squeezing the table for the two rows it would take.
                        SizedBox(
                          width: rail,
                          child: SingleChildScrollView(child: seats),
                        ),
                      ],
                    ),
                  ),
                  status,
                  // Pass stays under the rail, which sideways is under the thumb
                  // of the hand holding that edge of the phone.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: hand),
                      SizedBox(width: rail, child: bottom),
                    ],
                  ),
                ],
              )
            else
              Column(
                children: [
                  widget.header,
                  if (widget.banner != null) widget.banner!,
                  seats,
                  Expanded(child: table),
                  status,
                  hand,
                  bottom,
                ],
              ),
            if (_flight case final flight?)
              CardFlight(
                key: ValueKey(flight.token),
                code: flight.card,
                from: flight.from,
                to: flight.to,
                flip: flight.flip,
                onDone: () {
                  // A quick second play can start a new flight before this one
                  // reports back. Only the current flight may clear the state.
                  if (!mounted || _flight?.token != flight.token) return;
                  setState(() {
                    _flight = null;
                    _hiddenCard = null;
                  });
                },
              ),
            for (final floater in _floaters)
              FloatUpLabel(
                key: floater.id,
                text: floater.text,
                icon: floater.icon,
                anchor: floater.anchor,
                colour: floater.colour,
                onDone: () {
                  if (!mounted) return;
                  setState(
                    () => _floaters.removeWhere(
                      (entry) => entry.id == floater.id,
                    ),
                  );
                },
              ),
            if (_passNotice case final notice?)
              Positioned(
                top: 72,
                left: 16,
                right: 16,
                child: Center(
                  child: PopIn(
                    key: ValueKey(notice.token),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Palette.inkDark.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: notice.isAuto ? Palette.coral : Palette.amber,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (notice.isAuto ? Palette.coral : Palette.amber)
                                .withValues(alpha: 0.45),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            notice.isAuto
                                ? Icons.timer_off_rounded
                                : Icons.motion_photos_auto_rounded,
                            color: notice.isAuto ? Palette.coral : Palette.amber,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            notice.text,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (!live)
              Positioned.fill(
                child: RoundOverPanel(
                  view: view,
                  seats: widget.seats,
                  onNextRound: widget.onNextRound,
                  onPlayAgain: widget.onPlayAgain,
                  onLeave: widget.onLeave,
                  waitingFor: widget.waitingFor,
                  footer: widget.footer,
                ),
              ),
          ],
        );
      },
    );
  }

  /// The card the eye should be drawn to, which is the last one played and not
  /// still flying.
  String? _lastPlayedCard(PublicView view) {
    final action = view.lastAction;
    if (action == null || !action.isPlay) return null;
    return action.card;
  }

  SeatInfo _yourSeat() {
    final seat = widget.view.yourSeat;
    if (seat != null && seat >= 0 && seat < widget.seats.length) {
      return widget.seats[seat];
    }
    return const SeatInfo(index: -1, name: 'You', avatar: 0, isYou: true);
  }

  int _yourCount(PublicView view) {
    final seat = view.yourSeat;
    if (seat == null || seat >= view.handCounts.length) {
      return view.yourHand.length;
    }
    return view.handCounts[seat];
  }

  /// The side rail on a wide screen. Wide enough for two seats abreast, and never
  /// more than a third of the board.
  double _railWidth(BoxConstraints constraints) =>
      (constraints.maxWidth * 0.30).clamp(210.0, 300.0);

  /// Hand cards are as big as the width allows, then trimmed so a short screen
  /// still leaves the table enough room to show every suit.
  double _handCardWidth(BoxConstraints constraints, {required bool wide}) {
    final byWidth = constraints.maxWidth / (wide ? 9.5 : 6.6);
    final byHeight =
        (constraints.maxHeight * (wide ? 0.34 : 0.24) - 58) * Sizes.cardAspect;
    final chosen = byWidth < byHeight ? byWidth : byHeight;
    return chosen.clamp(40.0, 78.0);
  }

  /// Thirteen ranks per row. Width sets the overlap, height sets the cap, and the
  /// column count decides how much of each the rows get.
  double _tableWidthFor(BoxConstraints constraints, int columns) {
    final columnWidth = TableMetrics.columnWidth(constraints.maxWidth, columns);
    final byWidth = TableMetrics.rowWidth(columnWidth, 20) / 6.4;
    final rows = (cards.suits.length / columns).ceil();
    final rowHeight = constraints.maxHeight / rows - TableMetrics.rowGap * 2;
    final byHeight = rowHeight * Sizes.cardAspect;
    final chosen = byWidth < byHeight ? byWidth : byHeight;
    return chosen.clamp(18.0, 74.0);
  }
}

class _Flight {
  const _Flight({
    required this.token,
    required this.card,
    required this.from,
    required this.to,
    required this.flip,
  });

  final int token;
  final String card;
  final Rect from;
  final Rect to;
  final bool flip;
}

class _Floater {
  const _Floater({
    required this.id,
    required this.text,
    required this.icon,
    required this.anchor,
    required this.colour,
  });

  final Key id;
  final String text;
  final IconData icon;
  final Rect anchor;
  final Color colour;
}

/// What just happened, and what to do now. Two lines, always in the same place,
/// so a player never has to hunt for the instruction.
class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.view,
    required this.seats,
    required this.notice,
    required this.paused,
  });

  final PublicView view;
  final List<SeatInfo> seats;
  final String? notice;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final warn = notice != null;
    final live = view.status == GameStatus.inProgress;
    final yourTurn = live && view.isMyTurn && !paused;
    final prompt = warn
        ? notice!
        : paused
        ? 'Paused. The clock starts again when you come back.'
        : narrate.turnPrompt(view, seats);
    final history = narrate.describeLastAction(view, seats) ?? 'Cards dealt';

    return Shake(
      token: notice,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
        // One halo when the turn lands on you. A player looking at their hand
        // still catches it out of the corner of their eye.
        child: AttentionPulse(
          token: warn || !yourTurn ? null : 'turn-${view.turnStartedAt}',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: warn ? Palette.amber : Palette.feltDark,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: warn
                    ? Palette.white
                    : Palette.cream.withValues(alpha: 0.25),
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  warn
                      ? Icons.info_rounded
                      : paused
                      ? Icons.pause_circle_filled_rounded
                      : yourTurn
                      ? Icons.touch_app_rounded
                      : Icons.hourglass_top_rounded,
                  size: 26,
                  color: warn ? Palette.inkDark : Palette.cream,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: Anim.swap,
                    child: Column(
                      key: ValueKey('$prompt|$history'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          prompt,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            height: 1.15,
                            fontWeight: FontWeight.w800,
                            color: warn ? Palette.inkDark : Palette.cream,
                          ),
                        ),
                        Text(
                          history,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            color: warn
                                ? Palette.inkDark.withValues(alpha: 0.75)
                                : Palette.cream.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Your own seat and the Pass button, both under the thumb.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.youKey,
    required this.seat,
    required this.cardCount,
    required this.yourTurn,
    required this.deadline,
    required this.timerSeconds,
    required this.hasLegalMove,
    required this.onPass,
  });

  final GlobalKey youKey;
  final SeatInfo seat;
  final int cardCount;
  final bool yourTurn;
  final int? deadline;
  final int timerSeconds;
  final bool hasLegalMove;
  final VoidCallback onPass;

  @override
  Widget build(BuildContext context) {
    final avatar = AvatarCircle(avatar: seat.avatar, size: 46);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
      child: Row(
        children: [
          SizedBox(
            key: youKey,
            width: 62,
            child: Center(
              child: yourTurn
                  ? TurnRing(
                      size: 58,
                      deadline: deadline,
                      totalMillis: timerSeconds * 1000,
                      child: avatar,
                    )
                  : avatar,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            // When there is nothing playable, passing is the whole turn, so the
            // button says so once rather than waiting to be found.
            child: AttentionPulse(
              token: yourTurn && !hasLegalMove ? 'pass-${deadline ?? 0}' : null,
              radius: Sizes.radius,
              colour: Palette.coral,
              child: BigButton(
                label: 'Pass',
                icon: Icons.block_rounded,
                colour: Palette.coral,
                foreground: Palette.white,
                minHeight: 62,
                muted: hasLegalMove,
                subtitle: yourTurn && hasLegalMove
                    ? 'You still have a card to play'
                    : null,
                onPressed: yourTurn ? onPass : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The solo match screen: local engine, local bots, local clock.
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Backgrounding must not lose a turn in a game with no server to keep time.
    _lifecycle = AppLifecycleListener(
      onPause: () => ref.read(soloGameProvider.notifier).pauseClock(),
      onRestart: () => ref.read(soloGameProvider.notifier).resumeClock(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave this match?'),
        content: const Text('The match will not be saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep playing', style: TextStyle(fontSize: 17)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave', style: TextStyle(fontSize: 17)),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final game = ref.watch(soloGameProvider);
    final control = ref.read(soloGameProvider.notifier);
    final view = game.view;
    final over = view.status != GameStatus.inProgress;

    return Scaffold(
      body: SafeArea(
        child: PopScope(
          canPop: over,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _confirmLeave();
          },
          child: GameBoard(
            header: ScreenHeader(
              title: game.config.rounds > 1
                  ? 'Round ${view.round} of ${view.rounds}'
                  : 'Beatful',
              subtitle:
                  '${game.seats.length} players, '
                  '${game.config.difficulty.label.toLowerCase()} bots',
              onBack: over ? () => Navigator.of(context).pop() : _confirmLeave,
              actions: [
                HeaderButton(
                  icon: Icons.help_outline_rounded,
                  label: 'How to play',
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const RulesScreen()),
                  ),
                ),
                HeaderButton(
                  icon: Icons.settings_rounded,
                  label: 'Settings',
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                ),
              ],
            ),
            view: view,
            seats: game.seats,
            notice: game.notice,
            thinkingSeat: game.thinkingSeat,
            paused: game.paused,
            onPlay: control.play,
            onPass: control.passTurn,
            onRefused: (card) {
              HapticFeedback.selectionClick();
              control.play(card);
            },
            onNextRound: game.roundOver ? control.nextRound : null,
            onPlayAgain: game.matchOver ? control.restart : null,
            onLeave: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }
}

class _PassNotice {
  const _PassNotice({
    required this.token,
    required this.text,
    required this.isAuto,
  });

  final int token;
  final String text;
  final bool isAuto;
}
