import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// Shared presentation for assistant answers and frontend-only editorial notices.
/// This widget carries no conversation identity or persistence behavior.
class ChatAssistantBubble extends StatelessWidget {
  const ChatAssistantBubble({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(5),
          bottomRight: Radius.circular(18),
        ),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BOTVINNIK',
            style: theme.textTheme.labelSmall?.copyWith(
              color: context.colors.accentText,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 7),
          child,
        ],
      ),
    );
  }
}
