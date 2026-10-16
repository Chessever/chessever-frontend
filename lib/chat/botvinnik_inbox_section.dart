import 'dart:async';

import 'package:chessever2/chat/chat_assistant_bubble.dart';

import 'package:chessever2/screens/inbox/inbox_provider.dart';
import 'package:chessever2/screens/inbox/inbox_screen.dart';
import 'package:chessever2/services/editorial_link_service.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A view of Inbox, never a chat message or part of a conversation's payload.
/// Only identities are retained here: the shared Inbox remains the source of
/// both content and receipts, including changes from the other reader.
class BotvinnikInboxTimeline extends ConsumerStatefulWidget {
  const BotvinnikInboxTimeline({
    super.key,
    required this.emptyState,
    this.scrollController,
    this.conversationItemCount = 0,
    this.conversationItemBuilder,
    this.exposed = true,
  });

  final Widget emptyState;
  final ScrollController? scrollController;
  final int conversationItemCount;
  final IndexedWidgetBuilder? conversationItemBuilder;
  final bool exposed;

  @override
  ConsumerState<BotvinnikInboxTimeline> createState() =>
      _BotvinnikInboxTimelineState();
}

class _BotvinnikInboxTimelineState extends ConsumerState<BotvinnikInboxTimeline>
    with WidgetsBindingObserver {
  late final ScrollController _scroll;
  final _viewport = GlobalKey();
  final _bodyKeys = <(String, DateTime), GlobalKey>{};
  final _retained = <(String, DateTime)>{};
  final _attempted = <(String, DateTime)>{};
  String? _owner;
  bool _checkScheduled = false;

  @override
  void initState() {
    super.initState();
    _scroll = widget.scrollController ?? ScrollController();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_scheduleVisibilityCheck);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.removeListener(_scheduleVisibilityCheck);
    if (widget.scrollController == null) _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _scheduleVisibilityCheck();
  }

  void _scheduleVisibilityCheck() {
    if (_checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      _markVisible();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Rect? _rect(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _markVisible() {
    if (!mounted ||
        !widget.exposed ||
        ModalRoute.of(context)?.isCurrent != true ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final viewport = _rect(_viewport);
    if (viewport == null || viewport.isEmpty) return;
    final state = ref.read(inboxProvider);
    if (state.ownerId != _owner) return;
    for (final identity in _retained) {
      final message = state.message(identity.$1);
      if (message == null ||
          !message.isUnread ||
          message.publishedAt != identity.$2 ||
          state.marking.contains(message.id) ||
          state.markErrors.containsKey(message.id) ||
          _attempted.contains(identity)) {
        continue;
      }
      final key = _bodyKeys[identity];
      final body = key == null ? null : _rect(key);
      // Lazy-list cache children can be laid out without being visible.
      // Measure the body itself, not its title or an attached image.
      if (body == null || body.intersect(viewport).isEmpty) continue;
      _attempted.add(identity);
      unawaited(ref.read(inboxProvider.notifier).markOpened(message.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Subscribe to route visibility changes, including returning from a link.
    ModalRoute.of(context);
    final state = ref.watch(inboxProvider);
    if (state.ownerId != _owner) {
      _owner = state.ownerId;
      _retained.clear();
      _attempted.clear();
      _bodyKeys.clear();
    }
    final current = state.messages
        .map((message) => (message.id, message.publishedAt))
        .toSet();
    _retained.removeWhere((identity) => !current.contains(identity));
    _bodyKeys.removeWhere((identity, _) => !current.contains(identity));
    _attempted.removeWhere((identity) => !current.contains(identity));
    for (final message in state.messages) {
      if (message.isUnread) _retained.add((message.id, message.publishedAt));
    }
    final messages = state.messages
        .where(
          (message) => _retained.contains((message.id, message.publishedAt)),
        )
        .toList();
    if (messages.isEmpty && widget.conversationItemCount == 0) {
      return widget.emptyState;
    }
    _scheduleVisibilityCheck();
    return ClipRect(
      key: _viewport,
      child: NotificationListener<SizeChangedLayoutNotification>(
        onNotification: (_) {
          _scheduleVisibilityCheck();
          return false;
        },
        child: ListView.builder(
          key: ValueKey(('botvinnik-timeline', _owner)),
          controller: _scroll,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          itemCount: messages.length + widget.conversationItemCount,
          itemBuilder: (context, index) {
            if (index >= messages.length) {
              return widget.conversationItemBuilder!(
                context,
                index - messages.length,
              );
            }
            final message = messages[index];
            final identity = (message.id, message.publishedAt);
            return SizeChangedLayoutNotifier(
              key: ValueKey(identity),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: ChatAssistantBubble(
                  child: InboxMessageContent(
                    compact: true,
                    message: message,
                    bodyKey: _bodyKeys.putIfAbsent(identity, GlobalKey.new),
                    onLink: (uri) =>
                        ref.read(editorialLinkOpenerProvider)(context, uri),
                    markError: state.markErrors[message.id],
                    cacheError: state.cacheError,
                    onRetryRead: () =>
                        ref.read(inboxProvider.notifier).markOpened(message.id),
                    onRetryCache: ref.read(inboxProvider.notifier).refresh,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
