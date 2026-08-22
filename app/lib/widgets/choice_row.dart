/// Setup controls shared by solo setup and, later, the online room settings.
///
/// Every control is a full size tap target and every selected state is drawn
/// with a tick and a border as well as a colour.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

/// A titled panel, so a setup screen reads as a short list of decisions.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.hint,
  });

  final String title;
  final String? hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: Palette.feltDark,
        borderRadius: BorderRadius.circular(Sizes.radius),
        border: Border.all(
          color: Palette.cream.withValues(alpha: 0.18),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Palette.cream,
            ),
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                hint!,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Palette.cream.withValues(alpha: 0.75),
                ),
              ),
            ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class ChoiceOption<T> {
  const ChoiceOption({required this.value, required this.label, this.blurb});

  final T value;
  final String label;
  final String? blurb;
}

/// A row of choices that wraps. One is always selected.
class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.stacked = false,
  });

  final List<ChoiceOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  /// One option per line, for choices that need their explanation shown.
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    if (stacked) {
      return Column(
        children: [
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _Choice<T>(
                option: option,
                selected: option.value == value,
                onTap: () => onChanged(option.value),
                expand: true,
              ),
            ),
        ],
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          _Choice<T>(
            option: option,
            selected: option.value == value,
            onTap: () => onChanged(option.value),
            expand: false,
          ),
      ],
    );
  }
}

class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.option,
    required this.selected,
    required this.onTap,
    required this.expand,
  });

  final ChoiceOption<T> option;
  final bool selected;
  final VoidCallback onTap;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      // The blurb explains what the choice means, so it is part of the one
      // sentence a reader says rather than a second node after it.
      label: option.blurb == null
          ? option.label
          : '${option.label}. ${option.blurb}',
      child: GestureDetector(
        onTap: onTap,
        child: ExcludeSemantics(
          child: Container(
            width: expand ? double.infinity : null,
            constraints: const BoxConstraints(
              minHeight: Sizes.tap,
              minWidth: 64,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? Palette.amber : Palette.felt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? Palette.white
                    : Palette.cream.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              children: [
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 20,
                  color: selected ? Palette.inkDark : Palette.cream,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        option.label,
                        style: TextStyle(
                          fontSize: 17,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                          color: selected ? Palette.inkDark : Palette.cream,
                        ),
                      ),
                      if (option.blurb != null)
                        Text(
                          option.blurb!,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.2,
                            fontWeight: FontWeight.w500,
                            color: selected
                                ? Palette.inkDark.withValues(alpha: 0.8)
                                : Palette.cream.withValues(alpha: 0.75),
                          ),
                        ),
                    ],
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

/// An on or off setting. The whole row is the tap target, and the state is drawn
/// with a word and an icon as well as the switch, because a switch on its own is
/// not obvious to everybody.
class ToggleRow extends StatelessWidget {
  const ToggleRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.icon,
    this.hint,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final IconData? icon;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: () => onChanged(!value),
          child: Container(
            constraints: const BoxConstraints(minHeight: Sizes.tap),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: value ? Palette.felt : Palette.feltDark,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: value
                    ? Palette.lime.withValues(alpha: 0.8)
                    : Palette.cream.withValues(alpha: 0.25),
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon ?? (value ? Icons.check_rounded : Icons.close_rounded),
                  size: 26,
                  color: value ? Palette.lime : Palette.cream,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 17,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                          color: Palette.cream,
                        ),
                      ),
                      Text(
                        hint ?? (value ? 'On' : 'Off'),
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          color: Palette.cream.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: value,
                  onChanged: onChanged,
                  activeThumbColor: Palette.inkDark,
                  activeTrackColor: Palette.lime,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Minus, a big number, plus. Clearer than a slider for a small count.
class CountStepper extends StatelessWidget {
  const CountStepper({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.unit,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  /// Printed after the number, already matched to the value by the caller.
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StepButton(
          icon: Icons.remove_rounded,
          label: 'One fewer',
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        Expanded(
          child: Semantics(
            label: '$value $unit',
            child: ExcludeSemantics(
              child: Column(
                children: [
                  Text(
                    '$value',
                    style: const TextStyle(
                      fontSize: 34,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                      color: Palette.lime,
                    ),
                  ),
                  Text(
                    unit,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Palette.cream,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        _StepButton(
          icon: Icons.add_rounded,
          label: 'One more',
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 64,
          height: Sizes.tap,
          decoration: BoxDecoration(
            color: enabled ? Palette.felt : Palette.feltDark,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Palette.cream.withValues(alpha: enabled ? 0.5 : 0.18),
              width: 2,
            ),
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 30,
            color: Palette.cream.withValues(alpha: enabled ? 1 : 0.35),
          ),
        ),
      ),
    );
  }
}
