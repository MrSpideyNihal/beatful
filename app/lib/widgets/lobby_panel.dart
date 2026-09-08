/// The lobby: the code to share, who is in, and the host's controls.
///
/// Everything a guest sees is read only, and it is the same list the host edits,
/// so nobody has to guess what the match will be. The host's changes go straight
/// to the server, which is the only place the settings actually live.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/bots.dart';
import '../models/room.dart';
import '../models/room_code.dart';
import '../state/solo_config.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/avatar_circle.dart';
import '../widgets/big_button.dart';
import '../widgets/choice_row.dart';

/// Entry fees offered as buttons. A stepper would take a lot of taps to reach a
/// useful number, and these cover the range people actually play for.
const List<int> entryFeeChoices = [10, 25, 50, 100, 250];

/// The smallest fee a coin match can carry. The server refuses a coin match with
/// no fee, so switching the toggle on has to bring one with it.
const int minEntryFee = 10;

class LobbyPanel extends StatelessWidget {
  const LobbyPanel({
    super.key,
    required this.room,
    required this.coins,
    required this.busy,
    required this.onReady,
    required this.onStart,
    required this.onSettings,
    required this.onAddBot,
    required this.onKick,
    required this.onLock,
    required this.onCopied,
  });

  final RoomView room;
  final int coins;
  final bool busy;

  final ValueChanged<bool> onReady;
  final VoidCallback onStart;
  final void Function(Map<String, Object?> patch) onSettings;
  final ValueChanged<BotDifficulty> onAddBot;
  final ValueChanged<String> onKick;
  final ValueChanged<bool> onLock;

  /// Told what was put on the clipboard, so the room can say so in its own voice
  /// rather than through a floating bar that covers the buttons.
  final ValueChanged<String> onCopied;

  bool get _host => room.isHost;

  int get _humans => room.players.where((player) => !player.isBot).length;

  int get _notReady =>
      room.players.where((player) => !player.isBot && !player.ready).length;

  @override
  Widget build(BuildContext context) {
    final settings = room.settings;
    final canStart = _host && !busy && room.players.length >= 2;
    final shortOfCoins = settings.coinMatch && coins < settings.entryFee;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
            children: [
              FadeSlideIn(
                child: _CodeCard(
                  code: room.roomCode,
                  link: room.link.isEmpty
                      ? roomLinkFor(room.roomCode)
                      : room.link,
                  locked: room.locked,
                  onCopied: onCopied,
                ),
              ),
              FadeSlideIn(
                delay: const Duration(milliseconds: 60),
                child: _PlayersCard(
                  room: room,
                  host: _host,
                  busy: busy,
                  onKick: onKick,
                  onAddBot: onAddBot,
                ),
              ),
              FadeSlideIn(
                delay: const Duration(milliseconds: 120),
                child: _host
                    ? _HostSettings(
                        room: room,
                        coins: coins,
                        busy: busy,
                        onSettings: onSettings,
                        onLock: onLock,
                      )
                    : _GuestSettings(room: room, coins: coins),
              ),
            ],
          ),
        ),
        if (shortOfCoins)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
            child: _Warning(
              icon: Icons.savings_rounded,
              message:
                  'This match costs ${settings.entryFee} coins to enter and you '
                  'have $coins. Earn some in the shop, or ask the host to make '
                  'it a free match.',
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
          child: _host
              ? BigButton(
                  label: busy ? 'Starting' : 'Start match',
                  icon: Icons.play_arrow_rounded,
                  minHeight: 74,
                  subtitle: _startHint(),
                  onPressed: canStart ? onStart : null,
                )
              : _ReadyButton(
                  ready: room.you?.ready ?? false,
                  busy: busy,
                  onReady: onReady,
                ),
        ),
      ],
    );
  }

  String _startHint() {
    if (room.players.length < 2) {
      return 'You need one more player, or add a bot';
    }
    if (_notReady > 0) {
      return _notReady == 1
          ? '1 player has not tapped Ready. You can still start.'
          : '$_notReady players have not tapped Ready. You can still start.';
    }
    if (_humans == 1) return 'Everybody ready. You are the only human here.';
    return 'Everybody is ready';
  }
}

/// The code, big enough to read out across a room, with the link beside it.
class _CodeCard extends StatelessWidget {
  const _CodeCard({
    required this.code,
    required this.link,
    required this.locked,
    required this.onCopied,
  });

  final String code;
  final String link;
  final bool locked;
  final ValueChanged<String> onCopied;

