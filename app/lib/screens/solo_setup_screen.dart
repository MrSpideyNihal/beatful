/// Solo setup: opponents, difficulty, turn timer, rounds, then start.
///
/// One level below Home, and every choice already has a value, so a player who
/// does not care can hit Start straight away.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/bots.dart';
import '../state/solo.dart';
import '../state/solo_config.dart';
import '../widgets/big_button.dart';
import '../widgets/choice_row.dart';
import '../widgets/screen_header.dart';
import 'game_screen.dart';

class SoloSetupScreen extends ConsumerWidget {
  const SoloSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(soloConfigProvider);
    final setup = ref.read(soloConfigProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: 'Play vs Bots',
              subtitle: '${config.seatCount} players at the table',
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                children: [
                  SectionCard(
                    title: 'Opponents',
                    hint: 'Cards are shared out evenly between everyone.',
                    child: CountStepper(
                      value: config.botCount,
                      min: minBots,
                      max: maxBots,
                      unit: config.botCount == 1 ? 'bot' : 'bots',
                      onChanged: setup.setBotCount,
                    ),
                  ),
                  SectionCard(
                    title: 'How well they play',
                    child: ChoiceRow<BotDifficulty>(
                      stacked: true,
                      value: config.difficulty,
                      onChanged: setup.setDifficulty,
                      options: [
                        for (final level in BotDifficulty.values)
                          ChoiceOption(
                            value: level,
                            label: level.label,
                            blurb: level.blurb,
                          ),
                      ],
                    ),
                  ),
                  SectionCard(
                    title: 'Time per turn',
                    hint: 'Run out of time and your turn is played for you.',
                    child: ChoiceRow<int>(
                      value: config.timerSeconds,
                      onChanged: setup.setTimerSeconds,
                      options: [
                        for (final seconds in timerChoices)
                          ChoiceOption(value: seconds, label: '$seconds sec'),
                      ],
                    ),
                  ),
                  SectionCard(
                    title: 'Rounds',
                    hint:
                        'More rounds means the best player over all of them wins.',
                    child: ChoiceRow<int>(
                      value: config.rounds,
                      onChanged: setup.setRounds,
                      options: [
                        for (final rounds in roundChoices)
                          ChoiceOption(
                            value: rounds,
                            label: rounds == 1 ? '1 round' : '$rounds rounds',
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
              child: BigButton(
                label: 'Start',
                icon: Icons.play_arrow_rounded,
                minHeight: 72,
                onPressed: () {
                  // Drop any match left over from a previous visit so Start always
                  // deals a new one with the settings above.
                  ref.invalidate(soloGameProvider);
                  Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const GameScreen()),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
