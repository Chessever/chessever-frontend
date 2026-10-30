import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:chessever2/screens/feed/news/news_hero_cover.dart';
import 'package:chessever2/screens/feed/news/news_reader_pager.dart';
import 'package:chessever2/screens/feed/news/news_repository.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/hub_tile.dart' show hubGutter;
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

/// The web's news grid in the app: real covers, date, headline and summary.
/// Every card opens the native rich reader, in this same newest-first order.
class NewsScreen extends ConsumerStatefulWidget {
  const NewsScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/news'),
      builder: (_) => const NewsScreen(),
    ),
  );

  @override
  ConsumerState<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends ConsumerState<NewsScreen> {
  final _scroll = ScrollController();
  final _heroScope = Object();
  late NewsCatalogRepository _repository;
  final List<FeedNews> _items = [];
  Future<void>? _pending;
  bool _loading = false;
  bool _hasMore = true;
  bool _failed = false;
  bool _refreshing = false;
  int _columns = 1;
  double _rowExtent = 0;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _repository = ref.read(newsCatalogFactoryProvider)();
    _scroll.addListener(_nearEnd);
    unawaited(_loadNext());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _nearEnd() {
    if (_scroll.hasClients &&
        _scroll.position.extentAfter < 600 &&
        !_failed &&
        !_refreshing) {
      unawaited(_loadNext());
    }
  }

  Future<void> _loadNext() => _pending ??= _fetchNext().whenComplete(() {
    _pending = null;
  });

  Future<void> _fetchNext() async {
    if (!_hasMore) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await _repository.loadNext();
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _hasMore = page.hasMore;
      });
    } catch (error) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    // Finish any existing page before replacing its cursor.
    await _pending;
    if (!mounted) return;
    final fresh = ref.read(newsCatalogFactoryProvider)();
    try {
      final page = await fresh.loadNext();
      if (!mounted) return;
      setState(() {
        _repository = fresh;
        _items
          ..clear()
          ..addAll(page.items);
        _hasMore = page.hasMore;
        _failed = false;
      });
    } catch (error) {
      if (!mounted) return;
      // The last successful list stays usable when a refresh fails.
      showAppSnack(
        context,
        "Couldn't refresh news.",
        tone: AppSnackTone.danger,
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _revealCard(FeedNews article) {
    // Keep the current card mounted behind the reader for its return Hero.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final index = _items.indexWhere((item) => item.key == article.key);
      if (index < 0) return;
      final top = 16 + (index ~/ _columns) * _rowExtent;
      final position = _scroll.position;
      if (top < position.pixels ||
          top + _rowExtent > position.pixels + position.viewportDimension) {
        _scroll.jumpTo(top.clamp(0.0, position.maxScrollExtent));
      }
    });
  }

  Future<void> _open(int index) async {
    if (_opening) return;
    _opening = true;
    try {
      await NewsReaderPager.open(
        context,
        articles: List.of(_items),
        initialIndex: index,
        heroScope: _heroScope,
        hasMore: () => _hasMore,
        loadMore: () async {
          await _loadNext();
          if (_failed) throw StateError('News page unavailable');
          return List.of(_items);
        },
        onArticleChanged: _revealCard,
      );
    } catch (error) {
      if (mounted) {
        showAppSnack(
          context,
          "Couldn't open news. Try again.",
          tone: AppSnackTone.danger,
        );
      }
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(
          'News',
          style: AppTypography.textLgBold.copyWith(color: colors.textPrimary),
        ),
        backgroundColor: colors.background,
        foregroundColor: colors.iconPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: RefreshIndicator(
        color: colors.textPrimary,
        backgroundColor: colors.surface,
        onRefresh: _refresh,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (_items.isEmpty && !_loading)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _NewsMessage(
                  title: _failed ? "Couldn't load news" : 'No news yet',
                  detail: _failed
                      ? 'Check your connection and try again.'
                      : 'New stories will appear here. Pull down to refresh.',
                  action: _failed ? _loadNext : null,
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(hubGutter, 16, hubGutter, 0),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final layout = _NewsGridLayout(
                      constraints.crossAxisExtent,
                      MediaQuery.textScalerOf(context),
                    );
                    _columns = layout.columns;
                    _rowExtent = layout.height + layout.spacing;
                    final side =
                        (constraints.crossAxisExtent - layout.width) / 2;
                    return SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: side),
                      sliver: SliverGrid.builder(
                        // The first page loads into the same columns.
                        itemCount: _items.isEmpty
                            ? layout.columns * 2
                            : _items.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: layout.columns,
                          crossAxisSpacing: layout.spacing,
                          mainAxisSpacing: layout.spacing,
                          mainAxisExtent: layout.height,
                        ),
                        itemBuilder: (context, index) => _items.isEmpty
                            ? _NewsSkeleton(compact: layout.compact)
                            : _NewsCard(
                                key: ValueKey('news_card_${_items[index].key}'),
                                news: _items[index],
                                compact: layout.compact,
                                heroTag: (_heroScope, _items[index].key),
                                onTap: () => _open(index),
                              ),
                      ),
                    );
                  },
                ),
              ),
            if (_items.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    16,
                    20,
                    24 + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: Center(
                    child: _failed
                        ? _NewsMessage(
                            title: "Couldn't load more news",
                            action: _loadNext,
                          )
                        : _hasMore
                        ? TextButton(
                            onPressed: _loading || _refreshing
                                ? null
                                : _loadNext,
                            child: Text(
                              _loading ? 'Loading news…' : 'More news',
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Columns and one card size for the grid and its skeleton. Phones get two
/// columns, wide screens a third once cards reach 280. Large text on a narrow
/// phone keeps one column so headlines keep whole words.
class _NewsGridLayout {
  factory _NewsGridLayout(double extent, TextScaler scaler) {
    final width = math.min(extent, 1120.0);
    final columns = math
        .max((width / 280).floor(), width >= scaler.scale(240) + 60 ? 2 : 1)
        .clamp(1, 3);
    final compact = columns > 1 && (width - 12 * (columns - 1)) / columns < 280;
    final spacing = compact ? 12.0 : 20.0;
    final cardWidth = (width - spacing * (columns - 1)) / columns;
    // Reserve identical text slots across a row. Scaled text grows the grid
    // instead of clipping against a fixed tile.
    final height = compact
        ? cardWidth * 3 / 4 +
              24 +
              scaler.scale(15) * 1.3 * 4 +
              8 +
              scaler.scale(12) * 1.4
        : cardWidth * 9 / 16 +
              32 +
              scaler.scale(12) * 1.4 * 2 +
              10 +
              scaler.scale(18) * 1.3 * 3 +
              10 +
              scaler.scale(14) * 1.5 * 3;
    return _NewsGridLayout._(width, columns, compact, spacing, height);
  }

  const _NewsGridLayout._(
    this.width,
    this.columns,
    this.compact,
    this.spacing,
    this.height,
  );

  final double width;
  final int columns;
  final bool compact;
  final double spacing;
  final double height;
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({
    super.key,
    required this.news,
    required this.compact,
    required this.heroTag,
    required this.onTap,
  });

  final FeedNews news;

  /// A narrow grid card: headline under the cover, date on the bottom edge.
  final bool compact;
  final Object heroTag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final scaler = MediaQuery.textScalerOf(context);
    return Semantics(
      button: true,
      label:
          '${news.title}. ${formatNewsDate(news.publishedAt)}. ${news.summary}',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: compact ? 4 / 3 : 16 / 9,
                child: NewsHeroCover(
                  tag: heroTag,
                  imageUrl: news.imageUrl,
                  radius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(compact ? 12 : 16),
                  child: compact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              news.title,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.textMdBold.copyWith(
                                fontSize: 15,
                                height: 1.3,
                                color: colors.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              DateFormat(
                                'MMM d, y',
                              ).format(news.publishedAt.toLocal()),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.textXsMedium.copyWith(
                                fontSize: 12,
                                height: 1.4,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: scaler.scale(12) * 1.4 * 2,
                              child: Text(
                                formatNewsDate(news.publishedAt),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.textXsMedium.copyWith(
                                  fontSize: 12,
                                  height: 1.4,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: scaler.scale(18) * 1.3 * 3,
                              child: Text(
                                news.title,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.textLgBold.copyWith(
                                  fontSize: 18,
                                  height: 1.3,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: scaler.scale(14) * 1.5 * 3,
                              child: Text(
                                news.summary,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.textSmRegular.copyWith(
                                  fontSize: 14,
                                  height: 1.5,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ),
                          ],
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

class _NewsMessage extends StatelessWidget {
  const _NewsMessage({required this.title, this.detail, this.action});
  final String title;
  final String? detail;
  final VoidCallback? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: AppTypography.textLgBold.copyWith(
            color: context.colors.textPrimary,
          ),
        ),
        if (detail != null) ...[
          const SizedBox(height: 8),
          Text(
            detail!,
            textAlign: TextAlign.center,
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ],
        if (action != null) ...[
          const SizedBox(height: 12),
          TextButton(onPressed: action, child: const Text('Try again')),
        ],
      ],
    ),
  );
}

class _NewsSkeleton extends StatelessWidget {
  const _NewsSkeleton({required this.compact});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget bar(double widthFactor) => FractionallySizedBox(
      widthFactor: widthFactor,
      child: SizedBox(
        height: compact ? 14 : 18,
        child: ColoredBox(color: colors.skeleton),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: colors.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: compact ? 4 / 3 : 16 / 9,
              child: ColoredBox(color: colors.skeleton),
            ),
            Padding(
              padding: EdgeInsets.all(compact ? 12 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [bar(0.9), const SizedBox(height: 8), bar(0.6)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
