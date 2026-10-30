import 'dart:async';

import 'package:chessever2/screens/feed/models/feed_entry.dart';
import 'package:chessever2/screens/feed/news/news_models.dart';
import 'package:chessever2/screens/feed/news/news_content.dart';
import 'package:chessever2/screens/feed/news/news_reader_screen.dart';
import 'package:chessever2/screens/feed/providers/feed_entries_provider.dart';
import 'package:chessever2/screens/feed/widgets/feed_ad_page.dart';
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

/// Horizontal browsing with upward footer transitions and independent reading positions.
/// Ads use Feed's placement and eligibility, only inside the reader.
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
  late List<FeedEntry> _entries;
  late int _index;
  final _withdrawn = <String>{};
  Future<void>? _pending;
  bool _advancing = false;
  bool _footerAdvance = false;
  bool _repositioning = false;
  int _revision = 0;

  bool get _more =>
      widget.loadMore != null && (widget.hasMore?.call() ?? false);

  List<FeedEntry> _compose() {
    final posts = [for (final article in _articles) FeedNewsEntry(article)];
    return ref.read(feedAdsVisibleProvider)
        ? withFeedAds(posts, withdrawn: _withdrawn)
        : posts;
  }

  @override
  void initState() {
    super.initState();
    _articles = List.of(widget.articles);
    _entries = _compose();
    _index = _entries.indexWhere(
      (entry) => entry.key == FeedNewsEntry(_articles[widget.initialIndex]).key,
    );
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
    if (feedPostIndexAt(_entries, _index) >= _articles.length - 2 && _more) {
      unawaited(_loadNext());
    }
  }

  Future<void> _loadNext() => _pending ??= _fetchNext().whenComplete(() {
    _pending = null;
  });

  Future<void> _fetchNext() async {
    if (!_more) return;
    try {
      final articles = await widget.loadMore!();
      if (!mounted) return;
      _articles = List.of(articles);
      _replacePages();
    } catch (error) {
      if (!mounted) return;
      showAppSnack(
        context,
        "Couldn't load more news.",
        tone: AppSnackTone.danger,
        actionLabel: 'Retry',
        onAction: _loadNext,
      );
    }
  }

  /// Keep the current article and its reading position when an ad joins or
  /// leaves. If the current ad fails, land on the article immediately after it.
  void _replacePages() {
    final next = _compose();
    if (next.isEmpty) return;
    final before = _entries;
    final previousIndex = _index;
    final previousKey = before[_index].key;
    var target = next.indexWhere((entry) => entry.key == previousKey);
    for (var i = _index + 1; target < 0 && i < before.length; i++) {
      target = next.indexWhere((entry) => entry.key == before[i].key);
    }
    if (target < 0) target = _index.clamp(0, next.length - 1);
    final arrived = next[target].key != previousKey;
    final reposition = _repositioning || target != previousIndex || arrived;
    final revision = ++_revision;
    setState(() {
      _entries = next;
      _index = target;
      _repositioning = reposition;
    });
    if (!reposition) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || revision != _revision) return;
      if (_pages.hasClients) _pages.jumpToPage(_index);
      setState(() => _repositioning = false);
      if (arrived) _reportArticle();
    });
  }

  void _withdraw(FeedAdEntry entry) {
    if (!mounted || !_withdrawn.add(entry.key)) return;
    _replacePages();
  }

  void _reportArticle() {
    if (_entries[_index] case FeedNewsEntry(:final news)) {
      widget.onArticleChanged?.call(news);
    }
    _prefetch();
  }

  void _pageChanged(int index) {
    if (_repositioning || index == _index) return;
    setState(() => _index = index);
    _reportArticle();
  }

  Future<void> _next(String from) async {
    if (_advancing || _repositioning || _entries[_index].key != from) return;
    _advancing = true;
    try {
      if (_index == _entries.length - 1 && _more) await _loadNext();
      if (!mounted ||
          !_pages.hasClients ||
          _entries[_index].key != from ||
          _index >= _entries.length - 1) {
        return;
      }
      if (MediaQuery.disableAnimationsOf(context)) {
        _pages.jumpToPage(_index + 1);
      } else {
        // Match the upward pull without taking vertical drags away from the
        // article's own scroll view during normal reading.
        setState(() => _footerAdvance = true);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || !_pages.hasClients) return;
        await _pages.animateToPage(
          _index + 1,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
        );
      }
    } finally {
      _advancing = false;
      if (mounted && _footerAdvance) {
        setState(() => _footerAdvance = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(feedAdsVisibleProvider, (_, _) => _replacePages());
    return PageView.builder(
      scrollDirection: _footerAdvance ? Axis.vertical : Axis.horizontal,
      controller: _pages,
      // Match Feed: prepare the next article or ad before the swipe lands.
      allowImplicitScrolling: true,
      itemCount: _entries.length,
      onPageChanged: _pageChanged,
      findChildIndexCallback: (key) {
        final index = _entries.indexWhere(
          (entry) => ValueKey(entry.key) == key,
        );
        return index < 0 ? null : index;
      },
      itemBuilder: (context, index) {
        final entry = _entries[index];
        if (entry is FeedAdEntry) {
          return Scaffold(
            key: ValueKey(entry.key),
            backgroundColor: context.colors.background,
            appBar: AppBar(
              title: Text('News', style: AppTypography.textMdMedium),
              centerTitle: true,
              toolbarHeight: 52,
              backgroundColor: context.colors.background,
              foregroundColor: context.colors.iconPrimary,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              leading: BackButton(
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            body: SafeArea(
              top: false,
              child: FeedAdPage(
                entry: entry,
                onUnavailable: () => _withdraw(entry),
                returnTo: 'news/reader',
              ),
            ),
          );
        }
        final article = (entry as FeedNewsEntry).news;
        final canAdvance = index < _entries.length - 1 || _more;
        return HeroMode(
          key: ValueKey(entry.key),
          enabled: index == _index,
          child: NewsReaderScreen(
            key: ValueKey(article.key),
            news: article,
            heroTag: (widget.heroScope, article.key),
            onNext: canAdvance ? () => _next(entry.key) : null,
            nextIsAd:
                index + 1 < _entries.length &&
                _entries[index + 1] is FeedAdEntry,
          ),
        );
      },
    );
  }
}
