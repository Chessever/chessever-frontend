import 'dart:async';

import 'package:chessever2/chat/botvinnik_icon.dart';
import 'package:chessever2/chat/chat_api.dart';
import 'package:chessever2/chat/botvinnik_provider.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/services/deep_link_service.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

Uri? safeChatSourceUri(String? href) {
  if (href == null) return null;
  final uri = Uri.tryParse(href.trim());
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
  return uri;
}

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
    final auth = Supabase.instance.client.auth;
    if (auth.currentUser == null ||
        auth.currentUser!.isAnonymous ||
        auth.currentSession == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = null;
        });
      }
      return;
    }
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
      if (mounted) {
        setState(() => _loading = false);
        _scrollToEnd(animate: false);
      }
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
      _scrollToEnd(animate: false);
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
    final user = ref.read(currentUserProvider);
    final quota = ref.read(botvinnikQuotaProvider).valueOrNull;
    final access = chatComposerAccess(
      isSignedIn: user != null && !user.isAnonymous,
      quota: quota,
    );
    if (access == ChatComposerAccess.signedOut) {
      unawaited(_showLogin());
      return;
    }
    if (access == ChatComposerAccess.exhausted) {
      return;
    }
    if (access == ChatComposerAccess.upgradeRequired) {
      unawaited(_showUpgrade());
      return;
    }
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
      if (error.quota != null) {
        ref.read(botvinnikQuotaProvider.notifier).setQuota(error.quota!);
      } else {
        unawaited(ref.read(botvinnikQuotaProvider.notifier).refresh());
      }
      setState(() {
        _error =
            error.quota != null && error.quota!.remaining <= 0
                ? null
                : error.message;
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

  Future<void> _showLogin() async {
    final signedIn = await showAuthUpgradeSheet(
      context: context,
      title: 'Sign in to use Botvinnik',
      message: 'Sign in or create an account to start chatting.',
      dismissLabel: 'Not now',
    );
    if (!mounted || !signedIn) return;
    setState(() => _error = null);
    await ref.read(botvinnikQuotaProvider.notifier).refresh();
    await _load();
  }

  Future<void> _showUpgrade() async {
    await showPremiumPaywallSheet(context: context);
    if (!mounted) return;
    await ref.read(botvinnikQuotaProvider.notifier).refresh();
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

  void _scrollToEnd({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final end = _scrollController.position.maxScrollExtent;
      if (!animate) {
        _scrollController.jumpTo(end);
        return;
      }
      unawaited(
        _scrollController.animateTo(
          end,
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
      return;
    }
    if (reference.type == 'player') {
      final fideId = int.tryParse(reference.id);
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder:
              (_) => PlayerProfileScreen(
                fideId: fideId,
                playerName: reference.label,
                title: reference.title,
                federation: reference.federation,
                rating: reference.rating,
              ),
        ),
      );
      return;
    }
    if (reference.type == 'opening' &&
        RegExp(r'^[A-E][0-9]{2}$').hasMatch(reference.id.toUpperCase())) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder:
              (_) => SmartEventScreen(
                request: SmartEventRequest.forOpening(
                  GameEcoFilter.forCode(reference.id),
                ),
              ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final quota = ref.watch(botvinnikQuotaProvider);
    final user = ref.watch(currentUserProvider);
    final composerAccess = chatComposerAccess(
      isSignedIn: user != null && !user.isAnonymous,
      quota: quota.valueOrNull,
    );
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
            BotvinnikIcon(size: 40),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Botvinnik (Beta)'),
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
            switch (composerAccess) {
              ChatComposerAccess.signedOut => _ChatLoginGate(
                onSignIn: _showLogin,
              ),
              ChatComposerAccess.exhausted => const _ChatDailyLimitNotice(),
              ChatComposerAccess.upgradeRequired => _ChatUpgradeGate(
                onUpgrade: _showUpgrade,
              ),
              ChatComposerAccess.enabled => _ChatComposer(
                controller: _controller,
                sending: _sending,
                onSend: _send,
              ),
            },
          ],
        ),
      ),
    );
  }
}

