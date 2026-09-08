/// Welcome dialog shown to first-time players to set their display name and avatar.
///
/// Ensures players are never generically named "You" in online multiplayer.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/avatar.dart';
import '../state/identity.dart';
import '../state/profile.dart';
import '../theme.dart';
import 'avatar_circle.dart';
import 'big_button.dart';

Future<void> showWelcomeNameDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const WelcomeNameDialog(),
  );
}

class WelcomeNameDialog extends ConsumerStatefulWidget {
  const WelcomeNameDialog({super.key});

  @override
  ConsumerState<WelcomeNameDialog> createState() => _WelcomeNameDialogState();
}

class _WelcomeNameDialogState extends ConsumerState<WelcomeNameDialog> {
  late final TextEditingController _nameController;
  late int _selectedAvatar;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(profileProvider);
    final initialName = profile.name.trim().toLowerCase() == 'you' ? '' : profile.name;
    _nameController = TextEditingController(text: initialName);
    _selectedAvatar = profile.avatar;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final raw = _nameController.text.trim();
    final fallback = 'Player ${100 + Random().nextInt(900)}';
    final chosenName = cleanName(raw.isEmpty ? fallback : raw, fallback: fallback);

    await ref.read(profileProvider.notifier).setName(chosenName);
    await ref.read(profileProvider.notifier).setAvatar(_selectedAvatar);
    await ref.read(profileProvider.notifier).setHasCustomName(true);

    if (mounted) {
      unawaited(ref.read(identityProvider.notifier).pushName(chosenName));
      unawaited(ref.read(identityProvider.notifier).pushAvatar(_selectedAvatar));
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          decoration: BoxDecoration(
            color: Palette.feltDark,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Palette.amber, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Palette.ink,
                    shape: BoxShape.circle,
                    border: Border.all(color: Palette.amber, width: 2),
                  ),
                  child: const Icon(
                    Icons.style_rounded,
                    color: Palette.amber,
                    size: 30,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Welcome to Beatful!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Palette.cream,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Choose your player name and avatar so friends know who you are in game.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Palette.mist,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 18),
              // Avatar selector row
              const Text(
                'Pick an Avatar',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Palette.amber,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: avatarCount(),
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final isSelected = index == _selectedAvatar;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedAvatar = index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Palette.amber : Colors.transparent,
                            width: 2.5,
                          ),
                        ),
                        child: AvatarCircle(avatar: index, size: 44),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
              // Name text field
              const Text(
                'Your Name',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Palette.amber,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _nameController,
                maxLength: maxNameLength,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Palette.cream,
                ),
                cursorColor: Palette.amber,
                decoration: InputDecoration(
                  hintText: 'e.g. Alex, Tiger, Ace...',
                  hintStyle: const TextStyle(color: Palette.inkSoft),
                  filled: true,
                  fillColor: Palette.ink,
                  counterStyle: const TextStyle(color: Palette.mist),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Palette.feltLight.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Palette.amber, width: 2),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              BigButton(
                label: "Let's Play",
                icon: Icons.check_circle_rounded,
                colour: Palette.amber,
                foreground: Palette.inkDark,
                minHeight: 52,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
