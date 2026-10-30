import 'dart:async';

import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:chessever2/screens/feed/news/news_content.dart';
import 'package:chessever2/screens/feed/news/news_cover.dart';
import 'package:chessever2/screens/feed/news/news_hero_cover.dart';
import 'package:chessever2/screens/feed/news/news_models.dart';
import 'package:chessever2/screens/feed/news/news_reader_pager.dart';
import 'package:chessever2/screens/feed/news/news_repository.dart';
import 'package:chessever2/screens/feed/news/news_rich_blocks.dart';
import 'package:chessever2/screens/feed/widgets/feed_glyphs.dart';
import 'package:chessever2/services/deep_link_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/foundation.dart';
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
  final url = newsShareUrl(news);
  try {
    await Share.share(
      '${news.title}\n$url',
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

/// A news article, read in the app: cover, headline, byline and the full
/// body, with the web's rich blocks (team results and pairings, section
/// headings, videos) rendered natively.
///
/// A partner's article carries the partner's mark and name and always
/// links to the original on the partner's site: under the headline, and as
/// a button at its end.
class NewsReaderScreen extends ConsumerStatefulWidget {
  const NewsReaderScreen({super.key, required this.news, this.heroTag});

  final FeedNews news;
  final Object? heroTag;

  static Future<void> open(BuildContext context, FeedNews news) async {
    final cached =
        ProviderScope.containerOf(
          context,
          listen: false,
        ).read(feedNewsProvider).valueOrNull ??
        const <FeedNews>[];
    final articles = mergeFeedNews([
      news,
    ], cached.where((item) => item.key != news.key).toList());
    try {
      await NewsReaderPager.open(
        context,
        articles: articles,
        initialIndex: articles.indexWhere((item) => item.key == news.key),
        heroScope: Object(),
      );
    } catch (_) {
      if (context.mounted) {
        showAppSnack(
          context,
          "Couldn't open news. Try again.",
          tone: AppSnackTone.danger,
        );
      }
    }
  }

  @override
  ConsumerState<NewsReaderScreen> createState() => _NewsReaderScreenState();
}

class _NewsReaderScreenState extends ConsumerState<NewsReaderScreen> {
  static const double _barHeight = 52;

  late List<NewsBlock> _blocks;
  late NewsAuthor? _author;
  late bool _showLead;

  final _scroll = ScrollController();
  final _headline = GlobalKey();

  /// Whether the headline has scrolled up under the bar, which then carries
  /// the title instead.
  final _titleInBar = ValueNotifier(false);
  bool _syncQueued = false;

  @override
  void initState() {
    super.initState();
    _derive();
    _scroll.addListener(_queueBarTitleSync);
    // A restored reading position never reports a scroll.
    _queueBarTitleSync();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _titleInBar.dispose();
    super.dispose();
  }

  /// The headline's position is read after layout: a scroll notifies before
  /// the slivers move, so reading it then would lag a frame behind.
  void _queueBarTitleSync() {
    if (_syncQueued) return;
    _syncQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncQueued = false;
      _syncBarTitle();
    });
  }

  void _syncBarTitle() {
    if (!mounted) return;
    final page = context.findRenderObject() as RenderBox?;
    final headline = _headline.currentContext?.findRenderObject() as RenderBox?;
    if (page == null || headline == null || !headline.attached) return;
    final bottom = headline
        .localToGlobal(Offset(0, headline.size.height), ancestor: page)
        .dy;
    _titleInBar.value =
        bottom <= MediaQuery.paddingOf(context).top + _barHeight;
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
    // A partner's summary is usually its first paragraph, quotes aside.
    _showLead =
        news.summary.isNotEmpty &&
        (news.publisher.isPartner
            ? !newsSummaryRepeatsBody(news.summary, news.content)
            : !cleanNewsText(
                newsContentText(news.content),
              ).startsWith(news.summary));
  }

  // ----------------------------------------------------------------- links

  Future<void> _openLink(Uri uri) async {
    unawaited(HapticFeedbackService.buttonPress());
    final items = ref.read(feedNewsProvider).valueOrNull ?? const [];
    final article = newsArticleAt(uri, [widget.news, ...items]);
    if (article != null) {
      if (article.key == widget.news.key) return;
      unawaited(NewsReaderScreen.open(context, article));
      return;
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
        newsArticleAt(sourceUri, [news])?.key != news.key;
    final publisher = news.publisher;
    final body = <Widget>[
      for (var i = 0; i < _blocks.length; i++) ...[
        if (i > 0) SizedBox(height: 20.sp),
        _block(_blocks[i]),
      ],
    ];

    final children = <Widget>[
      NewsPublisherLine(news: news, style: AppTypography.textSmMedium),
      SizedBox(height: 10.sp),
      Semantics(
        header: true,
        child: Text(
          key: _headline,
          news.title,
          style: AppTypography.displayXsBold.copyWith(
            color: colors.textPrimary,
            height: 1.18,
            letterSpacing: -0.2,
          ),
        ),
      ),
      if (publisher.isPartner && webUri != null) ...[
        SizedBox(height: 4.sp),
        _ReadOriginalLink(
          publisher: publisher,
          onTap: () => _openExternal(webUri),
        ),
      ],
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
      ...body,
      if (publisher.isPartner) ...[
        if (webUri != null) ...[
          SizedBox(height: 32.sp),
          _ReadOriginalButton(
            publisher: publisher,
            onTap: () => _openExternal(webUri),
          ),
        ],
      ] else ...[
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
      ],
    ];

    return Scaffold(
      backgroundColor: colors.background,
      body: CustomScrollView(
        key: PageStorageKey('news_reader_${news.key}'),
        controller: _scroll,
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: colors.background,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            elevation: 0,
            automaticallyImplyLeading: false,
            toolbarHeight: _barHeight,
            titleSpacing: 8,
            leadingWidth: 56,
            centerTitle: true,
            title: _BarTitle(title: news.title, shown: _titleInBar),
            leading: IconButton(
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 20,
                color: colors.iconPrimary,
              ),
            ),
            actions: [
              Builder(
                builder: (buttonContext) => IconButton(
                  tooltip: 'Share article',
                  onPressed: () => shareNews(buttonContext, news),
                  constraints: const BoxConstraints(
                    minWidth: 52,
                    minHeight: 52,
                  ),
                  icon: FeedGlyph(
                    FeedGlyphs.share,
                    width: 20,
                    height: 20,
                    color: colors.iconPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
          if (news.imageUrl != null || widget.heroTag != null)
            SliverToBoxAdapter(
              child: _ReaderCover(
                imageUrl: news.imageUrl,
                aspectRatio: publisher.coverAspectRatio,
                heroTag: widget.heroTag,
              ),
            )
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

/// The headline, handed to the bar once the page's own headline has
/// scrolled under it. It rises out of the bar's lower edge, the way the
/// headline left, and sinks back when the headline returns.
class _BarTitle extends StatelessWidget {
  const _BarTitle({required this.title, required this.shown});

  final String title;
  final ValueListenable<bool> shown;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.textMdMedium.copyWith(
        color: context.colors.textPrimary,
      ),
    );
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return ValueListenableBuilder<bool>(
      valueListenable: shown,
      child: text,
      builder: (context, shown, text) => ExcludeSemantics(
        // The page's headline is already the article's heading.
        child: reduceMotion
            ? (shown ? text! : const SizedBox.shrink())
            : ClipRect(
                child: SingleMotionBuilder(
                  value: shown ? 1 : 0,
                  motion: const CupertinoMotion.smooth(
                    duration: Duration(milliseconds: 360),
                  ),
                  child: text,
                  // At rest below the bar the title is not built at all.
                  builder: (context, t, text) => t < 0.01
                      ? const SizedBox.shrink()
                      : Opacity(
                          opacity: t.clamp(0.0, 1.0),
                          child: Transform.translate(
                            offset: Offset(0, (1 - t) * 18),
                            child: text,
                          ),
                        ),
                ),
              ),
      ),
    );
  }
}

/// The cover under the bar: feathered at the top into the bar and at the
/// bottom into the page, so the headline rises out of the picture.
class _ReaderCover extends StatelessWidget {
  const _ReaderCover({required this.imageUrl, this.aspectRatio, this.heroTag});

  final String? imageUrl;
  final Object? heroTag;

  /// The cover's own shape, when it is known (a partner's); drawn at it the
  /// picture is whole. Otherwise the reader's band, cropped to fill.
  final double? aspectRatio;

  /// A cover that fails to load leaves quiet space, not the black brand
  /// slab (the reader follows the app theme, which may be light).
  static const Widget _quiet = SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final aspect = aspectRatio;
        final height = aspect == null
            ? (constraints.maxWidth * 0.62).clamp(180.0, 420.0)
            : (constraints.maxWidth / aspect).clamp(120.0, 420.0);
        return SizedBox(
          height: height,
          child: heroTag != null
              ? NewsHeroCover(
                  tag: heroTag!,
                  imageUrl: imageUrl,
                  fadeTop: 0.08,
                  fadeBottom: 0.45,
                )
              : reduceMotion
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

/// "Read original article", under a partner's headline: the article is
/// the partner's, and its own page is one tap away from the first screen.
class _ReadOriginalLink extends StatelessWidget {
  const _ReadOriginalLink({required this.publisher, required this.onTap});

  final NewsPublisher publisher;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = 'Read original article on ${publisher.name}';
    return Semantics(
      link: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  style: AppTypography.textSmMedium.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              NewsOutArrow(color: colors.textSecondary, size: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Read original article" at the foot of a partner's article, under the
/// partner's mark: the way on to the article on the partner's site.
class _ReadOriginalButton extends StatelessWidget {
  const _ReadOriginalButton({required this.publisher, required this.onTap});

  final NewsPublisher publisher;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mark = publisher.mark;
    return Semantics(
      link: true,
      label: 'Read original article on ${publisher.name}',
      excludeSemantics: true,
      child: NewsPressable(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.textPrimary,
            borderRadius: BorderRadius.circular(4),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  if (mark != null) ...[
                    Image.asset(
                      mark,
                      height: 20,
                      width: 20 * publisher.markAspectRatio,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      'Read original article',
                      style: AppTypography.textMdBold.copyWith(
                        color: colors.textInverse,
                      ),
                    ),
                  ),
                  NewsOutArrow(color: colors.textInverse, size: 14),
                ],
              ),
            ),
          ),
        ),
      ),
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
