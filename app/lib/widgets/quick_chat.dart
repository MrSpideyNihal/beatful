/// Quick chat feature for Beatful multiplayer rooms.
///
/// Predefined short messages and reactions that players can tap to communicate
/// without typing. Matches the server's CHAT_MESSAGES indices.
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
  required void Function(int index) onSelect,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _QuickChatPanel(
      onSelect: (index) {
        Navigator.of(sheetContext).pop();
        onSelect(index);
      },
    ),
  );
}

class _QuickChatPanel extends StatelessWidget {
  const _QuickChatPanel({required this.onSelect});

  final void Function(int index) onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
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
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Palette.inkSoft,
              borderRadius: BorderRadius.circular(2),
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
                    'Quick Chat',
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
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 3.2,
            ),
            itemCount: quickChatMessages.length,
            itemBuilder: (context, index) {
              final text = quickChatMessages[index];
              return Material(
                color: Palette.ink,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => onSelect(index),
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
                        fontSize: 15,
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
    );
  }
}
