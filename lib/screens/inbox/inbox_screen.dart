import 'dart:async';

import 'package:chessever2/screens/collections/event_view_shell.dart';
import 'package:chessever2/screens/feed/news/news_content.dart';
import 'package:chessever2/screens/feed/news/news_cover.dart';
import 'package:chessever2/screens/feed/news/news_rich_blocks.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart';
import 'package:chessever2/screens/my_space/widgets/pixel_art.dart';
import 'package:chessever2/screens/my_space/widgets/space_glyphs.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/services/editorial_link_service.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

import 'inbox_message.dart';
import 'inbox_provider.dart';
import 'inbox_unread_dot.dart';

String _date(BuildContext context, DateTime date) => DateFormat.yMMMd(
  Localizations.localeOf(context).toString(),
).format(date.toLocal());

/// A message's attached image, when it may load on its own: only from the
/// origins article pictures load from (this project's public Storage and
/// chessever.com), so opening a message never calls out to another host.
Uri? inboxImageUri(String? url) {
  final uri = resolveNewsHref(url);
  return uri != null && isNewsImageSourceAllowed(uri) ? uri : null;
}

/// Reading width of a message's text on tablets; phones use the full width.
const double _readingWidth = 640;

/// The Inbox's pages on the shell every pushed hub destination stands in:
/// the back arrow, the destination's mark and name, and one page beneath.
Widget _inboxShell({required Widget child}) => EventViewShell(
  title: 'Inbox',
  titleIcon: const Icon(Icons.inbox_outlined),
  tabs: const ['Inbox'],
  tabStripOverride: const SizedBox.shrink(),
  pageBuilder: (_, _) => child,
);

/// A state that fills the page (nothing to list, a failed load) and still
/// scrolls, so pull-to-refresh answers on it too.
class _FillPage extends StatelessWidget {
  const _FillPage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: child,
      ),
    ),
  );
}

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

  void _open(InboxState state, InboxMessage message) {
    final owner = state.ownerId;
    if (owner == null) return;
    HapticFeedbackService.cardTap();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            InboxMessageScreen(ownerId: owner, messageId: message.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inboxProvider);
    final controller = ref.read(inboxProvider.notifier);
    final messages = ref.watch(inboxListedMessagesProvider);
    final attention = {
      for (final message in ref.watch(inboxAttentionProvider)) message.id,
    };
    final bottom = MediaQuery.viewPaddingOf(context).bottom + 24.h;

    final Widget page;
    if (state.loading) {
      page = const _InboxSkeleton();
    } else if (messages.isEmpty && state.syncError != null) {
      page = _FillPage(
        child: GenericErrorWidget(
          message: state.syncError,
          onRetry: controller.refresh,
        ),
      );
    } else if (messages.isEmpty) {
      page = const _FillPage(child: _InboxEmpty());
    } else {
      page = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(top: 4.h, bottom: bottom),
        children: [
          for (final error in [state.syncError, state.cacheError])
            if (error != null)
              DiscoveryNotice(
                text: error,
                actionLabel: 'Retry',
                onAction: controller.refresh,
              ),
          for (final message in messages)
            _InboxRow(
              key: ValueKey('inbox-row-${message.id}'),
              title: message.title,
              preview: message.previewText,
              image: inboxImageUri(message.imageUrl),
              date: _date(context, message.publishedAt),
              unreadDot: attention.contains(message.id)
                  ? InboxUnreadDot(key: ValueKey('inbox-row-dot-${message.id}'))
                  : null,
              onTap: () => _open(state, message),
            ),
        ],
      );
    }

    return _inboxShell(
      child: RefreshIndicator(
        onRefresh: controller.refresh,
        color: context.colors.accentText,
        backgroundColor: context.colors.surface,
        child: page,
      ),
    );
  }
}

/// One message in the list, in the hub's card frame: the title and its date
/// on one line, the first lines of the text beneath. Unread shows in the
/// title's weight and a dot at the end of the text, a place kept once the
/// message is read so nothing reflows. An attached image shows as a thumbnail
/// at the card's end.
class _InboxRow extends StatelessWidget {
  const _InboxRow({
    super.key,
    required this.title,
    required this.preview,
    required this.date,
    required this.unreadDot,
    required this.onTap,
    this.image,
  });

  final String title;
  final String preview;
  final Uri? image;
  final String date;
  final Widget? unreadDot;
  final VoidCallback? onTap;