  Future<void> _copy(String text, String said) async {
    await Clipboard.setData(ClipboardData(text: text));
    onCopied(said);
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Your room code',
      hint: locked
          ? 'The room is closed. Unlock it below to let anybody else in.'
          : 'Read it out, or copy the invite and send it.',
      child: Column(
        children: [
          Semantics(
            label: 'Room code ${code.split('').join(' ')}',
            child: ExcludeSemantics(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Palette.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Palette.amber, width: 3),
                ),
                child: Text(
                  code,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 40,
                    height: 1.1,
                    letterSpacing: 8,
                    fontWeight: FontWeight.w900,
                    color: Palette.ink,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: PillButton(
                  label: 'Copy code',
                  icon: Icons.content_copy_rounded,
                  onPressed: () => _copy(code, 'Code copied.'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PillButton(
                  label: 'Copy invite',
                  icon: Icons.ios_share_rounded,
                  colour: Palette.amber,
                  filled: true,
                  onPressed: () => _copy(
                    'Join my Beatful game. Room code $code, or tap $link',
                    'Invite copied. Paste it into any chat.',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlayersCard extends StatelessWidget {
  const _PlayersCard({
    required this.room,
    required this.host,
    required this.busy,
    required this.onKick,
    required this.onAddBot,
  });

  final RoomView room;
  final bool host;
  final bool busy;
  final ValueChanged<String> onKick;
  final ValueChanged<BotDifficulty> onAddBot;

  @override
  Widget build(BuildContext context) {
    final free = room.seatsFree;
    return SectionCard(
      title: 'Players',
      hint: '${room.seatsFilled} of ${room.settings.playerCount} seats taken',
      child: Column(
        children: [
          for (final player in room.players)
            FadeSlideIn(
              key: ValueKey(player.userId),
              dy: 10,
              child: _PlayerRow(
                player: player,
                hostUserId: room.hostUserId,
                canKick: host && !busy && !player.isYou,
                onKick: () => onKick(player.userId),
              ),
            ),
          for (var i = 0; i < free; i += 1)
            _EmptySeatRow(key: ValueKey('empty-$i')),
          if (host && free > 0) ...[
            const SizedBox(height: 4),
            _AddBotRow(busy: busy, onAddBot: onAddBot),
          ],
        ],
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.player,
    required this.hostUserId,
    required this.canKick,
    required this.onKick,
  });

  final RoomPlayer player;
  final String hostUserId;
  final bool canKick;
  final VoidCallback onKick;

  @override
  Widget build(BuildContext context) {
    final isHost = player.userId == hostUserId;
    final ready = player.isBot || player.ready;
    final badges = <_Badge>[
      if (player.isYou) const _Badge('You', Palette.blue, Icons.person_rounded),
      if (isHost)
        const _Badge('Host', Palette.violet, Icons.workspace_premium_rounded),
      if (player.isBot)
        _Badge(
          '${player.difficulty?.label ?? 'Medium'} bot',
          Palette.teal,
          Icons.smart_toy_rounded,
        ),
      if (!player.connected)
        const _Badge('Away', Palette.coral, Icons.cloud_off_rounded),
    ];

    return Semantics(
      label:
          '${player.name}, ${ready ? 'ready' : 'not ready yet'}'
          '${isHost ? ', host' : ''}',
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: Sizes.tap),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
          decoration: BoxDecoration(
            color: Palette.felt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: ready
                  ? Palette.lime.withValues(alpha: 0.7)
                  : Palette.cream.withValues(alpha: 0.22),
              width: 2,
            ),
          ),
          child: Row(
            children: [
              AvatarCircle(
                avatar: player.avatarId,
                size: 42,
                faded: !player.connected,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      (!player.isYou &&
                              (player.name.trim().isEmpty ||
                                  player.name.trim().toLowerCase() == 'you'))
                          ? 'Player ${player.seatIndex + 1}'
                          : player.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        color: Palette.cream,
                      ),
                    ),
                    if (badges.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: badges,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              PopIn(
                key: ValueKey(ready),
                child: Icon(
                  ready
                      ? Icons.check_circle_rounded
                      : Icons.hourglass_empty_rounded,
                  size: 26,
                  color: ready ? Palette.lime : Palette.cream,
                ),
              ),
              if (canKick)
                IconButton(
                  onPressed: onKick,
                  tooltip: 'Remove ${player.name}',
                  iconSize: 24,
                  constraints: const BoxConstraints(
                    minWidth: Sizes.tap,
                    minHeight: Sizes.tap,
                  ),
                  style: IconButton.styleFrom(foregroundColor: Palette.coral),
                  icon: const Icon(Icons.person_remove_rounded),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptySeatRow extends StatelessWidget {
  const _EmptySeatRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: Sizes.tap),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Palette.cream.withValues(alpha: 0.2),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.person_outline_rounded,
            size: 34,
            color: Palette.cream.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 12),
          Text(
            'Empty seat',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Palette.cream.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddBotRow extends StatefulWidget {
  const _AddBotRow({required this.busy, required this.onAddBot});

  final bool busy;
  final ValueChanged<BotDifficulty> onAddBot;

  @override
  State<_AddBotRow> createState() => _AddBotRowState();
}

class _AddBotRowState extends State<_AddBotRow> {
  BotDifficulty _level = BotDifficulty.medium;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChoiceRow<BotDifficulty>(
          value: _level,
          onChanged: (value) => setState(() => _level = value),
          options: [
            for (final level in BotDifficulty.values)
              ChoiceOption(value: level, label: level.label),
          ],
        ),
        const SizedBox(height: 8),
        PillButton(
          label: 'Add a ${_level.label.toLowerCase()} bot',
          icon: Icons.smart_toy_rounded,
          colour: Palette.teal,
          filled: true,
          onPressed: widget.busy ? null : () => widget.onAddBot(_level),
        ),
      ],
    );
  }
}

/// The host's controls. Every change is sent on its own, so a failure only ever
/// undoes the one setting that failed.
class _HostSettings extends StatelessWidget {
  const _HostSettings({
    required this.room,
    required this.coins,
    required this.busy,
    required this.onSettings,
    required this.onLock,
  });

  final RoomView room;
  final int coins;
  final bool busy;
  final void Function(Map<String, Object?> patch) onSettings;
  final ValueChanged<bool> onLock;

  void _send(Map<String, Object?> patch) {
    if (busy) return;
    onSettings(patch);
  }

  @override
  Widget build(BuildContext context) {
    final settings = room.settings;
    // Never below the number already sitting down, or the room would refuse the
    // players it already has.
    final floor = room.players.length < 2 ? 2 : room.players.length;

    return Column(
      children: [
        SectionCard(
          title: 'Seats',
          hint: 'How many players this room holds.',
          child: CountStepper(
            value: settings.playerCount < floor ? floor : settings.playerCount,
            min: floor,
            max: 8,
            unit: 'players',
            onChanged: (value) => _send({'playerCount': value}),
          ),
        ),
        SectionCard(
          title: 'Time per turn',
          hint: 'Run out of time and the turn is played for you.',
          child: ChoiceRow<int>(
            value: settings.timerSeconds,
            onChanged: (value) => _send({'timerSeconds': value}),
            options: [
              for (final seconds in timerChoices)
                ChoiceOption(value: seconds, label: '$seconds sec'),
              if (!timerChoices.contains(settings.timerSeconds))
                ChoiceOption(
                  value: settings.timerSeconds,
                  label: '${settings.timerSeconds} sec',
                ),
            ],
          ),
        ),
        SectionCard(
          title: 'Rounds',
          hint: 'More rounds means the best player over all of them wins.',
          child: ChoiceRow<int>(
            value: settings.rounds,
            onChanged: (value) => _send({'rounds': value}),
            options: [
              for (final rounds in roundChoices)
                ChoiceOption(
                  value: rounds,
                  label: rounds == 1 ? '1 round' : '$rounds rounds',
                ),
              if (!roundChoices.contains(settings.rounds))
                ChoiceOption(
                  value: settings.rounds,
                  label: '${settings.rounds} rounds',
                ),
            ],
          ),
        ),
        SectionCard(
          title: 'The table',
          child: Column(
            children: [
              ToggleRow(
                label: 'Shuffle the seat order',
                icon: Icons.shuffle_rounded,
                hint: settings.shuffleSeats
                    ? 'Turn order is drawn at the start'
                    : 'Turn order follows the order people joined',
                value: settings.shuffleSeats,
                onChanged: (value) => _send({'shuffleSeats': value}),
              ),
              ToggleRow(
                label: 'Fill empty seats with bots',
                icon: Icons.smart_toy_rounded,
                hint: settings.fillWithBots
                    ? 'Any seat still empty at Start becomes a bot'
                    : 'Empty seats stay empty',
                value: settings.fillWithBots,
                onChanged: (value) => _send({'fillWithBots': value}),
              ),
              if (settings.fillWithBots)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ChoiceRow<BotDifficulty>(
                    value: settings.botDifficulty,
                    onChanged: (value) => _send({'botDifficulty': value.wire}),
                    options: [
                      for (final level in BotDifficulty.values)
                        ChoiceOption(value: level, label: level.label),
                    ],
                  ),
                ),
              ToggleRow(
                label: 'Close the room',
                icon: Icons.lock_rounded,
                hint: room.locked
                    ? 'Nobody else can join with the code'
                    : 'Anybody with the code can join',
                value: room.locked,
                onChanged: busy ? (_) {} : onLock,
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Coins',
          hint: 'You have $coins coins.',
          child: Column(
            children: [
              ToggleRow(
                label: 'Play for coins',
                icon: Icons.monetization_on_rounded,
                hint: settings.coinMatch
                    ? 'Everybody pays the entry fee at Start'
                    : 'Free match, no coins at stake',
                value: settings.coinMatch,
                onChanged: (value) => _send({
                  'coinMatch': value,
                  // A coin match with no fee is refused by the server, so the
                  // toggle brings a fee with it.
                  'entryFee': value
                      ? (settings.entryFee < minEntryFee
                            ? minEntryFee
                            : settings.entryFee)
                      : settings.entryFee,
                }),
              ),
              if (settings.coinMatch) ...[
                ChoiceRow<int>(
                  value: settings.entryFee,
                  onChanged: (value) => _send({'entryFee': value}),
                  options: [
                    for (final fee in entryFeeChoices)
                      ChoiceOption(value: fee, label: '$fee coins'),
                    if (!entryFeeChoices.contains(settings.entryFee))
                      ChoiceOption(
                        value: settings.entryFee,
                        label: '${settings.entryFee} coins',
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                ChoiceRow<PayoutMode>(
                  stacked: true,
                  value: settings.payout,
                  onChanged: (value) => _send({
                    'payout': value == PayoutMode.rankedSplit
                        ? 'ranked_split'
                        : 'winner_takes_all',
                  }),
                  options: const [
                    ChoiceOption(
                      value: PayoutMode.winnerTakesAll,
                      label: 'Winner takes the pot',
                      blurb: 'First player out wins every coin staked.',
                    ),
                    ChoiceOption(
                      value: PayoutMode.rankedSplit,
                      label: 'Split by finishing place',
                      blurb: 'The top finishers share the pot.',
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The same settings for everybody else, as a list they can read.
class _GuestSettings extends StatelessWidget {
  const _GuestSettings({required this.room, required this.coins});

  final RoomView room;
  final int coins;

  @override
  Widget build(BuildContext context) {
    final settings = room.settings;
    final lines = <(IconData, String)>[
      (Icons.groups_rounded, '${settings.playerCount} seats'),
      (Icons.timer_rounded, '${settings.timerSeconds} seconds a turn'),
      (
        Icons.repeat_rounded,
        settings.rounds == 1 ? 'One round' : '${settings.rounds} rounds',
      ),
      (
        Icons.shuffle_rounded,
        settings.shuffleSeats
            ? 'Seat order drawn at the start'
            : 'Turn order follows who joined first',
      ),
      if (settings.coinMatch)
        (
          Icons.monetization_on_rounded,
          '${settings.entryFee} coins to enter, '
              '${settings.payout == PayoutMode.rankedSplit ? 'split by place' : 'winner takes the pot'}. '
              'You have $coins.',
        )
      else
        (Icons.card_giftcard_rounded, 'Free match, no coins at stake'),
      if (settings.fillWithBots)
        (
          Icons.smart_toy_rounded,
          'Empty seats become ${settings.botDifficulty.label.toLowerCase()} bots',
        ),
    ];

    return SectionCard(
      title: 'The host has set',
      hint: 'Only the host can change these.',
      child: Column(
        children: [
          for (final (icon, text) in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(icon, size: 24, color: Palette.lime),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                        color: Palette.cream,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ReadyButton extends StatelessWidget {
  const _ReadyButton({
    required this.ready,
    required this.busy,
    required this.onReady,
  });

  final bool ready;
  final bool busy;
  final ValueChanged<bool> onReady;

  @override
  Widget build(BuildContext context) {
    return BigButton(
      label: ready ? 'Ready' : 'I am ready',
      icon: ready ? Icons.check_circle_rounded : Icons.thumb_up_rounded,
      colour: ready ? Palette.lime : Palette.amber,
      minHeight: 74,
      subtitle: ready
          ? 'Waiting for the host to start. Tap to take it back.'
          : 'Let the host know you are set',
      onPressed: busy ? null : () => onReady(!ready),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, this.colour, this.icon);

  final String label;
  final Color colour;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colour, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colour),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              height: 1.2,
              fontWeight: FontWeight.w800,
              color: colour,
            ),
          ),
        ],
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Palette.amberDeep,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.white, width: 2),
      ),
      child: Row(
        children: [
          Icon(icon, size: 24, color: Palette.inkDark),
          const SizedBox(width: 10),
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
        ],
      ),
    );
  }
}
