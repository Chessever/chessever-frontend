import 'dart:async';

import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:chessever2/screens/feed/news/news_content.dart';
import 'package:chessever2/screens/feed/news/news_cover.dart';
import 'package:chessever2/screens/feed/news/news_models.dart';
import 'package:chessever2/screens/feed/news/news_rich_blocks.dart';
import 'package:chessever2/screens/feed/widgets/feed_glyphs.dart';
import 'package:chessever2/services/deep_link_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shares the article's chessever.com link.
Future<void> shareNews(BuildContext context, FeedNews news) async {
  unawaited(HapticFeedbackService.buttonPress());
  final box = context.findRenderObject() as RenderBox?;
  final origin = box != null && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : const Rect.fromLTWH(0, 0, 1, 1);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final url = news.webUrl;
  try {
    await Share.share(
      url == null ? news.title : '${news.title}\n$url',
      subject: news.title,
      sharePositionOrigin: origin,
    );
  } catch (error) {
    debugPrint('[FeedNews] share failed: $error');
    if (messenger != null) {
      showAppSnackOn(
        messenger,
        "Couldn't open sharing.",
        tone: AppSnackTone.danger,
      );
    }
  }
}

/// A ChessEver News article, read in the app: cover, headline, byline and
/// the full body, with the web's rich blocks (team results and pairings,
/// section headings, videos) rendered natively.
class NewsReaderScreen extends ConsumerStatefulWidget {
  const NewsReaderScreen({super.key, required this.news});

  final FeedNews news;

  static Future<void> open(BuildContext context, FeedNews news) {
    unawaited(HapticFeedbackService.cardTap());
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: '/news/${news.id}'),
        builder: (_) => NewsReaderScreen(news: news),
      ),
    );
  }

  @override
  ConsumerState<NewsReaderScreen> createState() => _NewsReaderScreenState();
}

class _NewsReaderScreenState extends ConsumerState<NewsReaderScreen> {
  late List<NewsBlock> _blocks;
  late NewsAuthor? _author;
  late bool _showLead;

  @override
  void initState() {
    super.initState();
    _derive();
  }