  static const double _dotSlot = 8;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final unread = unreadDot != null;
    final previewStyle = discoveryType(
      context,
      DiscoveryType.label,
      weight: FontWeight.w400,
      color: colors.textSecondary,
    );
    final picture = image;
    final thumb = 56.sp;
    final text = Column(
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
                style: discoveryType(
                  context,
                  DiscoveryType.body,
                  weight: unread ? FontWeight.w700 : FontWeight.w500,
                  color: unread ? colors.textPrimary : colors.textPrimaryMuted,
                ),
              ),
            ),
            SizedBox(width: 12.w),
            Text(
              date,
              maxLines: 1,
              style: discoveryType(context, DiscoveryType.meta, tabular: true),
            ),
          ],
        ),
        SizedBox(height: 4.h),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: previewStyle,
              ),
            ),
            SizedBox(width: 12.w),
            SizedBox(
              width: _dotSlot,
              // Level with the text's first line, whatever its size.
              height: MediaQuery.textScalerOf(
                context,
              ).scale(previewStyle.fontSize! * previewStyle.height!),
              child: Center(child: unreadDot),
            ),
          ],
        ),
      ],
    );
    final card = Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8.br),
      ),
      padding: EdgeInsets.fromLTRB(14.sp, 12.sp, 14.sp, 14.sp),
      child: picture == null
          ? text
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: text),
                SizedBox(width: 12.w),
                ExcludeSemantics(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4.br),
                    child: NewsNetworkImage(
                      url: picture.toString(),
                      pixelWidth:
                          (thumb * MediaQuery.devicePixelRatioOf(context))
                              .round(),
                      width: thumb,
                      height: thumb,
                      fit: BoxFit.cover,
                      placeholder: (context, _) => ColoredBox(
                        color: colors.surfaceRecessed,
                        child: SizedBox.square(dimension: thumb),
                      ),
                      errorWidget: (context, _, _) => ColoredBox(
                        color: colors.surfaceRecessed,
                        child: SizedBox.square(dimension: thumb),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
    final open = onTap;
    return Padding(
      padding: EdgeInsets.fromLTRB(discoveryGutter, 0, discoveryGutter, 8.h),
      child: open == null
          ? card
          : Semantics(
              button: true,
              child: TappableScale(scaleDown: 0.98, onTap: open, child: card),
            ),
    );
  }
}

/// The list's shape while the first load is out: the rows themselves, boned.
class _InboxSkeleton extends StatelessWidget {
  const _InboxSkeleton();

  @override
  Widget build(BuildContext context) => SkeletonWidget(
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(top: 4.h),
      children: [
        for (final title in const [
          'A message from the team',
          'What changed this week',
          'A tip for your next game',
          'Something new to try out',
        ])
          _InboxRow(
            title: title,
            preview:
                'The first lines of a message stand here while the Inbox '
                'is loading, two lines of them at the most.',
            date: 'Sep 30, 2026',
            unreadDot: null,
            onTap: null,
          ),
      ],
    ),
  );
}

/// Nothing published yet: the Inbox's envelope and one line.
class _InboxEmpty extends StatelessWidget {
  const _InboxEmpty();

  @override
  Widget build(BuildContext context) {
    final side = 96.w;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 40.w, vertical: 48.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: SizedBox(
                width: side,
                // The envelope is 12 blocks by 8.
                height: side * 2 / 3,
                child: PixelArtView(
                  scene: PixelScene.mark(
                    PixelArt.envelope(tone: PixelTone.of(context)),
                    Size(side, side * 2 / 3),
                  ),
                ),
              ),
            ),
            SizedBox(height: 20.h),
            Text(
              'Updates and chess tips from the ChessEver team arrive here.',
              textAlign: TextAlign.center,
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textSecondary,
                height: 20 / 14,
              ),
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
  DateTime? _scheduledPublication;

  /// A link in a message: a ChessEver page opens in the app, anything else
  /// in the browser.
  Future<void> _openLink(Uri uri) async {
    unawaited(HapticFeedbackService.buttonPress());
    await ref.read(editorialLinkOpenerProvider)(context, uri);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(inboxProvider);
    final controller = ref.read(inboxProvider.notifier);
    // Never retain a route-local body across an account change.
    final message = state.ownerId == widget.ownerId
        ? state.message(widget.messageId)
        : null;
    if (message != null && _scheduledPublication != message.publishedAt) {
      _scheduledPublication = message.publishedAt;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
        final current = ref.read(inboxProvider);
        if (current.ownerId != widget.ownerId ||
            current.message(widget.messageId)?.publishedAt !=
                message.publishedAt) {
          return;
        }
        // The first frame containing this exact full text is now on screen.
        unawaited(controller.markOpened(widget.messageId));
      });
    }
    if (message == null) {
      if (state.ownerId == widget.ownerId &&
          (state.loading || state.refreshing)) {
        return _inboxShell(child: const _InboxSkeleton());
      }
      return _inboxShell(
        child: GenericErrorWidget(
          message: state.ownerId == widget.ownerId
              ? state.syncError ??
                    'This message is unavailable for this account.'
              : 'This message is unavailable for this account.',
          onRetry: controller.refresh,
        ),
      );
    }
    return _inboxShell(
      // Top-aligned: centering would float a short message mid-page.
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _readingWidth),
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              top: 12.h,
              bottom: MediaQuery.viewPaddingOf(context).bottom + 40.h,
            ),
            child: InboxMessageContent(
              message: message,
              onLink: _openLink,
              markError: state.markErrors[message.id],
              cacheError: state.cacheError,
              onRetryRead: () => controller.markOpened(message.id),
              onRetryCache: controller.refresh,
            ),
          ),
        ),
      ),
    );
  }
}

