import 'package:chessever2/chat/botvinnik_icon.dart';
import 'package:chessever2/chat/botvinnik_provider.dart';
import 'package:chessever2/chat/chat_api.dart';
import 'package:chessever2/chat/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class BotvinnikChatButton extends ConsumerWidget {
  const BotvinnikChatButton({
    required this.heroTag,
    this.screenContext,
    this.iconOnly = false,
    super.key,
  });

  final String heroTag;
  final ChatScreenContext? screenContext;
  final bool iconOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(botvinnikEnabledProvider).valueOrNull ?? true;
    if (!ChatApi.buildEnabled || !enabled) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 48,
      child: FloatingActionButton(
        heroTag: heroTag,
        tooltip: 'Ask Botvinnik',
        backgroundColor:
            iconOnly ? Colors.transparent : Colors.black.withValues(alpha: 0.5),
        elevation: iconOnly ? 0 : null,
        focusElevation: iconOnly ? 0 : null,
        hoverElevation: iconOnly ? 0 : null,
        highlightElevation: iconOnly ? 0 : null,
        onPressed:
            () => ChatScreen.show(
              context,
              screenContext: screenContext,
              createNewConversationOnOpen: true,
            ),
        child: BotvinnikIcon(
          size: iconOnly ? 48 : 38,
          color: colorScheme.primary,
        ),
      ),
    );
  }
}
