import 'dart:async';

import 'package:chessever2/chat/chat_api.dart';
import 'package:chessever2/chat/botvinnik_provider.dart';
import 'package:chessever2/services/deep_link_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    this.screenContext,
    this.initialConversationId,
    this.createNewConversationOnOpen = false,
    this.onConversationChanged,
    super.key,
  });

  final ChatScreenContext? screenContext;
  final String? initialConversationId;
  final bool createNewConversationOnOpen;
  final ValueChanged<String>? onConversationChanged;

  static Future<void> show(
    BuildContext context, {
    ChatScreenContext? screenContext,
    String? initialConversationId,
    bool createNewConversationOnOpen = false,
    ValueChanged<String>? onConversationChanged,
  }) async {
    Widget buildChatScreen() => ChatScreen(
      screenContext: screenContext,
      initialConversationId: initialConversationId,
      createNewConversationOnOpen: createNewConversationOnOpen,
      onConversationChanged: onConversationChanged,
    );

    final width = MediaQuery.sizeOf(context).width;
    if (width < 700) {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => buildChatScreen()));
      return;
    }
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close Botvinnik',
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
                child: buildChatScreen(),
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
  final Set<String> _feedbackPending = {};
  String? _appVersion;
  String? _buildNumber;

  Locale get _locale => Localizations.localeOf(context);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(_loadClientMetadata());
  }

  Future<void> _loadClientMetadata() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _appVersion = packageInfo.version;
      _buildNumber = packageInfo.buildNumber;
    } catch (_) {
      // Platform and form factor are still sent when version lookup is absent.
    }
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
      final conversations = await _api.conversations();
      late final ChatConversation selected;
      late final List<ChatMessage> messages;
      if (widget.createNewConversationOnOpen) {
        selected = ChatConversation.draft(locale: _locale.toLanguageTag());
        messages = const [];
      } else {
        if (conversations.isEmpty) {
          selected = ChatConversation.draft(locale: _locale.toLanguageTag());
          messages = const [];
        } else {
          selected = chatConversationForOpen(
            conversations,
            widget.initialConversationId,
          );
          messages = await _api.messages(selected.id);
        }
      }
      if (!mounted) return;
      setState(() {
        _conversations = conversations;
        _selected = selected;
        _messages = messages;
      });
      if (!selected.isDraft) {
        widget.onConversationChanged?.call(selected.id);
      }
    } on ChatApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _newConversation() async {
    final conversation = ChatConversation.draft(
      locale: _locale.toLanguageTag(),
    );
    setState(() {
      _selected = conversation;
      _messages = const [];
      _error = null;
    });
    Navigator.of(context).maybePop();
  }

  Future<void> _select(ChatConversation conversation) async {
    if (_sending) return;
    try {
      final messages =
          conversation.isDraft
              ? const <ChatMessage>[]
              : await _api.messages(conversation.id);
      if (!mounted) return;
      setState(() {
        _selected = conversation;
        _messages = messages;
        _error = null;
      });
      if (!conversation.isDraft) {
        widget.onConversationChanged?.call(conversation.id);
      }
      Navigator.of(context).maybePop();
    } on ChatApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _delete(ChatConversation conversation) async {
    if (_sending) return;
    try {
      if (!conversation.isDraft) {
        await _api.deleteConversation(conversation.id);
      }
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
    var selected = _selected;
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
      if (selected.isDraft) {
        final draftId = selected.id;
        final persisted = await _api.createConversation(
          locale: _locale.toLanguageTag(),
          title: chatTitleFromQuestion(content),
        );
        selected = persisted;
        if (!mounted) return;
        setState(() {
          _conversations = [
            persisted,
            ..._conversations.where(
              (item) => item.id != draftId && item.id != persisted.id,
            ),
          ];
          _selected = persisted;
        });
        widget.onConversationChanged?.call(persisted.id);
      }
      final viewport = MediaQuery.sizeOf(context);
      await for (final event in _api.send(
        conversationId: selected.id,
        content: content,
        locale: _locale.toLanguageTag(),
        timezone: DateTime.now().timeZoneName,
        clientContext: ChatClientContext.current(
          viewportWidth: viewport.width,
          shortestSide: viewport.shortestSide,
          appVersion: _appVersion,
          buildNumber: _buildNumber,
        ),
        screenContext: widget.screenContext,
      )) {
        if (!mounted) return;
        final messages = [..._messages];
        final assistant = messages.last;
        switch (event.type) {
          case 'start':
            _useQuestionAsTitle(selected.id, content);
            _readQuota(event.data);
            break;
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

  Future<void> _setFeedback(ChatMessage message, String feedback) async {
    final selected = _selected;
    if (selected == null ||
        message.id.startsWith('local-') ||
        _feedbackPending.contains(message.id)) {
      return;
    }

    final nextFeedback = message.feedback == feedback ? null : feedback;
    final previousFeedback = message.feedback;
    setState(() {
      _feedbackPending.add(message.id);
      _messages =
          _messages
              .map(
                (item) =>
                    item.id == message.id
                        ? item.withFeedback(nextFeedback)
                        : item,
              )
              .toList();
    });

    try {
      final updated = await _api.setMessageFeedback(
        conversationId: selected.id,
        messageId: message.id,
        feedback: nextFeedback,
      );
      if (!mounted || _selected?.id != selected.id) return;
      setState(() {
        _messages =
            _messages
                .map((item) => item.id == updated.id ? updated : item)
                .toList();
      });
    } on ChatApiException catch (error) {
      if (!mounted || _selected?.id != selected.id) return;
      setState(() {
        _error = error.message;
        _messages =
            _messages
                .map(
                  (item) =>
                      item.id == message.id
                          ? item.withFeedback(previousFeedback)
                          : item,
                )
                .toList();
      });
    } finally {
      if (mounted) setState(() => _feedbackPending.remove(message.id));
    }
  }

  void _sendSuggestion(String suggestion) {
    _controller.text = suggestion;
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    unawaited(_send());
  }

  void _readQuota(Map<String, dynamic> data) {
    final quota = data['quota'] as Map<String, dynamic>?;
    if (quota == null) return;
    ref
        .read(botvinnikQuotaProvider.notifier)
        .setQuota(ChatQuotaStatus.fromJson(quota));
  }

  void _useQuestionAsTitle(String conversationId, String question) {
    final index = _conversations.indexWhere(
      (conversation) => conversation.id == conversationId,
    );
    if (index == -1 || _conversations[index].title != 'New chat') return;

    final renamed = _conversations[index].copyWith(
      title: chatTitleFromQuestion(question),
    );
    final conversations = [..._conversations];
    conversations[index] = renamed;
    _conversations = conversations;
    if (_selected?.id == conversationId) _selected = renamed;
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
    if (reference.id.isEmpty) return;
    if (reference.type == 'game') {
      DeepLinkService.instance.openGameFromApp(reference.id);
      return;
    }
    if (reference.type == 'round') {
      DeepLinkService.instance.openEventFromApp(
        roundId: reference.id,
        tourId: reference.tourId,
      );
      return;
    }
    if (reference.type == 'event') {
      DeepLinkService.instance.openEventFromApp(eventId: reference.id);
      return;
    }
    if (reference.type == 'tournament') {
      DeepLinkService.instance.openEventFromApp(tourId: reference.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final quota = ref.watch(botvinnikQuotaProvider);
    return Scaffold(
      key: _scaffoldKey,
      drawer: _ConversationDrawer(
        conversations: _conversations,
        selectedId: _selected?.id,
        onNew: _newConversation,
        onSelect: _select,
        onDelete: _delete,
        quota: quota,
      ),
      appBar: AppBar(
        toolbarHeight: 72,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        leading: IconButton(
          tooltip: 'Chats',
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        titleSpacing: 4,
        title: const Row(
          children: [
            _BotAvatar(size: 40),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Botvinnik'),
                  SizedBox(height: 1),
                  Row(
                    children: [
                      _OnlineDot(),
                      SizedBox(width: 5),
                      Text(
                        'Chess assistant',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      body: ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: Column(
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
                      ? _EmptyChat(
                        suggestions: chatSuggestionsForScreen(
                          widget.screenContext?.screen,
                        ),
                        isTournamentContext:
                            widget.screenContext?.screen == 'tournament' ||
                            widget.screenContext?.screen == 'event',
                        onSuggestionPressed: _sendSuggestion,
                      )
                      : ListView.builder(
                        controller: _scrollController,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                        itemCount: _messages.length,
                        itemBuilder:
                            (context, index) => _MessageBubble(
                              message: _messages[index],
                              isStreaming:
                                  _sending && index == _messages.length - 1,
                              feedbackPending: _feedbackPending.contains(
                                _messages[index].id,
                              ),
                              onReferencePressed: _openReference,
                              onFeedbackPressed: _setFeedback,
                            ),
                      ),
            ),
            _ChatComposer(
              controller: _controller,
              sending: _sending,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

ChatConversation chatConversationForOpen(
  List<ChatConversation> conversations,
  String? preferredId,
) {
  if (preferredId != null) {
    for (final conversation in conversations) {
      if (conversation.id == preferredId) return conversation;
    }
  }
  return conversations.first;
}

String normalizeChatMarkdown(String source) {
  final breakTag = RegExp(r'<br\s*/?>', caseSensitive: false);
  return source
      .split('\n')
      .map((line) {
        if (!breakTag.hasMatch(line)) return line;
        final trimmed = line.trim();
        final isTableRow = trimmed.startsWith('|') && trimmed.endsWith('|');
        return line.replaceAll(breakTag, isTableRow ? '; ' : '\n');
      })
      .join('\n');
}

class _BotAvatar extends StatelessWidget {
  const _BotAvatar({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colorScheme.primary, colorScheme.tertiary],
        ),
        shape: BoxShape.circle,
        boxShadow:
            size > 48
                ? [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.22),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ]
                : null,
      ),
      child: Icon(
        Icons.auto_awesome_rounded,
        size: size * 0.52,
        color: colorScheme.onPrimary,
      ),
    );
  }
}

class _OnlineDot extends StatelessWidget {
  const _OnlineDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: const BoxDecoration(
        color: Color(0xff35c759),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _ChatComposer extends StatelessWidget {
  const _ChatComposer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            padding: const EdgeInsets.fromLTRB(16, 3, 6, 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 2000,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: 'Message Botvinnik…',
                      hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                      counterText: '',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, child) {
                      final canSend = value.text.trim().isNotEmpty && !sending;
                      return IconButton.filled(
                        tooltip: 'Send',
                        onPressed: canSend ? onSend : null,
                        style: IconButton.styleFrom(
                          minimumSize: const Size.square(40),
                          maximumSize: const Size.square(40),
                        ),
                        icon:
                            sending
                                ? const SizedBox.square(
                                  dimension: 17,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Icon(Icons.arrow_upward_rounded),
                      );
                    },
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

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({
    required this.suggestions,
    required this.isTournamentContext,
    required this.onSuggestionPressed,
  });

  final List<ChatSuggestion> suggestions;
  final bool isTournamentContext;
  final ValueChanged<String> onSuggestionPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _BotAvatar(size: 76),
              const SizedBox(height: 20),
              Text(
                'How can I help?',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isTournamentContext
                    ? 'Ask about this tournament’s format, schedule, rounds, games, or standings.'
                    : 'Ask about tournaments, schedules, rounds, games, or standings — in your preferred language.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              ...suggestions.map(
                (suggestion) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => onSuggestionPressed(suggestion.prompt),
                      icon: Icon(suggestion.icon, size: 18),
                      label: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(suggestion.label),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colorScheme.onSurface,
                        side: BorderSide(color: colorScheme.outlineVariant),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatSuggestion {
  const ChatSuggestion({
    required this.label,
    required this.prompt,
    required this.icon,
  });

  final String label;
  final String prompt;
  final IconData icon;
}

List<ChatSuggestion> chatSuggestionsForScreen(String? screen) {
  if (screen == 'tournament' || screen == 'event') {
    return const [
      ChatSuggestion(
        label: 'Tournament overview',
        prompt:
            'Give me an overview of this tournament and explain its format.',
        icon: Icons.emoji_events_outlined,
      ),
      ChatSuggestion(
        label: 'Schedule and rounds',
        prompt: 'Show the schedule and rounds for this tournament.',
        icon: Icons.calendar_month_outlined,
      ),
      ChatSuggestion(
        label: 'Current standings',
        prompt: 'Show the current standings for this tournament.',
        icon: Icons.leaderboard_outlined,
      ),
    ];
  }
  return const [
    ChatSuggestion(
      label: 'Live games',
      prompt: 'Which games are live right now?',
      icon: Icons.radio_button_checked_rounded,
    ),
    ChatSuggestion(
      label: 'Recent events',
      prompt: 'Which events were played last month?',
      icon: Icons.calendar_month_rounded,
    ),
    ChatSuggestion(
      label: 'Tournament format',
      prompt: 'Explain the format of the latest tournament.',
      icon: Icons.account_tree_outlined,
    ),
  ];
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isStreaming,
    required this.feedbackPending,
    required this.onReferencePressed,
    required this.onFeedbackPressed,
  });

  final ChatMessage message;
  final bool isStreaming;
  final bool feedbackPending;
  final ValueChanged<ChatReference> onReferencePressed;
  final void Function(ChatMessage message, String feedback) onFeedbackPressed;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final colorScheme = Theme.of(context).colorScheme;
    final referenceGroups = structureChatReferences(message.references);
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: isUser ? 420 : double.infinity),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
        color:
            isUser
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isUser ? 18 : 5),
          bottomRight: Radius.circular(isUser ? 5 : 18),
        ),
        border: isUser ? null : Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Text(
              'BOTVINNIK',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(height: 7),
          ],
          if (message.content.isEmpty && isStreaming)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  'Thinking…',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              ],
            )
          else if (isUser)
            SelectableText(
              message.content,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onPrimaryContainer,
                height: 1.4,
              ),
            )
          else
            MarkdownBody(
              data: normalizeChatMarkdown(message.content),
              selectable: true,
              softLineBreak: true,
              styleSheet: MarkdownStyleSheet.fromTheme(
                Theme.of(context),
              ).copyWith(
                p: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(height: 1.45),
                h1: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                h2: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                h3: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                blockSpacing: 12,
                tableCellsPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                tableBorder: TableBorder.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
          if (referenceGroups.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Related',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            ...referenceGroups.map(
              (group) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children:
                      group
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
                              side: BorderSide(
                                color: colorScheme.outlineVariant,
                              ),
                            ),
                          )
                          .toList(),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    final feedbackActions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FeedbackButton(
          tooltip: 'Helpful',
          icon: Icons.thumb_up_outlined,
          selectedIcon: Icons.thumb_up_rounded,
          selected: message.feedback == 'like',
          disabled: feedbackPending,
          onPressed: () => onFeedbackPressed(message, 'like'),
        ),
        _FeedbackButton(
          tooltip: 'Not helpful',
          icon: Icons.thumb_down_outlined,
          selectedIcon: Icons.thumb_down_rounded,
          selected: message.feedback == 'dislike',
          disabled: feedbackPending,
          onPressed: () => onFeedbackPressed(message, 'dislike'),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child:
          isUser
              ? Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Flexible(child: bubble)],
              )
              : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bubble,
                  if (message.content.isNotEmpty && !isStreaming)
                    Padding(
                      padding: const EdgeInsets.only(left: 2, top: 3),
                      child: feedbackActions,
                    ),
                ],
              ),
    );
  }
}

List<List<ChatReference>> structureChatReferences(
  List<ChatReference> references,
) {
  final visible = references.toList();
  if (visible.isEmpty) return const [];

  final consumed = <int>{};
  final groups = <List<ChatReference>>[];
  for (var index = 0; index < visible.length; index++) {
    final tournament = visible[index];
    if (tournament.type != 'tournament') continue;
    consumed.add(index);
    final group = <ChatReference>[tournament];
    for (var gameIndex = 0; gameIndex < visible.length; gameIndex++) {
      final game = visible[gameIndex];
      if (game.type == 'game' && game.tourId == tournament.id) {
        group.add(game);
        consumed.add(gameIndex);
      }
    }
    groups.add(group);
  }

  final pending = <ChatReference>[];
  for (var index = 0; index < visible.length; index++) {
    if (!consumed.contains(index)) pending.add(visible[index]);
  }
  if (pending.isNotEmpty) groups.add(pending);
  return groups;
}

class _FeedbackButton extends StatelessWidget {
  const _FeedbackButton({
    required this.tooltip,
    required this.icon,
    required this.selectedIcon,
    required this.selected,
    required this.disabled,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final IconData selectedIcon;
  final bool selected;
  final bool disabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      isSelected: selected,
      icon: Icon(icon, size: 18),
      selectedIcon: Icon(selectedIcon, size: 18),
      onPressed: disabled ? null : onPressed,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        foregroundColor: colorScheme.onSurfaceVariant,
        backgroundColor:
            selected ? colorScheme.secondaryContainer : Colors.transparent,
        disabledForegroundColor: colorScheme.onSurfaceVariant.withValues(
          alpha: 0.45,
        ),
      ),
    );
  }
}

class _ConversationDrawer extends ConsumerWidget {
  const _ConversationDrawer({
    required this.conversations,
    required this.selectedId,
    required this.onNew,
    required this.onSelect,
    required this.onDelete,
    required this.quota,
  });

  final List<ChatConversation> conversations;
  final String? selectedId;
  final Future<void> Function() onNew;
  final Future<void> Function(ChatConversation) onSelect;
  final Future<void> Function(ChatConversation) onDelete;
  final AsyncValue<ChatQuotaStatus?> quota;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    return Drawer(
      backgroundColor: colorScheme.surfaceContainerLow,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: Row(
                children: [
                  _BotAvatar(size: 38),
                  SizedBox(width: 10),
                  Text(
                    'Botvinnik',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onNew,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New chat'),
                  style: FilledButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.bolt_rounded,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: quota.when(
                        data: (value) {
                          final label =
                              value == null
                                  ? 'Sign in to view quota'
                                  : '${value.remaining} of ${value.limit} messages left';
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Daily allowance',
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                label,
                                style: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          );
                        },
                        loading:
                            () => const Text(
                              'Loading daily allowance…',
                              style: TextStyle(fontSize: 12),
                            ),
                        error:
                            (error, stack) => const Text(
                              'Daily allowance unavailable',
                              style: TextStyle(fontSize: 12),
                            ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh question count',
                      onPressed:
                          () => unawaited(
                            ref.read(botvinnikQuotaProvider.notifier).refresh(),
                          ),
                      icon: const Icon(Icons.refresh_rounded, size: 19),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Text(
                'RECENT CHATS',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: conversations.length,
                itemBuilder: (context, index) {
                  final conversation = conversations[index];
                  final selected = conversation.id == selectedId;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: ListTile(
                      selected: selected,
                      selectedTileColor: colorScheme.secondaryContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 19,
                        color:
                            selected
                                ? colorScheme.onSecondaryContainer
                                : colorScheme.onSurfaceVariant,
                      ),
                      title: Text(
                        conversation.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                      onTap: () => onSelect(conversation),
                      trailing: IconButton(
                        tooltip: 'Delete chat',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 19,
                        ),
                        onPressed: () => onDelete(conversation),
                      ),
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