enum ChatComposerAccess { signedOut, enabled, upgradeRequired, exhausted }

ChatComposerAccess chatComposerAccess({
  required bool isSignedIn,
  required ChatQuotaStatus? quota,
}) {
  if (!isSignedIn) return ChatComposerAccess.signedOut;
  if (quota != null && quota.remaining <= 0) {
    if (!quota.isPremium && quota.limit <= 0) {
      return ChatComposerAccess.upgradeRequired;
    }
    return ChatComposerAccess.exhausted;
  }
  return ChatComposerAccess.enabled;
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

class _ChatComposer extends StatefulWidget {
  const _ChatComposer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  State<_ChatComposer> createState() => _ChatComposerState();
}

class _ChatLoginGate extends StatelessWidget {
  const _ChatLoginGate({required this.onSignIn});

  final Future<void> Function() onSignIn;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
          ),
          child: FilledButton.icon(
            onPressed: onSignIn,
            icon: const Icon(Icons.login_rounded),
            label: const Text('Sign in to chat'),
          ),
        ),
      ),
    );
  }
}

class _ChatDailyLimitNotice extends StatelessWidget {
  const _ChatDailyLimitNotice();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Semantics(
        liveRegion: true,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            border: Border(top: BorderSide(color: colors.outlineVariant)),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: colors.tertiary),
              const SizedBox(width: 12),
              const Expanded(child: Text(chatDailyLimitMessage)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatUpgradeGate extends StatelessWidget {
  const _ChatUpgradeGate({required this.onUpgrade});
  final Future<void> Function() onUpgrade;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 5),
                color: colorScheme.surfaceContainerHighest,
                alignment: Alignment.center,
                child: Text(
                  'Botvinnik is available with Premium.',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onUpgrade,
                    icon: const Icon(Icons.workspace_premium_rounded),
                    label: const Text('Upgrade to continue chatting'),
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

class _ChatComposerState extends State<_ChatComposer> {
  static const _placeholders = <String>[
    'Your move—ask Botvinnik',
    '轮到你了——问问博特维尼克',
    'आपकी चाल—बोटविनिक से पूछें',
    'Tu jugada—pregúntale a Botvinnik',
    'حان دورك—اسأل بوتفينيك',
  ];

  static const _typingDelay = Duration(milliseconds: 70);
  static const _deletingDelay = Duration(milliseconds: 35);
  static const _completedPhrasePause = Duration(milliseconds: 1400);
  static const _betweenPhrasesPause = Duration(milliseconds: 250);

  Timer? _placeholderTimer;
  int _placeholderIndex = 0;
  int _visibleCharacterCount = 0;
  bool _isDeleting = false;
  bool _hasUserTyped = false;
  bool? _reduceMotion;

  List<int> get _currentRunes =>
      _placeholders[_placeholderIndex].runes.toList();

  String get _visiblePlaceholder =>
      String.fromCharCodes(_currentRunes.take(_visibleCharacterCount));

  @override
  void initState() {
    super.initState();
    _hasUserTyped = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion == reduceMotion) return;

    _placeholderTimer?.cancel();
    _reduceMotion = reduceMotion;
    _placeholderIndex = 0;
    _isDeleting = false;
    _visibleCharacterCount =
        reduceMotion || _hasUserTyped ? _currentRunes.length : 0;
    if (!reduceMotion && !_hasUserTyped) {
      _schedulePlaceholderTick(_typingDelay);
    }
  }

  @override
  void didUpdateWidget(covariant _ChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_onTextChanged);
    widget.controller.addListener(_onTextChanged);
    if (widget.controller.text.isNotEmpty) _stopPlaceholderAnimation();
  }

  void _onTextChanged() {
    if (_hasUserTyped || widget.controller.text.isEmpty) return;
    _stopPlaceholderAnimation();
  }

  void _stopPlaceholderAnimation() {
    _placeholderTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _hasUserTyped = true;
      _placeholderIndex = 0;
      _visibleCharacterCount = _currentRunes.length;
      _isDeleting = false;
    });
  }

  void _schedulePlaceholderTick(Duration delay) {
    _placeholderTimer = Timer(delay, _updatePlaceholder);
  }

  void _updatePlaceholder() {
    if (!mounted || _reduceMotion != false) return;
    final characterCount = _currentRunes.length;

    if (!_isDeleting && _visibleCharacterCount < characterCount) {
      setState(() => _visibleCharacterCount++);
      _schedulePlaceholderTick(
        _visibleCharacterCount == characterCount
            ? _completedPhrasePause
            : _typingDelay,
      );
      return;
    }

    if (!_isDeleting) {
      _isDeleting = true;
      _schedulePlaceholderTick(_deletingDelay);
      return;
    }

    if (_visibleCharacterCount > 0) {
      setState(() => _visibleCharacterCount--);
      _schedulePlaceholderTick(
        _visibleCharacterCount == 0 ? _betweenPhrasesPause : _deletingDelay,
      );
      return;
    }

    if (_placeholderIndex == _placeholders.length - 1) {
      setState(() {
        _placeholderIndex = 0;
        _visibleCharacterCount = _currentRunes.length;
        _isDeleting = false;
      });
      return;
    }

    _isDeleting = false;
    _placeholderIndex++;
    _schedulePlaceholderTick(_typingDelay);
  }

  @override
  void dispose() {
    _placeholderTimer?.cancel();
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

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
                    controller: widget.controller,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 2000,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: _visiblePlaceholder,
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
                    valueListenable: widget.controller,
                    builder: (context, value, child) {
                      final canSend =
                          value.text.trim().isNotEmpty && !widget.sending;
                      return IconButton.filled(
                        tooltip: 'Send',
                        onPressed: canSend ? widget.onSend : null,
                        style: IconButton.styleFrom(
                          minimumSize: const Size.square(40),
                          maximumSize: const Size.square(40),
                        ),
                        icon:
                            widget.sending
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
              const BotvinnikAnimatedIcon(size: 76),
              const SizedBox(height: 10),
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
            _CopyableMessageContent(
              text: message.content,
              child: Text(
                message.content,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  height: 1.4,
                ),
              ),
            )
          else
            _CopyableMessageContent(
              text: message.content,
              child: MarkdownBody(
                data: normalizeChatMarkdown(message.content),
                softLineBreak: true,
                onTapLink: (text, href, title) {
                  final uri = safeChatSourceUri(href);
                  if (uri != null) {
                    unawaited(launchUrl(uri, mode: LaunchMode.platformDefault));
                  }
                },
                styleSheet: MarkdownStyleSheet.fromTheme(
                  Theme.of(context),
                ).copyWith(
                  p: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.45),
                  h1: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  h2: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
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
                              avatar: Icon(switch (reference.type) {
                                'game' => Icons.sports_esports_rounded,
                                'player' => Icons.person_rounded,
                                'opening' => Icons.auto_stories_rounded,
                                _ => Icons.emoji_events_rounded,
                              }, size: 16),
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

class _CopyableMessageContent extends StatelessWidget {
  const _CopyableMessageContent({required this.text, required this.child});

  final String text;
  final Widget child;

  Future<void> _copyMessage(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    ContextMenuController.removeAny();
    await Clipboard.setData(ClipboardData(text: text));
    await HapticFeedback.lightImpact();
    if (messenger == null || !messenger.mounted) return;
    showAppSnackOn(messenger, 'Message copied', tone: AppSnackTone.success);
  }

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      contextMenuBuilder: (context, selectableRegionState) {
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: selectableRegionState.contextMenuAnchors,
          buttonItems: [
            ContextMenuButtonItem(
              label: 'Copy message',
              onPressed: () => unawaited(_copyMessage(context)),
            ),
          ],
        );
      },
      child: child,
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
  });

  final List<ChatConversation> conversations;
  final String? selectedId;
  final Future<void> Function() onNew;
  final Future<void> Function(ChatConversation) onSelect;
  final Future<void> Function(ChatConversation) onDelete;

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
                  BotvinnikIcon(size: 38),
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
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 17,
                          color: colorScheme.tertiary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Botvinnik can make mistakes. Check important information.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ],
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
