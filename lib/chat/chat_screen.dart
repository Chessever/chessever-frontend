import 'dart:async';

import 'package:chessever2/chat/chat_api.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  static Future<void> show(BuildContext context) async {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 700) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const ChatScreen()));
      return;
    }
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close ChessEver Chat',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: SafeArea(
            child: Material(
              elevation: 20,
              child: SizedBox(
                width: 520,
                height: double.infinity,
                child: const ChatScreen(),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        );
      },
    );
  }

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final ChatApi _api = ChatApi();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  List<ChatConversation> _conversations = const [];
  List<ChatMessage> _messages = const [];
  ChatConversation? _selected;
  String? _error;
  bool _loading = true;
  bool _sending = false;
  int? _remaining;
  int? _limit;

  Locale get _locale => Localizations.localeOf(context);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _api.close();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var conversations = await _api.conversations();
      if (conversations.isEmpty) {
        conversations = [
          await _api.createConversation(locale: _locale.toLanguageTag()),
        ];
      }
      final selected = conversations.first;
      final messages = await _api.messages(selected.id);
      if (!mounted) return;
      setState(() {
        _conversations = conversations;
        _selected = selected;
        _messages = messages;
      });
    } on ChatApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _newConversation() async {
    try {
      final conversation = await _api.createConversation(
        locale: _locale.toLanguageTag(),
      );
      if (!mounted) return;
      setState(() {
        _conversations = [conversation, ..._conversations];
        _selected = conversation;
        _messages = const [];
        _error = null;
      });
      Navigator.of(context).maybePop();
    } on ChatApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _select(ChatConversation conversation) async {
    if (_sending) return;
    try {
      final messages = await _api.messages(conversation.id);
      if (!mounted) return;
      setState(() {
        _selected = conversation;
        _messages = messages;
        _error = null;
      });
      Navigator.of(context).maybePop();
    } on ChatApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _delete(ChatConversation conversation) async {
    if (_sending) return;
    try {
      await _api.deleteConversation(conversation.id);
      if (!mounted) return;
      final remaining =
          _conversations.where((item) => item.id != conversation.id).toList();
      setState(() => _conversations = remaining);
      if (_selected?.id == conversation.id) {
        if (remaining.isEmpty) {
          await _newConversation();
        } else {
          await _select(remaining.first);
        }
      }
    } on ChatApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _send() async {
    final selected = _selected;
    final content = _controller.text.trim();
    if (selected == null || content.isEmpty || _sending) return;
    _controller.clear();
    final localUser = ChatMessage(
      id: 'local-user-${DateTime.now().microsecondsSinceEpoch}',
      role: 'user',
      content: content,
    );
    final localAssistant = ChatMessage(
      id: 'local-assistant-${DateTime.now().microsecondsSinceEpoch}',
      role: 'assistant',
      content: '',
    );
    setState(() {
      _sending = true;
      _error = null;
      _messages = [..._messages, localUser, localAssistant];
    });
    _scrollToEnd();
    try {
      await for (final event in _api.send(
        conversationId: selected.id,
        content: content,
        locale: _locale.toLanguageTag(),
        timezone: DateTime.now().timeZoneName,
      )) {
        if (!mounted) return;
        final messages = [..._messages];
        final assistant = messages.last;
        switch (event.type) {
          case 'start':
          case 'done':
            _readQuota(event.data);
            break;
          case 'delta':
            messages[messages.length - 1] = assistant.copyWith(
              content:
                  '${assistant.content}${event.data['text'] as String? ?? ''}',
            );
            break;
          case 'references':
            final raw = event.data['references'] as List<dynamic>? ?? const [];
            messages[messages.length - 1] = assistant.copyWith(
              references:
                  raw
                      .whereType<Map<String, dynamic>>()
                      .map(ChatReference.fromJson)
                      .toList(),
            );
            break;
          case 'error':
            throw ChatApiException(
              event.data['message'] as String? ?? 'Unable to answer right now',
            );
          default:
            break;
        }
        setState(() => _messages = messages);
        _scrollToEnd();
      }
      final refreshed = await _api.messages(selected.id);
      if (mounted) setState(() => _messages = refreshed);
    } on ChatApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        if (_messages.isNotEmpty && _messages.last.content.isEmpty) {
          _messages = _messages.sublist(0, _messages.length - 1);
        }
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _readQuota(Map<String, dynamic> data) {
    final quota = data['quota'] as Map<String, dynamic>?;
    if (quota == null) return;
    _remaining = quota['remaining'] as int?;
    _limit = quota['limit'] as int?;
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      unawaited(
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  void _openReference(ChatReference reference) {
    if (reference.id.isEmpty ||
        (reference.type != 'event' && reference.type != 'tournament')) {
      return;
    }

    final broadcast = GroupBroadcast(
      id: reference.id,
      createdAt: DateTime.now(),
      name: reference.label,
      search: [reference.id, reference.label],
    );
    ref.read(selectedBroadcastModelProvider.notifier).state = broadcast;
    ref.read(selectedTourModeProvider.notifier).state =
        TournamentDetailScreenMode.games;
    Navigator.of(context).pushNamed('/tournament_detail_screen');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _ConversationDrawer(
        conversations: _conversations,
        selectedId: _selected?.id,
        onNew: _newConversation,
        onSelect: _select,
        onDelete: _delete,
      ),
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Chats',
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Text(_selected?.title ?? 'ChessEver Chat'),
        actions: [
          if (_remaining != null && _limit != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text('$_remaining / $_limit left'),
              ),
            ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _error = null),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          Expanded(
            child:
                _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _messages.isEmpty
                    ? const _EmptyChat()
                    : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder:
                          (context, index) => _MessageBubble(
                            message: _messages[index],
                            isStreaming:
                                _sending && index == _messages.length - 1,
                            onReferencePressed: _openReference,
                          ),
                    ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 2000,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'Ask about tournaments, rounds or games…',
                        counterText: '',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Send',
                    onPressed: _sending ? null : _send,
                    icon:
                        _sending
                            ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              size: 44,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Ask ChessEver',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Try “What games are live?” or ask the same question in Hindi.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isStreaming,
    required this.onReferencePressed,
  });

  final ChatMessage message;
  final bool isStreaming;
  final ValueChanged<ChatReference> onReferencePressed;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color:
              isUser
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.content.isEmpty && isStreaming)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              SelectableText(message.content),
            if (message.references.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children:
                    message.references
                        .map(
                          (reference) => ActionChip(
                            avatar: Icon(
                              reference.type == 'game'
                                  ? Icons.sports_esports_rounded
                                  : Icons.emoji_events_rounded,
                              size: 16,
                            ),
                            label: Text(reference.label),
                            onPressed: () => onReferencePressed(reference),
                          ),
                        )
                        .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConversationDrawer extends StatelessWidget {
  const _ConversationDrawer({
    required this.conversations,
    required this.selectedId,
    required this.onNew,
    required this.onSelect,
    required this.onDelete,
  });

  final List<ChatConversation> conversations;
  final String? selectedId;
  final Future<void> Function() onNew;
  final Future<void> Function(ChatConversation) onSelect;
  final Future<void> Function(ChatConversation) onDelete;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.add_comment_rounded),
              title: const Text('New chat'),
              onTap: onNew,
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: conversations.length,
                itemBuilder: (context, index) {
                  final conversation = conversations[index];
                  return ListTile(
                    selected: conversation.id == selectedId,
                    title: Text(
                      conversation.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => onSelect(conversation),
                    trailing: IconButton(
                      tooltip: 'Delete chat',
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => onDelete(conversation),
                    ),
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