  @override
  void didUpdateWidget(NewsReaderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.news.content != widget.news.content ||
        oldWidget.news.summary != widget.news.summary) {
      _derive();
    }
  }

  void _derive() {
    final news = widget.news;
    _blocks = newsReaderBlocks(news.content);
    _author = resolveNewsAuthor(news.content);
    // A summary the row did not set is the body's first words; skip it then.
    _showLead =
        news.summary.isNotEmpty &&
        !cleanNewsText(newsContentText(news.content)).startsWith(news.summary);
  }

  // ----------------------------------------------------------------- links

  Future<void> _openLink(Uri uri) async {
    unawaited(HapticFeedbackService.buttonPress());
    final articleId = newsArticleIdOf(uri);
    if (articleId != null) {
      if (articleId == widget.news.id) return;
      final items = ref.read(feedNewsProvider).valueOrNull ?? const [];
      for (final item in items) {
        if (item.id == articleId) {
          unawaited(NewsReaderScreen.open(context, item));
          return;
        }
      }
    }
    final route = newsInAppRoute(uri);
    if (route != null && DeepLinkService.instance.openLinkFromApp(route)) {
      return;
    }
    await _openExternal(uri);
  }

  Future<void> _openExternal(Uri uri) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      debugPrint('[FeedNews] link failed: $error');
    }
    if (!opened && messenger != null) {
      showAppSnackOn(
        messenger,
        "Couldn't open the link.",
        tone: AppSnackTone.danger,
      );
    }
  }

  // ----------------------------------------------------------------- build

  Widget _block(NewsBlock block) {
    return switch (block) {
      NewsMarkdownBlock(:final markdown) => NewsMarkdown(
        markdown: markdown,
        onLink: _openLink,
      ),
      NewsParagraphBlock(:final text) => NewsMarkdown(
        markdown: sanitizeNewsMarkdown(text),
        onLink: _openLink,
      ),
      NewsSectionBlock(:final text) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: NewsSectionHeading(text: text),
      ),
      NewsYoutubeBlock(:final videoId) => NewsYoutubeCard(
        videoId: videoId,
        onLink: _openLink,
      ),
      NewsResultsBlock(:final snapshot) => NewsResultsView(
        snapshot: snapshot,
        onLink: _openLink,
      ),
      NewsPairingsBlock(:final snapshot) => NewsPairingsView(
        snapshot: snapshot,
        onLink: _openLink,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final news = widget.news;
    final colors = context.colors;
    final gutter = 20.sp;
    final webUri = news.webUrl == null ? null : Uri.tryParse(news.webUrl!);
    // The web's source/context link ("Open Event", "Open Standings", ...).
    // Internal hrefs open in place through [_openLink]; a source that is
    // this very article would be a dead tap, so it is left out.
    final sourceHref = newsSourceContextHref(news);
    final sourceUri = resolveNewsHref(sourceHref);
    final showSource =
        sourceHref != null &&
        sourceUri != null &&
        newsArticleIdOf(sourceUri) != news.id;

    final children = <Widget>[
      Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'ChessEver News',
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: '  ·  ${formatNewsDate(news.publishedAt)}',
              style: TextStyle(color: colors.textSecondary),
            ),
          ],
        ),
        style: AppTypography.textSmMedium,
      ),
      SizedBox(height: 10.sp),
      Semantics(
        header: true,
        child: Text(
          news.title,
          style: AppTypography.displayXsBold.copyWith(
            color: colors.textPrimary,
            height: 1.18,
            letterSpacing: -0.2,
          ),
        ),
      ),
      if (_author case final NewsAuthor author) ...[
        SizedBox(height: 12.sp),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'By '),
              TextSpan(
                text: author.displayName,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextSpan(text: '  ·  ${author.role}'),
            ],
          ),
          style: AppTypography.textSmRegular.copyWith(
            color: colors.textSecondary,
          ),
        ),
      ],
      if (_showLead) ...[
        SizedBox(height: 14.sp),
        Text(
          news.summary,
          style: AppTypography.textLgRegular.copyWith(
            color: colors.textSecondary,
            height: 1.5,
          ),
        ),
      ],
      SizedBox(height: 24.sp),
      for (var i = 0; i < _blocks.length; i++) ...[
        if (i > 0) SizedBox(height: 20.sp),
        _block(_blocks[i]),
      ],
      if (showSource || webUri != null) SizedBox(height: 36.sp),
      if (showSource)
        _ReaderLinkRow(
          label: newsSourceContextLabel(sourceHref),
          onTap: () => _openLink(sourceUri),
        ),
      if (showSource && webUri != null) SizedBox(height: 8.sp),
      if (webUri != null)
        _ReaderLinkRow(
          label: 'Open on chessever.com',
          onTap: () => _openExternal(webUri),
        ),
    ];

    return Scaffold(
      backgroundColor: colors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: colors.background,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            elevation: 0,
            automaticallyImplyLeading: false,
            toolbarHeight: 52,
            titleSpacing: 0,
            leadingWidth: 56,
            leading: Semantics(
              button: true,
              label: 'Back',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
                child: Center(
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 20,
                    color: colors.iconPrimary,
                  ),
                ),
              ),
            ),
            actions: [
              Builder(
                builder: (buttonContext) => Semantics(
                  button: true,
                  label: 'Share article',
                  excludeSemantics: true,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => shareNews(buttonContext, news),
                    child: SizedBox(
                      width: 52,
                      height: 52,
                      child: Center(
                        child: FeedGlyph(
                          FeedGlyphs.share,
                          width: 20,
                          height: 20,
                          color: colors.iconPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
          if (news.imageUrl case final String imageUrl)
            SliverToBoxAdapter(child: _ReaderCover(imageUrl: imageUrl))
          else
            SliverToBoxAdapter(child: SizedBox(height: 12.sp)),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              gutter,
              0,
              gutter,
              28.sp + MediaQuery.paddingOf(context).bottom,
            ),
            sliver: SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The cover under the bar: feathered at the top into the bar and at the
/// bottom into the page, so the headline rises out of the picture.
class _ReaderCover extends StatelessWidget {
  const _ReaderCover({required this.imageUrl});

  final String imageUrl;

  /// A cover that fails to load leaves quiet space, not the black brand
  /// slab (the reader follows the app theme, which may be light).
  static const Widget _quiet = SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = (constraints.maxWidth * 0.62).clamp(180.0, 420.0);
        return SizedBox(
          height: height,
          child: reduceMotion
              ? NewsCover(imageUrl: imageUrl, fadeTop: 0.08, fallback: _quiet)
              // One-shot: the picture settles as the page opens.
              : SingleMotionBuilder(
                  value: 1,
                  from: 1.05,
                  motion: const CupertinoMotion.smooth(
                    duration: Duration(milliseconds: 900),
                  ),
                  builder: (context, scale, _) => NewsCover(
                    imageUrl: imageUrl,
                    fadeTop: 0.08,
                    fallback: _quiet,
                    scale: scale,
                  ),
                ),
        );
      },
    );
  }
}

/// A full-width link at the foot of the article.
class _ReaderLinkRow extends StatelessWidget {
  const _ReaderLinkRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      link: true,
      label: label,
      excludeSemantics: true,
      child: NewsPressable(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(4),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: AppTypography.textMdMedium.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  NewsOutArrow(color: colors.textSecondary, size: 14),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
