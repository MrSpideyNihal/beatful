/// Settings: name, avatar, sound, music, haptics.
///
/// Every change applies at once and is written to storage, so there is no save
/// button to forget and nothing to lose by leaving the screen.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/avatar.dart';
import '../services/audio.dart';
import '../state/identity.dart';
import '../state/profile.dart';
import '../state/settings.dart';
import '../theme.dart';
import '../widgets/anim.dart';
import '../widgets/avatar_circle.dart';
import '../widgets/big_button.dart';
import '../widgets/choice_row.dart';
import '../widgets/screen_header.dart';
import 'terms_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: ref.read(profileProvider).name);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _commitName() {
    final cleaned = cleanName(_name.text);
    final was = ref.read(profileProvider).name;
    ref.read(profileProvider.notifier).setName(cleaned);
    if (_name.text != cleaned) _name.text = cleaned;
    // The local name is what the device shows straight away. Sending it up is
    // what makes the other players in a room see it, and a failure there is not
    // worth a message: the next launch pushes it again.
    if (cleaned != was) {
      unawaited(ref.read(identityProvider.notifier).pushName(cleaned));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final settingsControl = ref.read(settingsProvider.notifier);
    final profile = ref.watch(profileProvider);

    // The name field is only filled once, so a load that lands after this screen
    // opened still shows the stored name.
    if (profile.loaded && _name.text.isEmpty && profile.name.isNotEmpty) {
      _name.text = profile.name;
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: 'Settings',
              subtitle: 'Saved as you change them',
              onBack: () {
                _commitName();
                Navigator.of(context).pop();
              },
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
                children: [
                  FadeSlideIn(
                    child: SectionCard(
                      title: 'Your name',
                      hint:
                          'What other players see, up to $maxNameLength letters',
                      child: TextField(
                        controller: _name,
                        maxLength: maxNameLength,
                        textInputAction: TextInputAction.done,
                        textCapitalization: TextCapitalization.words,
                        onSubmitted: (_) => _commitName(),
                        onTapOutside: (_) {
                          FocusManager.instance.primaryFocus?.unfocus();
                          _commitName();
                        },
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Palette.ink,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Palette.white,
                          counterStyle: TextStyle(
                            color: Palette.cream.withValues(alpha: 0.8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 50),
                    child: SectionCard(
                      title: 'Your picture',
                      hint: avatarStyle(profile.avatar).name,
                      child: _AvatarPicker(
                        selected: profile.avatar,
                        onPick: (id) {
                          HapticFeedback.selectionClick();
                          ref.read(profileProvider.notifier).setAvatar(id);
                          unawaited(
                            ref.read(identityProvider.notifier).pushAvatar(id),
                          );
                        },
                      ),
                    ),
                  ),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 100),
                    child: SectionCard(
                      title: 'Sound and feel',
                      child: Column(
                        children: [
                          ToggleRow(
                            label: 'Sound effects',
                            icon: Icons.volume_up_rounded,
                            value: settings.sound,
                            onChanged: settingsControl.setSound,
                          ),
                          ToggleRow(
                            label: 'Background music',
                            icon: Icons.music_note_rounded,
                            value: settings.music,
                            onChanged: settingsControl.setMusic,
                          ),
                          _VolumeRow(
                            value: settings.musicVolume,
                            enabled: settings.music,
                            onChanged: settingsControl.setMusicVolume,
                          ),
                          ToggleRow(
                            label: 'Vibration',
                            icon: Icons.vibration_rounded,
                            hint: settings.haptics
                                ? 'On, a small buzz on your turn'
                                : 'Off',
                            value: settings.haptics,
                            onChanged: (value) {
                              settingsControl.setHaptics(value);
                              if (value) HapticFeedback.mediumImpact();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 150),
                    child: SectionCard(
                      title: 'About',
                      hint: 'Beatful, the sevens card game',
                      child: PillButton(
                        label: 'Terms',
                        icon: Icons.description_rounded,
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => const TermsScreen(),
                          ),
                        ),
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

class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({required this.selected, required this.onPick});

  final int selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var id = 0; id < avatarCount(); id += 1)
          Semantics(
            button: true,
            selected: id == selected,
            label: avatarStyle(id).name,
            child: GestureDetector(
              onTap: () => onPick(id),
              child: AnimatedContainer(
                duration: Anim.swap,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: id == selected ? Palette.lime : Colors.transparent,
                    width: 3,
                  ),
                ),
                child: Stack(
                  children: [
                    AvatarCircle(avatar: id, size: 52),
                    if (id == selected)
                      const Positioned(
                        right: -2,
                        bottom: -2,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Palette.lime,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: Palette.inkDark,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _VolumeRow extends ConsumerWidget {
  const _VolumeRow({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final percent = (value * 100).round();
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 4),
        child: Row(
          children: [
            const Icon(Icons.volume_down_rounded, color: Palette.cream),
            Expanded(
              child: Semantics(
                label: 'Music volume $percent percent',
                child: ExcludeSemantics(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 8,
                      activeTrackColor: Palette.lime,
                      inactiveTrackColor: Palette.feltDark,
                      thumbColor: Palette.cream,
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 26,
                      ),
                    ),
                    child: Slider(
                      value: value,
                      onChanged: enabled ? onChanged : null,
                      onChangeEnd: enabled
                          ? (level) =>
                                ref.read(audioProvider).previewMusic(level)
                          : null,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 46,
              child: Text(
                '$percent',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Palette.cream,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
