/// The buttons.
///
/// Big, obviously pressable, and never smaller than a comfortable thumb. The
/// hard bottom edge is the whole point: it makes a button look like a physical
/// thing to press, which matters for players who are not sure what is tappable.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

Color _shade(Color colour, double delta) {
  final hsl = HSLColor.fromColor(colour);
  return hsl.withLightness((hsl.lightness + delta).clamp(0.0, 1.0)).toColor();
}

class BigButton extends StatefulWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.subtitle,
    this.colour = Palette.amber,
    this.foreground = Palette.inkDark,
    this.minHeight = 64,
    this.expand = true,
    this.muted = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final String? subtitle;
  final Color colour;
  final Color foreground;
  final double minHeight;
  final bool expand;

  /// Still tappable, but drawn as not the thing to do right now. Used for Pass
  /// while a legal move exists, so the tap can explain itself instead of dying.
  final bool muted;

  @override
  State<BigButton> createState() => _BigButtonState();
}

class _BigButtonState extends State<BigButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final base = widget.muted || !enabled
        ? _shade(widget.colour, 0.18).withValues(alpha: enabled ? 0.85 : 0.5)
        : widget.colour;
    final edge = _shade(base, -0.16);
    final foreground = enabled
        ? widget.foreground
        : widget.foreground.withValues(alpha: 0.55);

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, size: 26, color: foreground),
              const SizedBox(width: 10),
            ],
            Flexible(
              child: Text(
                widget.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                  color: foreground,
                ),
              ),
            ),
          ],
        ),
        if (widget.subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            widget.subtitle!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.15,
              fontWeight: FontWeight.w600,
              color: foreground.withValues(alpha: 0.8),
            ),
          ),
        ],
      ],
    );

    return Semantics(
      button: true,
      enabled: enabled,
      // The subtitle carries the reason a button is muted, so it belongs in the
      // spoken label rather than being read as a second line of its own.
      label: widget.subtitle == null
          ? widget.label
          : '${widget.label}. ${widget.subtitle}',
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTap: widget.onPressed,
        child: ExcludeSemantics(
          child: Transform.translate(
            offset: Offset(0, _down ? 3 : 0),
            child: Container(
              width: widget.expand ? double.infinity : null,
              constraints: BoxConstraints(minHeight: widget.minHeight),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: base,
                borderRadius: BorderRadius.circular(Sizes.radius),
                boxShadow: [
                  BoxShadow(
                    color: edge,
                    offset: Offset(0, _down ? 1 : 5),
                    blurRadius: 0,
                  ),
                  if (!_down)
                    BoxShadow(
                      color: Palette.inkDark.withValues(alpha: 0.25),
                      offset: const Offset(0, 6),
                      blurRadius: 8,
                    ),
                ],
              ),
              alignment: Alignment.center,
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}

/// Secondary action: smaller, outlined, still a full size tap target.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.colour = Palette.cream,
    this.filled = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color colour;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final foreground = filled ? Palette.inkDark : colour;
    // No Semantics wrapper: TextButton already reports itself as a button with
    // this label and enabled state, and a second node would be read twice.
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, Sizes.tap),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        backgroundColor: filled ? colour : Colors.transparent,
        foregroundColor: foreground,
        side: BorderSide(color: colour.withValues(alpha: 0.7), width: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Sizes.tap / 2),
        ),
      ),
      icon: icon == null ? null : Icon(icon, size: 22, color: foreground),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: foreground,
        ),
      ),
    );
  }
}
