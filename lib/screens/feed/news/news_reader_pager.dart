import 'dart:async';

import 'package:chessever2/screens/feed/news/news_models.dart';
import 'package:chessever2/screens/feed/news/news_reader_screen.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';

/// Horizontal article browsing, with independent vertical reading positions.
/// Only the visible page owns a Hero, even while PageView builds neighbours.
class NewsReaderPager extends StatefulWidget {
  const NewsReaderPager({
    super.key,
    required this.articles,
    required this.initialIndex,
    required this.heroScope,
    this.hasMore,
    this.loadMore,
    this.onArticleChanged,
  }) : assert(initialIndex >= 0 && initialIndex < articles.length);

  final List<FeedNews> articles;
  final int initialIndex;
  final Object heroScope;
  final bool Function()? hasMore;
  final Future<List<FeedNews>> Function()? loadMore;
  final ValueChanged<FeedNews>? onArticleChanged;

  static Future<void> open(
    BuildContext context, {
    required List<FeedNews> articles,
    required int initialIndex,
    required Object heroScope,
    bool Function()? hasMore,
    Future<List<FeedNews>> Function()? loadMore,
    ValueChanged<FeedNews>? onArticleChanged,
  }) {
    unawaited(HapticFeedbackService.cardTap());
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: '/news/${articles[initialIndex].key}'),
        builder: (_) => NewsReaderPager(
          articles: articles,
          initialIndex: initialIndex,
          heroScope: heroScope,
          hasMore: hasMore,
          loadMore: loadMore,
          onArticleChanged: onArticleChanged,
        ),
      ),
    );
  }

  @override
  State<NewsReaderPager> createState() => _NewsReaderPagerState();
}

class _NewsReaderPagerState extends State<NewsReaderPager> {
  late final PageController _pages;
  late List<FeedNews> _articles;
  late int _index;
  bool _loading = false;
  bool _loadFailed = false;

  bool get _more =>
      widget.loadMore != null && (widget.hasMore?.call() ?? false);

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _articles = List.of(widget.articles);
    _pages = PageController(initialPage: _index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _prefetch();
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _prefetch() {
    if (!_loadFailed && _index >= _articles.length - 2 && _more) {
      unawaited(_loadNext());
    }
  }

  Future<void> _loadNext() async {
    if (_loading || !_more) return;
    setState(() => _loading = true);
    try {
      final articles = await widget.loadMore!();
      if (!mounted) return;
      setState(() {
        _articles = List.of(articles);
        _loadFailed = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadFailed = true);
      showAppSnack(
        context,
        "Couldn't load more news. Tap Next article to retry.",
        tone: AppSnackTone.danger,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _next() async {
    if (_index == _articles.length - 1) await _loadNext();
    if (!mounted || _index >= _articles.length - 1) return;
    _goTo(_index + 1);
  }

  void _goTo(int index) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(index);
    } else {
      unawaited(
        _pages.animateToPage(
          index,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => PageView.builder(
    controller: _pages,
    itemCount: _articles.length,
    onPageChanged: (index) {
      setState(() => _index = index);
      widget.onArticleChanged?.call(_articles[index]);
      _prefetch();
    },
    itemBuilder: (context, index) {
      final article = _articles[index];
      return HeroMode(
        enabled: index == _index,
        child: NewsReaderScreen(
          key: ValueKey(article.key),
          news: article,
          heroTag: (widget.heroScope, article.key),
          navigation: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Previous article',
                onPressed: index > 0 ? () => _goTo(index - 1) : null,
                color: context.colors.iconPrimary,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Flexible(
                child: Semantics(
                  liveRegion: index == _index,
                  label: 'Article ${index + 1} of ${_articles.length}',
                  excludeSemantics: true,
                  child: Text(
                    '${index + 1} / ${_articles.length}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.textSmMedium.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: _loadFailed && index == _articles.length - 1
                    ? 'Retry next article'
                    : 'Next article',
                onPressed: _loading && index == _articles.length - 1
                    ? null
                    : index < _articles.length - 1 || _more
                    ? _next
                    : null,
                color: context.colors.iconPrimary,
                icon: _loading && index == _articles.length - 1
                    ? SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.colors.textSecondary,
                        ),
                      )
                    : const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
      );
    },
  );
}
