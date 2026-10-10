import 'dart:async';

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import 'inbox_provider.dart';
import 'inbox_unread_dot.dart';

String _date(BuildContext context, DateTime date) => DateFormat.yMMMd(
  Localizations.localeOf(context).toString(),
).format(date.toLocal());

/// Reading width on tablets; phones use the full width.
const double _readingWidth = 640;

/// The page's own flat bar: no elevation and no Material tint on scroll.
AppBar _inboxBar(
  BuildContext context, {
  required String title,
  List<Widget>? actions,
}) => AppBar(
  title: Text(title),
  titleTextStyle: AppTypography.textLgBold.copyWith(
    color: context.colors.textPrimary,
  ),
  // Tight to the back arrow; a normal gutter when there is none.
  titleSpacing: (ModalRoute.of(context)?.canPop ?? false) ? 0 : 16,
  backgroundColor: context.colors.background,
  foregroundColor: context.colors.textPrimary,
  surfaceTintColor: Colors.transparent,
  elevation: 0,
  scrolledUnderElevation: 0,
  actions: actions,
);

Widget _reading({required Widget child}) => Center(
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: _readingWidth),
    child: child,
  ),
);

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
      appBar: _inboxBar(
        context,
        title: 'Inbox',
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
            : _reading(
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 4, bottom: 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Text(
                        'Updates and chess tips from ChessEver',
                        style: AppTypography.textSmRegular.copyWith(
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ),
                    if (state.refreshing)
                      LinearProgressIndicator(
                        minHeight: 2,
                        color: context.isLightTheme
                            ? context.colors.accentText
                            : kPrimaryColor,
                        backgroundColor: Colors.transparent,
                      ),
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
                      Padding(
                        padding: const EdgeInsets.fromLTRB(32, 72, 32, 32),
                        child: Text(
                          'Your Inbox is empty.\nChessEver messages will appear here.',
                          textAlign: TextAlign.center,
                          style: AppTypography.textMdRegular.copyWith(
                            color: context.colors.textSecondary,
                          ),
                        ),
                      ),
                    for (final message in state.messages)
                      _InboxRow(
                        key: ValueKey('inbox-row-${message.id}'),
                        title: message.title,
                        preview: message.body,
                        date: _date(context, message.publishedAt),
                        unreadDot: message.isUnread
                            ? InboxUnreadDot(
                                key: ValueKey('inbox-row-dot-${message.id}'),
                              )
                            : null,
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
      ),
    );
  }
}

/// One message in the list: a quiet card with the title, the date and the
/// first lines of the text. Unread shows in the title's weight and a dot in
/// the gutter, which stays reserved once read so titles never shift.
class _InboxRow extends StatelessWidget {
  const _InboxRow({
    super.key,
    required this.title,
    required this.preview,
    required this.date,
    required this.unreadDot,
    required this.onTap,
  });

  final String title;
  final String preview;
  final String date;
  final Widget? unreadDot;
  final VoidCallback onTap;

  static const double _gutter = 20;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final unread = unreadDot != null;
    final radius = BorderRadius.circular(14);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: colors.popup,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _gutter,
                  // Level with the title's first line, whatever its size.
                  height:
                      (AppTypography.textMdBold.fontSize ?? 16) *
                      (AppTypography.textMdBold.height ?? 1.5),
                  child: Center(child: unreadDot),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  (unread
                                          ? AppTypography.textMdBold
                                          : AppTypography.textMdMedium)
                                      .copyWith(
                                        color: unread
                                            ? colors.textPrimary
                                            : colors.textSecondary,
                                      ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            date,
                            style: AppTypography.textXsRegular.copyWith(
                              color: colors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        // Collapse line breaks so two lines carry real text.
                        preview.replaceAll(RegExp(r'\s+'), ' ').trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.textSmRegular.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
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
      appBar: _inboxBar(context, title: 'ChessEver message'),
      body: message == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'This message is unavailable for this account.',
                      textAlign: TextAlign.center,
                      style: AppTypography.textMdRegular.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          ref.read(inboxProvider.notifier).refresh(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : _reading(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                children: [
                  Text(
                    message.title,
                    style: AppTypography.displayXsBold.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _date(context, message.publishedAt),
                    style: AppTypography.textSmRegular.copyWith(
                      color: context.colors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // No HTML/Markdown/link interpretation, attachments or CTAs.
                  SelectableText(
                    message.body,
                    key: const ValueKey('inbox-full-text'),
                    style: AppTypography.textMdRegular.copyWith(
                      color: context.colors.textPrimary,
                      height: 1.6,
                    ),
                  ),
                  if (state.marking.contains(message.id))
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Text(
                        'Saving read status…',
                        style: AppTypography.textSmRegular.copyWith(
                          color: context.colors.textTertiary,
                        ),
                      ),
                    ),
                  if (state.markErrors[message.id] != null)
                    _RetryNotice(
                      message: state.markErrors[message.id]!,
                      onRetry: () => ref
                          .read(inboxProvider.notifier)
                          .markOpened(message.id),
                    ),
                  if (state.cacheError != null)
                    _RetryNotice(
                      message: state.cacheError!,
                      onRetry: () => ref.read(inboxProvider.notifier).refresh(),
                    ),
                ],
              ),
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
        Text(
          message,
          style: AppTypography.textSmRegular.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        TextButton(
          onPressed: onRetry,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 44),
            alignment: Alignment.centerLeft,
            foregroundColor: context.isLightTheme
                ? context.colors.accentText
                : kPrimaryColor,
            textStyle: AppTypography.textSmSemiBold,
          ),
          child: const Text('Retry'),
        ),
      ],
    ),
  );
}