/// The same full editorial content in Inbox details and temporary chat notices.
class InboxMessageContent extends StatelessWidget {
  const InboxMessageContent({
    super.key,
    required this.message,
    required this.onLink,
    this.bodyKey,
    this.compact = false,
    this.markError,
    this.cacheError,
    this.onRetryRead,
    this.onRetryCache,
  });

  final InboxMessage message;
  final Future<void> Function(Uri) onLink;
  final Key? bodyKey;
  final bool compact;
  final String? markError;
  final String? cacheError;
  final VoidCallback? onRetryRead;
  final VoidCallback? onRetryCache;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final markError = this.markError;
    final cacheError = this.cacheError;
    final side = compact
        ? EdgeInsets.zero
        : EdgeInsets.symmetric(horizontal: discoveryGutter);
    final bodyStyle = compact
        ? Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45)
        : AppTypography.textMdRegular.copyWith(
            color: colors.textPrimary,
            height: 1.6,
          );
    final picture = inboxImageUri(message.imageUrl);
    // The button's link: http(s) only, a ChessEver page opening in the app.
    final actionLabel = message.actionLabel;
    final actionUri = resolveNewsHref(message.actionUrl);
    final pictureWidth =
        (MediaQuery.sizeOf(context).width.clamp(0, _readingWidth) *
                MediaQuery.devicePixelRatioOf(context))
            .round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: side,
          child: Text(
            message.title,
            style: compact
                ? Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.45,
                  )
                : AppTypography.displayXsBold.copyWith(
                    color: colors.textPrimary,
                  ),
          ),
        ),
        if (!compact) ...[
          SizedBox(height: 6.h),
          Padding(
            padding: side,
            child: Text(
              _date(context, message.publishedAt),
              style: discoveryType(context, DiscoveryType.meta, tabular: true),
            ),
          ),
        ],
        SizedBox(height: compact ? 8 : 20.h),
        if (picture != null) ...[
          Padding(
            padding: side,
            child: ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8.br),
                child: NewsNetworkImage(
                  key: const ValueKey('inbox-image'),
                  url: picture.toString(),
                  pixelWidth: pictureWidth > 0 ? pictureWidth : null,
                  fit: BoxFit.fitWidth,
                  width: double.infinity,
                  placeholder: (context, _) => AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ColoredBox(color: colors.surface),
                  ),
                  errorWidget: (context, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
          SizedBox(height: 20.h),
        ],
        Padding(
          padding: side,
          key: bodyKey,
          child: message.isMarkdown
              // Markdown only, in the article reader's own renderer:
              // raw HTML is never interpreted.
              ? KeyedSubtree(
                  key: const ValueKey('inbox-full-text'),
                  child: NewsMarkdown(
                    markdown: sanitizeNewsMarkdown(message.body),
                    bodyStyle: compact ? bodyStyle : null,
                    onLink: onLink,
                  ),
                )
              // Plain text is shown exactly as written.
              : SelectableText(
                  message.body,
                  key: const ValueKey('inbox-full-text'),
                  style: bodyStyle,
                ),
        ),
        if (actionLabel != null && actionUri != null) ...[
          SizedBox(height: 24.h),
          Padding(
            padding: side,
            child: Semantics(
              button: true,
              label: actionLabel,
              excludeSemantics: true,
              child: AppButton(
                key: const ValueKey('inbox-action'),
                text: actionLabel,
                icon: SpaceGlyph(
                  SpaceGlyphKind.arrowUpRight,
                  size: 14.sp,
                  ink: colors.textInverse,
                ),
                onPressed: () => onLink(actionUri),
              ),
            ),
          ),
        ],
        if (markError != null || cacheError != null) SizedBox(height: 12.h),
        if (markError != null)
          DiscoveryNotice(
            text: markError,
            actionLabel: 'Retry',
            onAction: onRetryRead,
          ),
        if (cacheError != null)
          DiscoveryNotice(
            text: cacheError,
            actionLabel: 'Retry',
            onAction: onRetryCache,
          ),
      ],
    );
  }
}
