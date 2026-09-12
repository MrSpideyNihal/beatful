/// Quick chat and custom message feature for Beatful multiplayer rooms.
///
/// Allows players to send either custom typed messages or quick emoji reactions.
library;

import 'package:flutter/material.dart';

import '../theme.dart';

const List<String> quickChatMessages = [
  '👋 Hello!',
  '👍 Good move!',
  '😄 Well played!',
  '⏳ Hurry up!',
  '😎 Easy!',
  '😱 Oh no!',
  '🎉 GG!',
  '👏 Nice one!',
];

Future<void> showQuickChatSheet(
  BuildContext context, {
  void Function(int index)? onSelect,
  void Function(String text)? onSendCustom,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _QuickChatPanel(
      onSelect: onSelect,
      onSendCustom: onSendCustom,
    ),
  );
}

class _QuickChatPanel extends StatefulWidget {
  const _QuickChatPanel({
    this.onSelect,
    this.onSendCustom,
  });

  final void Function(int index)? onSelect;
  final void Function(String text)? onSendCustom;

  @override
  State<_QuickChatPanel> createState() => _QuickChatPanelState();
}

class _QuickChatPanelState extends State<_QuickChatPanel> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop();
    widget.onSendCustom?.call(text);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Palette.inkDark,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: Palette.amber, width: 2),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Palette.inkSoft,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.chat_bubble_rounded, color: Palette.amber, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Table Chat',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Palette.cream,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Palette.cream),
                  onPressed: () => Navigator.of(context).pop(),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    maxLength: 120,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submit(),
                    style: const TextStyle(color: Palette.cream, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Type a custom message...',
                      hintStyle: TextStyle(
                        color: Palette.cream.withValues(alpha: 0.4),
                        fontSize: 14,
                      ),
                      counterText: '',
                      filled: true,
                      fillColor: Palette.ink,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: Palette.feltLight.withValues(alpha: 0.4),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: Palette.feltLight.withValues(alpha: 0.4),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: Palette.amber,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: Palette.amber,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    onTap: _submit,
                    borderRadius: BorderRadius.circular(14),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(
                        Icons.send_rounded,
                        color: Palette.inkDark,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'QUICK REACTIONS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Palette.amber,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 3.4,
              ),
              itemCount: quickChatMessages.length,
              itemBuilder: (context, index) {
                final text = quickChatMessages[index];
                return Material(
                  color: Palette.ink,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onSelect?.call(index);
                    },
                    borderRadius: BorderRadius.circular(12),
                    splashColor: Palette.amber.withValues(alpha: 0.3),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Palette.feltLight.withValues(alpha: 0.3),
                        ),
                      ),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        text,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Palette.cream,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
