/// Play with Friends: make a room, or type the code somebody sent you.
///
/// One level below Home, and the only level. A room is created with sensible
/// settings straight away and the host adjusts them in the lobby, so nobody has to
/// walk through a wizard before their friends can see a code.
///
/// The code box checks itself as you type. A room that cannot be joined says so
/// before the Join button is ever pressed, because "that match already started" is
/// far kinder up front than after a failed tap.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/narrate.dart' as narrate;
import '../models/room.dart';
import '../models/room_code.dart';
import '../services/api.dart';
import '../services/cues.dart';
import '../state/identity.dart';
import '../state/online.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/big_button.dart';
import '../widgets/choice_row.dart';
import '../widgets/screen_header.dart';
import 'room_screen.dart';

/// What the code box currently knows about the room it names.
enum _Look { none, checking, ok, blocked, missing }

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key, this.initialCode, this.initialError});

  /// A code that arrived from somewhere else, such as a tapped invite link. It is
  /// filled in and checked straight away so the player only has to tap Join.
  final String? initialCode;

  /// Why an automatic join did not work, shown once as an error line.
  final String? initialError;

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final TextEditingController _code = TextEditingController();
  Timer? _debounce;

  _Look _look = _Look.none;
  String _lookMessage = '';
  String _lookedUp = '';
  bool _alreadyIn = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = widget.initialError;
    final code = normaliseRoomCode(widget.initialCode);
    if (isValidRoomCode(code)) {
      _code.text = code;
      _look = _Look.checking;
      _lookMessage = 'Checking that code';
      _debounce = Timer(const Duration(milliseconds: 250), () => _lookUp(code));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _code.dispose();
    super.dispose();
  }

  Cues get _cues => ref.read(cuesProvider);

  /* ------------------------------------------------------------- code entry */

  void _onCodeChanged(String raw) {
    // A shared link pasted into the box is treated as the code it contains, which
    // is what somebody who long pressed a message and hit paste actually meant.
    final fromLink = roomCodeFromLink(Uri.tryParse(raw.trim()));
    var code = fromLink ?? normaliseRoomCode(raw);
    if (code.length > roomCodeLength) code = code.substring(0, roomCodeLength);

    if (code != _code.text) {
      _code.value = TextEditingValue(
        text: code,
        selection: TextSelection.collapsed(offset: code.length),
      );
    }

    _debounce?.cancel();
    setState(() {
      _error = null;
      if (code.length < roomCodeLength) {
        _look = _Look.none;
        _lookMessage = '';
        _alreadyIn = false;
        return;
      }
      if (!isValidRoomCode(code)) {
        _look = _Look.blocked;
        _alreadyIn = false;
        final odd = confusedCharacters(code);
        _lookMessage = odd.isEmpty
            ? 'That is not a room code.'
            : 'Codes never use $odd. Look at that character again.';
        return;
      }
      _look = _Look.checking;
      _lookMessage = 'Checking that code';
      _alreadyIn = false;
    });

    if (code.length == roomCodeLength && isValidRoomCode(code)) {
      _debounce = Timer(const Duration(milliseconds: 350), () => _lookUp(code));
    }
  }

  /// Asks the server what is behind the code. Read only, so a wrong code costs
  /// nothing and a right one shows the host's name before you commit.
  Future<void> _lookUp(String code) async {
    if (!mounted) return;
    try {
      final info = await ref.read(apiProvider).lookupRoom(code);
      if (!mounted || normaliseRoomCode(_code.text) != code) return;
      final status = info['status'] as String? ?? 'lobby';
      final locked = info['locked'] == true;
      final filled = (info['playerCount'] as num?)?.toInt() ?? 0;
      final seats = (info['maxPlayers'] as num?)?.toInt() ?? 0;
      final host = info['hostName'] as String? ?? 'Host';
      final alreadyIn = info['alreadyIn'] == true;

      setState(() {
        _lookedUp = code;
        _alreadyIn = alreadyIn;
        if (alreadyIn) {
          _look = _Look.ok;
          _lookMessage = 'You are already in this room. Go back in.';
          return;
        }
        if (info['canJoin'] == true) {
          _look = _Look.ok;
          final free = seats - filled;
          _lookMessage =
              "$host's room, $filled of $seats seats taken, "
              '${free == 1 ? '1 seat' : '$free seats'} free.';
          return;
        }
        _look = _Look.blocked;
        _lookMessage = _whyNot(status, locked, filled, seats);
      });
    } on ApiFailure catch (failure) {
      if (!mounted || normaliseRoomCode(_code.text) != code) return;
      setState(() {
        _lookedUp = code;
        _alreadyIn = false;
        _look = failure.code == 'ROOM_NOT_FOUND' ? _Look.missing : _Look.none;
        // An unreachable server is not a bad code, so the Join button stays live
        // and the server gets the last word.
        _lookMessage = failure.code == 'ROOM_NOT_FOUND'
            ? 'No room has that code. Check it with your friend.'
            : narrate.errorMessage(failure.code, failure.message);
      });
    }
  }

  String _whyNot(String status, bool locked, int filled, int seats) {
    if (status != 'lobby') return 'That match has already started.';
    if (locked) return 'The host has closed this room to new players.';
    if (seats > 0 && filled >= seats) return 'That room is full.';
    return 'That room is not taking players right now.';
  }

  /* ----------------------------------------------------------------- actions */

  Future<void> _create() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Defaults now, host controls in the lobby. Getting a code in front of the
      // player is the urgent part.
      final response = await ref
          .read(apiProvider)
          .createRoom(const RoomSettings().toJson());
      final raw = response['room'];
      if (raw is! Map) {
        throw const ApiFailure('SERVER_ERROR', 'The room came back empty.');
      }
      final room = RoomView.fromJson(Map<String, Object?>.from(raw));
      _cues.tap();
      ref.read(onlineRoomProvider.notifier).enter(room);
      if (!mounted) return;
      setState(() => _busy = false);
      await _openRoom();
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      _cues.denied();
      setState(() {
        _busy = false;
        _error = narrate.errorMessage(failure.code, failure.message);
      });
    }
  }

  Future<void> _join() async {
    if (_busy) return;
    final code = normaliseRoomCode(_code.text);
    if (!isValidRoomCode(code)) {
      _cues.denied();
      setState(() => _error = narrate.errorMessage('BAD_ROOM_CODE'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final joined = await ref.read(onlineRoomProvider.notifier).joinByCode(code);
    if (!mounted) return;
    if (!joined) {
      _cues.denied();
      setState(() {
        _busy = false;
        _error = ref.read(onlineRoomProvider).notice ?? 'Could not join.';
      });
      return;
    }
    _cues.tap();
    setState(() => _busy = false);
    await _openRoom();
  }

  Future<void> _openRoom() async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const RoomScreen()));
  }

  /* -------------------------------------------------------------------- view */

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(identityProvider);
    final online = ref.watch(onlineRoomProvider);
    final code = normaliseRoomCode(_code.text);
    final canTry = identity.isReady && !_busy;
    final joinable =
        canTry &&
        isValidRoomCode(code) &&
        _look != _Look.blocked &&
        _look != _Look.missing &&
        _look != _Look.checking;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: 'Play with Friends',
              subtitle: 'Make a room, or type a code',
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 20),
                children: [
                  if (!identity.isReady)
                    FadeSlideIn(
                      child: _LinkNotice(
                        identity: identity,
                        onRetry: () =>
                            ref.read(identityProvider.notifier).connect(),
                      ),
                    ),
                  if (online.hasRoom)
                    FadeSlideIn(
                      child: _StillInRoom(
                        code: online.room!.roomCode,
                        onOpen: _openRoom,
                        onLeave: () async {
                          await ref.read(onlineRoomProvider.notifier).leave();
                        },
                      ),
                    ),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 60),
                    child: SectionCard(
                      title: 'Make a room',
                      hint:
                          'You get a 6 character code to share. You choose the '
                          'players, the timer and the rounds once everybody is in.',
                      child: BigButton(
                        label: _busy ? 'Making the room' : 'Create room',
                        icon: Icons.add_circle_outline_rounded,
                        colour: Palette.lime,
                        minHeight: 72,
                        onPressed: canTry ? _create : null,
                      ),
                    ),
                  ),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 120),
                    child: SectionCard(
                      title: 'Join a room',
                      hint: 'Type the code your friend sent you.',
                      child: Column(
                        children: [
                          _CodeField(
                            controller: _code,
                            onChanged: _onCodeChanged,
                            onSubmitted: joinable ? _join : null,
                          ),
                          const SizedBox(height: 10),
                          _LookLine(look: _look, message: _lookMessage),
                          const SizedBox(height: 10),
                          BigButton(
                            label: _alreadyIn && _lookedUp == code
                                ? 'Go back in'
                                : 'Join',
                            icon: Icons.login_rounded,
                            colour: Palette.blue,
                            foreground: Palette.white,
                            minHeight: 72,
                            onPressed: joinable ? _join : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_error case final message?)
                    Shake(
                      token: message,
                      child: _ErrorLine(
                        message: message,
                        onDismiss: () => setState(() => _error = null),
                      ),
                    ),
                  const _HowItWorks(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The code box: six wide characters, nothing else allowed in.
class _CodeField extends StatelessWidget {
  const _CodeField({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // Only the label: the field below already reports itself as an edit box,
      // and claiming that here as well would put two of them in the tree.
      label: 'Room code, six characters',
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: (_) => onSubmitted?.call(),
        textInputAction: TextInputAction.go,
        textCapitalization: TextCapitalization.characters,
        textAlign: TextAlign.center,
        autocorrect: false,
        enableSuggestions: false,
        style: const TextStyle(
          fontSize: 34,
          height: 1.2,
          letterSpacing: 8,
          fontWeight: FontWeight.w900,
          color: Palette.ink,
        ),
        decoration: InputDecoration(
          hintText: 'ABC123',
          hintStyle: TextStyle(
            fontSize: 30,
            letterSpacing: 8,
            fontWeight: FontWeight.w900,
            color: Palette.inkSoft.withValues(alpha: 0.5),
          ),
          filled: true,
          fillColor: Palette.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// What the code box found, in one line with an icon that says the same thing as
/// the colour does.
class _LookLine extends StatelessWidget {
  const _LookLine({required this.look, required this.message});

  final _Look look;
  final String message;

  @override
  Widget build(BuildContext context) {
    if (look == _Look.none && message.isEmpty) {
      return const SizedBox(height: 4);
    }
    final (colour, icon) = switch (look) {
      _Look.ok => (Palette.lime, Icons.check_circle_rounded),
      _Look.blocked => (Palette.coral, Icons.block_rounded),
      _Look.missing => (Palette.coral, Icons.search_off_rounded),
      _Look.checking => (Palette.cream, Icons.hourglass_top_rounded),
      _Look.none => (Palette.cream, Icons.info_outline_rounded),
    };

    return PopIn(
      key: ValueKey('$look|$message'),
      child: Row(
        children: [
          Icon(icon, size: 22, color: colour),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 15,
                height: 1.25,
                fontWeight: FontWeight.w700,
                color: colour,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The sign in state, only shown when it is standing in the way.
class _LinkNotice extends StatelessWidget {
  const _LinkNotice({required this.identity, required this.onRetry});

  final Identity identity;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final connecting = identity.status != LinkStatus.offline;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: connecting ? Palette.feltDark : Palette.coralDeep,
        borderRadius: BorderRadius.circular(Sizes.radius),
        border: Border.all(
          color: Palette.cream.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: Row(
        children: [
          if (connecting)
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Palette.cream,
              ),
            )
          else
            const Icon(Icons.wifi_off_rounded, size: 26, color: Palette.white),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              connecting
                  ? 'Connecting to the game server. This can take up to a '
                        'minute the first time.'
                  : identity.message ??
                        'Could not reach the game server. Playing against bots '
                            'still works.',
              style: const TextStyle(
                fontSize: 15,
                height: 1.25,
                fontWeight: FontWeight.w700,
                color: Palette.cream,
              ),
            ),
          ),
          if (!connecting) ...[
            const SizedBox(width: 8),
            PillButton(label: 'Retry', onPressed: onRetry),
          ],
        ],
      ),
    );
  }
}

/// Shown when a room is still being followed, so backing out of a lobby by
/// accident does not look like the room vanished.
class _StillInRoom extends StatelessWidget {
  const _StillInRoom({
    required this.code,
    required this.onOpen,
    required this.onLeave,
  });

  final String code;
  final VoidCallback onOpen;
  final Future<void> Function() onLeave;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'You are still in room $code',
      hint: 'Go back in, or leave it so you can join another one.',
      child: Row(
        children: [
          Expanded(
            child: PillButton(
              label: 'Back to $code',
              icon: Icons.meeting_room_rounded,
              colour: Palette.lime,
              filled: true,
              onPressed: onOpen,
            ),
          ),
          const SizedBox(width: 10),
          PillButton(
            label: 'Leave',
            icon: Icons.logout_rounded,
            colour: Palette.coral,
            onPressed: () => onLeave(),
          ),
        ],
      ),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: Palette.coralDeep,
        borderRadius: BorderRadius.circular(Sizes.radius),
        border: Border.all(color: Palette.white, width: 2),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Palette.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 16,
                height: 1.25,
                fontWeight: FontWeight.w700,
                color: Palette.white,
              ),
            ),
          ),
          HeaderButton(
            icon: Icons.close_rounded,
            label: 'Dismiss',
            tint: Palette.white,
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    const steps = [
      'One person creates the room and reads out the code.',
      'Everybody else types that code in and taps Join.',
      'The host picks the settings, then taps Start.',
    ];
    return FadeSlideIn(
      delay: const Duration(milliseconds: 180),
      child: SectionCard(
        title: 'How this works',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < steps.length; i += 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Palette.amber,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Palette.inkDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        steps[i],
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          color: Palette.cream.withValues(alpha: 0.9),
                        ),
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
