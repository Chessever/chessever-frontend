import 'dart:async';

import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import 'inbox_provider.dart';
import 'inbox_unread_dot.dart';

String _date(BuildContext context, DateTime date) => DateFormat.yMMMd(
  Localizations.localeOf(context).toString(),
).format(date.toLocal());

class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(ref.read(inboxProvider.notifier).refresh());
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inboxProvider);
    final controller = ref.read(inboxProvider.notifier);
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: const Text('Inbox'),
        backgroundColor: context.colors.background,
        foregroundColor: context.colors.textPrimary,
        actions: [
          IconButton(
            tooltip: 'Refresh Inbox',
            onPressed: state.refreshing ? null : controller.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: state.loading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Text('Updates and chess tips from ChessEver'),
                  ),
                  if (state.refreshing) const LinearProgressIndicator(),
                  if (state.syncError != null)
                    _RetryNotice(
                      message: state.syncError!,
                      onRetry: controller.refresh,
                    ),
                  if (state.cacheError != null)
                    _RetryNotice(
                      message: state.cacheError!,
                      onRetry: controller.refresh,
                    ),
                  if (state.messages.isEmpty && state.syncError == null)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Your Inbox is empty.\nChessEver messages will appear here.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  for (final message in state.messages)
                    ListTile(
                      key: ValueKey('inbox-row-${message.id}'),
                      minVerticalPadding: 16,
                      title: Text(
                        message.title,
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontWeight: message.isUnread
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        _date(context, message.publishedAt),
                        style: TextStyle(color: context.colors.textSecondary),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (message.isUnread)
                            InboxUnreadDot(
                              key: ValueKey('inbox-row-dot-${message.id}'),
                            ),
                          const SizedBox(width: 12),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      onTap: () {
                        final owner = state.ownerId;
                        if (owner == null) return;
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => InboxMessageScreen(
                              ownerId: owner,
                              messageId: message.id,
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

class InboxMessageScreen extends ConsumerStatefulWidget {
  const InboxMessageScreen({
    super.key,
    required this.ownerId,
    required this.messageId,
  });
  final String ownerId;
  final String messageId;

  @override
  ConsumerState<InboxMessageScreen> createState() => _InboxMessageScreenState();
}

class _InboxMessageScreenState extends ConsumerState<InboxMessageScreen> {
  bool _scheduledRead = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inboxProvider);
    // Never retain a route-local body across an account change.
    final message = state.ownerId == widget.ownerId
        ? state.message(widget.messageId)
        : null;
    if (message != null && !_scheduledRead) {
      _scheduledRead = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
        final current = ref.read(inboxProvider);
        if (current.ownerId != widget.ownerId ||
            current.message(widget.messageId) == null) {
          return;
        }
        // The first frame containing this exact full text is now on screen.
        unawaited(
          ref.read(inboxProvider.notifier).markOpened(widget.messageId),
        );
      });
    }
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: const Text('ChessEver message'),
        backgroundColor: context.colors.background,
        foregroundColor: context.colors.textPrimary,
      ),
      body: message == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('This message is unavailable for this account.'),
                    TextButton(
                      onPressed: () =>
                          ref.read(inboxProvider.notifier).refresh(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  message.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: context.colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _date(context, message.publishedAt),
                  style: TextStyle(color: context.colors.textSecondary),
                ),
                const SizedBox(height: 24),
                // No HTML/Markdown/link interpretation, attachments or CTAs.
                SelectableText(
                  message.body,
                  key: const ValueKey('inbox-full-text'),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: context.colors.textPrimary,
                    height: 1.5,
                  ),
                ),
                if (state.marking.contains(message.id))
                  const Padding(
                    padding: EdgeInsets.only(top: 20),
                    child: Text('Saving read status…'),
                  ),
                if (state.markErrors[message.id] != null)
                  _RetryNotice(
                    message: state.markErrors[message.id]!,
                    onRetry: () =>
                        ref.read(inboxProvider.notifier).markOpened(message.id),
                  ),
                if (state.cacheError != null)
                  _RetryNotice(
                    message: state.cacheError!,
                    onRetry: () => ref.read(inboxProvider.notifier).refresh(),
                  ),
              ],
            ),
    );
  }
}

class _RetryNotice extends StatelessWidget {
  const _RetryNotice({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: TextStyle(color: context.colors.textSecondary)),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    ),
  );
}
