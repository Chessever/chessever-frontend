import 'package:chessever2/chat/botvinnik_provider.dart';
import 'package:chessever2/chat/chat_api.dart';
import 'package:chessever2/chat/chat_screen.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BotvinnikChatButton extends ConsumerWidget {
  const BotvinnikChatButton({
    required this.heroTag,
    this.screenContext,
    this.initialConversationId,
    this.createNewConversationOnOpen = false,
    this.onConversationChanged,
    super.key,
  });

  final String heroTag;
  final ChatScreenContext? screenContext;
  final String? initialConversationId;
  final bool createNewConversationOnOpen;
  final ValueChanged<String>? onConversationChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = Supabase.instance.client.auth.currentUser;
    final enabled = ref.watch(botvinnikEnabledProvider).valueOrNull ?? true;
    if (!ChatApi.buildEnabled || !enabled || user == null || user.isAnonymous) {
      return const SizedBox.shrink();
    }
    return FloatingActionButton.small(
      heroTag: heroTag,
      tooltip: 'Ask Botvinnik',
      onPressed:
          () => ChatScreen.show(
            context,
            screenContext: screenContext,
            initialConversationId: initialConversationId,
            createNewConversationOnOpen: createNewConversationOnOpen,
            onConversationChanged: onConversationChanged,
          ),
      child: const Icon(Icons.auto_awesome_rounded),
    );
  }
}
