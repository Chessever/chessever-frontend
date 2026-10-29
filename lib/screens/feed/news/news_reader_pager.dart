import 'dart:async';

import 'package:chessever2/screens/feed/news/news_models.dart';
import 'package:chessever2/screens/feed/news/news_content.dart';
import 'package:chessever2/screens/feed/news/news_reader_screen.dart';
import 'package:chessever2/screens/feed/news/news_reading_access.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final _newsNavigationProvider = Provider((ref) => _NewsNavigation());

class _NewsNavigation {
  bool pending = false;
}

/// Horizontal article browsing, with independent vertical reading positions.
/// Only the visible page owns a Hero, even while PageView builds neighbours.
class NewsReaderPager extends ConsumerStatefulWidget {
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
  }) async {
    if (!context.mounted) return;
    final navigation = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(_newsNavigationProvider);
    if (navigation.pending) return;
    navigation.pending = true;
    try {
      if (!await requestNewsArticleAccess(
            context,
            articles[initialIndex].key,
          ) ||
          !context.mounted) {
        return;
      }
      unawaited(HapticFeedbackService.cardTap());
      final closed = Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          settings: RouteSettings(
            name: Uri.parse(newsShareUrl(articles[initialIndex])).path,
          ),
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
      // Lock the originating tap until the new route owns the next frame.
      // Links inside the reader remain usable while that route is open.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => navigation.pending = false,
      );
      await closed;
    } finally {
      navigation.pending = false;
    }
  }

  @override
  ConsumerState<NewsReaderPager> createState() => _NewsReaderPagerState();
}

class _NewsReaderPagerState extends ConsumerState<NewsReaderPager> {
  late final PageController _pages;
  late List<FeedNews> _articles;
  late int _index;
  bool _loading = false;
  bool _loadFailed = false;
  bool _changing = false;
  bool _ready = false;

  bool get _more =>
      widget.loadMore != null && (widget.hasMore?.call() ?? false);

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _articles = List.of(widget.articles);
    _pages = PageController(initialPage: _index);
    _ready = ref
        .read(newsReadingAccessProvider)
        .canRead(
          _articles[_index].key,
          hasPremium: ref.read(premiumAccessProvider),
        );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_startReading());
    });
  }

  Future<void> _startReading() async {
    final allowed = await _approve(_index);
    if (!mounted) return;
    if (!allowed) {
      unawaited(Navigator.of(context).maybePop());
      return;
    }
    setState(() => _ready = true);
    _prefetch();
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
    if (_changing) return;
    if (_index == _articles.length - 1) await _loadNext();
    if (!mounted || _index >= _articles.length - 1) return;
    await _goTo(_index + 1);
  }

  Future<void> _goTo(int index) async {
    if (_changing || !await _approve(index) || !mounted) return;
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

  Future<bool> _approve(int index) async {
    setState(() => _changing = true);
    try {
      return await requestNewsArticleAccess(context, _articles[index].key);
    } catch (error) {
      if (mounted) {
        showAppSnack(
          context,
          "Couldn't check news access. Try again.",
          tone: AppSnackTone.danger,
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  Future<void> _pageChanged(int index) async {
    if (index == _index || _changing) return;
    final allowed = await _approve(index);
    if (!mounted) return;
    if (!allowed) {
      _pages.jumpToPage(_index);
      return;
    }
    setState(() => _index = index);
    widget.onArticleChanged?.call(_articles[index]);
    _prefetch();
  }

  @override
  Widget build(BuildContext context) {
    final premium = ref.watch(premiumAccessProvider);
    final access = ref.read(newsReadingAccessProvider);
    return PageView.builder(
      controller: _pages,
      physics: _changing ? const NeverScrollableScrollPhysics() : null,
      itemCount: _articles.length,
      onPageChanged: (index) => unawaited(_pageChanged(index)),
      itemBuilder: (context, index) {
        final article = _articles[index];
        // PageView builds neighbours before a swipe is accepted. Keep a gated
        // article's body out of that preview, including during a fast swipe.
        if (!_ready || !access.canRead(article.key, hasPremium: premium)) {
          return Scaffold(
            backgroundColor: context.colors.background,
            body: Center(
              child: CircularProgressIndicator(
                color: context.colors.textSecondary,
              ),
            ),
          );
        }
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
                  onPressed: !_changing && index > 0
                      ? () => _goTo(index - 1)
                      : null,
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
                  onPressed:
                      _changing || (_loading && index == _articles.length - 1)
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
}
