import 'dart:async';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/gamebase/models/gamebase_game.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/miniatures/providers/miniatures_provider.dart';
import 'package:chessever2/screens/miniatures/widgets/miniature_game_card.dart';
import 'package:chessever2/screens/miniatures/widgets/miniatures_filter_sheet.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/widgets/liquid_glass/glass_kit.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

typedef MiniatureOpenCallback =
    FutureOr<void> Function(GamebaseMiniature miniature);
typedef MiniaturesPremiumAccessCallback = FutureOr<bool> Function();

class MiniaturesScreen extends ConsumerStatefulWidget {
  const MiniaturesScreen({
    super.key,
    this.onOpenMiniature,
    this.onRequirePremiumFeature,
  });

  /// Test and embedding seam. Production callers normally leave this null so
  /// the screen hydrates the canonical Gamebase game before opening Board.
  final MiniatureOpenCallback? onOpenMiniature;

  /// Optional capability seam for hosts that already performed an
  /// authoritative premium check. Browsing and opening remain free.
  final MiniaturesPremiumAccessCallback? onRequirePremiumFeature;

  @override
  ConsumerState<MiniaturesScreen> createState() => _MiniaturesScreenState();
}

class _MiniaturesScreenState extends ConsumerState<MiniaturesScreen> {
  static const _searchDebounce = Duration(milliseconds: 350);

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final Set<String> _openingGameIds = <String>{};

  Timer? _searchTimer;
  bool _searchExpanded = false;
  MiniatureGamesFilter _uiFilter = kDefaultMiniaturesFilter;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels <= 560) {
      unawaited(ref.read(miniaturesProvider.notifier).loadMore());
    }
  }

  void _onSearchChanged(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(_searchDebounce, () {
      if (!mounted) return;
      unawaited(_applySearch(value));
    });
  }

  Future<void> _applySearch(String value) async {
    final normalized = value.trim();
    final current = _uiFilter.search?.trim() ?? '';
    if (normalized == current) return;

    final next = copyMiniaturesFilter(
      _uiFilter,
      search: normalized.isEmpty ? null : normalized,
      clearSearch: normalized.isEmpty,
    );
    await _replaceFilter(next);
  }

  void _clearSearch() {
    _searchTimer?.cancel();
    if (_searchController.text.isNotEmpty) _searchController.clear();
    unawaited(_applySearch(''));
  }

  void _onSearchExpandedChanged(bool expanded) {
    if (!expanded) {
      if (mounted) setState(() => _searchExpanded = false);
      return;
    }
    unawaited(_enableSearch());
  }

  Future<void> _enableSearch() async {
    if (!await _requestPremiumFeature() || !mounted) return;
    setState(() => _searchExpanded = true);
  }

  Future<bool> _requestPremiumFeature() async {
    final callback = widget.onRequirePremiumFeature;
    if (callback != null) return await callback();
    return requirePremiumGuard(context, ref);
  }

  Future<void> _showFilters() async {
    if (!await _requestPremiumFeature() || !mounted) return;
    final next = await showMiniaturesFilterSheet(
      context: context,
      currentFilter: _uiFilter,
    );
    if (next == null || !mounted) return;
    await _replaceFilter(next);
  }

  Future<void> _selectWindow(MiniatureGamesWindow window) async {
    if (window == _uiFilter.window) return;
    final next = copyMiniaturesFilter(_uiFilter, window: window);
    await _replaceFilter(next);
  }

  Future<void> _resetFilters() async {
    _searchTimer?.cancel();
    _searchController.clear();
    final next = resetMiniaturesFilter(_uiFilter);
    await _replaceFilter(next);
  }

  Future<void> _replaceFilter(MiniatureGamesFilter next) async {
    if (mounted) {
      setState(() => _uiFilter = next);
    } else {
      _uiFilter = next;
    }
    try {
      await ref.read(miniaturesProvider.notifier).replaceFilter(next);
    } catch (_) {
      // The provider owns the visible cold-error state. Event callbacks catch
      // here so a failed replacement does not become an unhandled zone error.
    }
  }

  Future<void> _openMiniature(GamebaseMiniature miniature) async {
    final gameId = miniature.canonicalGameId;
    if (!_openingGameIds.add(gameId)) return;
    if (mounted) setState(() {});

    try {
      final callback = widget.onOpenMiniature;
      if (callback != null) {
        await callback(miniature);
      } else {
        await _hydrateAndOpenMiniature(miniature);
      }
    } on _MiniatureOpenException catch (error) {
      _showOpenFailure(error.message);
    } catch (_) {
      _showOpenFailure('Could not load the complete game. Try again.');
    } finally {
      _openingGameIds.remove(gameId);
      if (mounted) setState(() {});
    }
  }

  Future<void> _hydrateAndOpenMiniature(GamebaseMiniature miniature) async {
    final fullGame = await ref
        .read(gamebaseRepositoryProvider)
        .getGameWithPgn(miniature.canonicalGameId);
    if (fullGame == null) {
      throw const _MiniatureOpenException(
        'The complete game is unavailable right now. Try again.',
      );
    }

    final builtPgn = buildPgnFromGamebaseData(fullGame.data);
    String? playablePgn;
    for (final candidate in <String?>[fullGame.pgn, builtPgn]) {
      final normalized = candidate?.trim();
      if (normalized != null &&
          normalized.isNotEmpty &&
          pgnHasMoves(normalized)) {
        playablePgn = normalized;
        break;
      }
    }
    if (playablePgn == null) {
      throw const _MiniatureOpenException(
        'This miniature has no complete move record, so it cannot be opened.',
      );
    }
    if (!mounted) return;

    final boardGame = _toBoardGame(
      miniature: miniature,
      fullGame: fullGame,
      pgn: playablePgn,
    );
    ref
        .read(gameCardWrapperProvider)
        .navigateToChessBoard(
          context: context,
          orderedGames: <GamesTourModel>[boardGame],
          gameIndex: 0,
          onReturnFromChessboard: (_) {},
          viewSource: ChessboardView.tour,
          hideEventInfo: true,
          showGamebaseButton: false,
          disableGamebaseOverlayByDefault: true,
          showClock: false,
        );
  }

  void _showOpenFailure(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: context.colors.surfaceElevated,
          action: SnackBarAction(
            label: 'Dismiss',
            textColor: context.colors.brand,
            onPressed: () {},
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(miniaturesProvider);
    final miniatures = asyncState.valueOrNull;
    if (miniatures != null && !asyncState.isLoading) {
      _uiFilter = miniatures.filter;
    }

    final activeFilterCount = miniaturesAdvancedFilterCount(_uiFilter);
    final title =
        miniatures == null || miniatures.total == 0
            ? 'Miniatures'
            : 'Miniatures · ${miniatures.total}';

    return GlassFullScreenPage(
      key: const ValueKey<String>('miniatures-full-screen-page'),
      backgroundColor: context.colors.background,
      contentPadding: const EdgeInsets.only(top: 116, bottom: 8),
      topOverlayPadding: const EdgeInsets.only(top: 4),
      topOverlay: GlassIslandStack(
        key: const ValueKey<String>('miniatures-floating-controls'),
        includeStatusBar: false,
        gap: 6,
        children: [
          GlassIslandTopBar(
            topPadding: 0,
            height: 48,
            leading: const GlassBackButton(
              semanticLabel: 'Back from miniatures',
            ),
            title:
                _searchExpanded
                    ? null
                    : GlassTitleChip(label: title, maxWidth: 132),
            center: Semantics(
              label:
                  _searchExpanded
                      ? 'Search miniatures field'
                      : 'Search miniatures',
              button: !_searchExpanded,
              textField: _searchExpanded,
              child: GlassIslandSearch(
                controller: _searchController,
                focusNode: _searchFocusNode,
                expanded: _searchExpanded,
                onExpandedChanged: _onSearchExpandedChanged,
                hintText: 'Player, event, opening, ECO',
                onChanged: _onSearchChanged,
                onSubmitted: (value) {
                  _searchTimer?.cancel();
                  unawaited(_applySearch(value));
                },
                onClear: _clearSearch,
                textFieldKey: const ValueKey<String>(
                  'miniatures-search-control',
                ),
              ),
            ),
            trailing: [
              MiniaturesFilterButton(
                activeCount: activeFilterCount,
                onPressed: () => unawaited(_showFilters()),
              ),
            ],
          ),
          MiniaturesWindowBar(
            selected: _uiFilter.window,
            onSelected: (window) => unawaited(_selectWindow(window)),
          ),
        ],
      ),
      content: AnimatedSwitcher(
        key: const ValueKey<String>('miniatures-state-switcher'),
        duration: GlassMotion.resolveDuration(
          context,
          const Duration(milliseconds: 180),
        ),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: _buildContent(asyncState, miniatures),
      ),
    );
  }

  Widget _buildContent(
    AsyncValue<MiniaturesState> asyncState,
    MiniaturesState? miniatures,
  ) {
    if (miniatures != null && miniatures.items.isNotEmpty) {
      return _MiniaturesFeed(
        key: const ValueKey<String>('miniatures-data-state'),
        controller: _scrollController,
        state: miniatures,
        openingGameIds: _openingGameIds,
        onRefresh: () => ref.read(miniaturesProvider.notifier).refresh(),
        onLoadMore: () => ref.read(miniaturesProvider.notifier).loadMore(),
        onOpen: (miniature) => unawaited(_openMiniature(miniature)),
      );
    }

    if (miniatures != null) {
      final hasRefinement =
          miniaturesHasSearch(miniatures.filter) ||
          miniaturesAdvancedFilterCount(miniatures.filter) > 0;
      final hasNarrowWindow =
          miniatures.filter.window != MiniatureGamesWindow.all;
      return _MiniaturesMessageState(
        key: const ValueKey<String>('miniatures-empty-state'),
        icon: CupertinoIcons.square_grid_2x2,
        title: hasRefinement ? 'No matching miniatures' : 'No miniatures here',
        message:
            hasRefinement
                ? 'Try a broader search or reset the active filters.'
                : hasNarrowWindow
                ? 'No qualifying games were found in this time window.'
                : 'Gamebase has no qualifying miniatures available right now.',
        actionLabel:
            hasRefinement
                ? 'Reset filters'
                : hasNarrowWindow
                ? 'Show all time'
                : 'Refresh miniatures',
        onAction:
            hasRefinement
                ? () => unawaited(_resetFilters())
                : hasNarrowWindow
                ? () => unawaited(_selectWindow(MiniatureGamesWindow.all))
                : () => ref.invalidate(miniaturesProvider),
      );
    }

    if (asyncState.hasError) {
      return _MiniaturesMessageState(
        key: const ValueKey<String>('miniatures-cold-error-state'),
        icon: CupertinoIcons.exclamationmark_triangle,
        title: 'Miniatures could not load',
        message:
            'Check your connection and retry. No local placeholder games are shown.',
        actionLabel: 'Retry miniatures',
        onAction: () => ref.invalidate(miniaturesProvider),
        isError: true,
      );
    }

    return const _MiniaturesLoadingState(
      key: ValueKey<String>('miniatures-loading-state'),
    );
  }
}

class _MiniaturesFeed extends StatelessWidget {
  const _MiniaturesFeed({
    required this.controller,
    required this.state,
    required this.openingGameIds,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onOpen,
    super.key,
  });

  final ScrollController controller;
  final MiniaturesState state;
  final Set<String> openingGameIds;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;
  final ValueChanged<GamebaseMiniature> onOpen;

  @override
  Widget build(BuildContext context) {
    final groups = _dateGroups(state.items);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1120 ? 3 : (width >= 700 ? 2 : 1);
        final horizontalPadding = width >= 700 ? 24.0 : 14.0;

        return RefreshIndicator.adaptive(
          onRefresh: onRefresh,
          color: context.colors.brand,
          child: CustomScrollView(
            key: const PageStorageKey<String>('miniatures-feed'),
            controller: controller,
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  12,
                  horizontalPadding,
                  4,
                ),
                sliver: SliverToBoxAdapter(
                  child: _MiniaturesSummary(state: state),
                ),
              ),
              for (final group in groups) ...[
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    18,
                    horizontalPadding,
                    10,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Semantics(
                      header: true,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              group.label,
                              style: AppTypography.textMdBold.copyWith(
                                color: context.colors.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            '${group.items.length}',
                            style: AppTypography.textSmMedium.copyWith(
                              color: context.colors.textSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    0,
                    horizontalPadding,
                    2,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, rowIndex) {
                      final firstIndex = rowIndex * columns;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (
                              var column = 0;
                              column < columns;
                              column++
                            ) ...[
                              if (column > 0) const SizedBox(width: 12),
                              Expanded(
                                child:
                                    firstIndex + column < group.items.length
                                        ? _buildCard(
                                          context,
                                          group.items[firstIndex + column],
                                        )
                                        : const SizedBox.shrink(),
                              ),
                            ],
                          ],
                        ),
                      );
                    }, childCount: (group.items.length / columns).ceil()),
                  ),
                ),
              ],
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  10,
                  horizontalPadding,
                  28,
                ),
                sliver: SliverToBoxAdapter(
                  child: _MiniaturesPaginationFooter(
                    state: state,
                    onLoadMore: onLoadMore,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCard(BuildContext context, GamebaseMiniature miniature) {
    return MiniatureGameCard(
      key: ValueKey<String>('miniature-card-${miniature.canonicalGameId}'),
      miniature: miniature,
      isOpening: openingGameIds.contains(miniature.canonicalGameId),
      onTap: () => onOpen(miniature),
    );
  }
}

class _MiniaturesSummary extends StatelessWidget {
  const _MiniaturesSummary({required this.state});

  final MiniaturesState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Decisive by move 25',
          style: AppTypography.displayXsBold.copyWith(
            color: context.colors.textPrimary,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '${state.total} qualifying games, ${_sortDescription(state.filter)}. Complete moves load before the board opens.',
          style: AppTypography.textSmRegular.copyWith(
            color: context.colors.textSecondary,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _MiniaturesPaginationFooter extends StatelessWidget {
  const _MiniaturesPaginationFooter({
    required this.state,
    required this.onLoadMore,
  });

  final MiniaturesState state;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context) {
    final failure = state.loadMoreFailure;
    if (failure != null) {
      return Semantics(
        liveRegion: true,
        child: Material(
          key: const ValueKey<String>('miniatures-pagination-error'),
          color: context.colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: context.colors.divider),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.exclamationmark_circle,
                  color: context.colors.danger,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'More games could not load',
                        style: AppTypography.textSmBold.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Your loaded miniatures are still available.',
                        style: AppTypography.textXsRegular.copyWith(
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  key: const ValueKey<String>('miniatures-pagination-retry'),
                  onPressed: () => unawaited(onLoadMore()),
                  style: TextButton.styleFrom(minimumSize: const Size(72, 48)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (state.isLoadingMore) {
      return Semantics(
        label: 'Loading more miniatures',
        liveRegion: true,
        child: const SizedBox(
          key: ValueKey<String>('miniatures-pagination-loading'),
          height: 56,
          child: Center(child: CupertinoActivityIndicator()),
        ),
      );
    }

    if (state.hasMore) {
      return Center(
        child: OutlinedButton.icon(
          key: const ValueKey<String>('miniatures-load-more'),
          onPressed: () => unawaited(onLoadMore()),
          style: OutlinedButton.styleFrom(minimumSize: const Size(210, 48)),
          icon: const Icon(CupertinoIcons.arrow_down_circle, size: 19),
          label: const Text('Load more miniatures'),
        ),
      );
    }

    return Semantics(
      label: 'All ${state.items.length} loaded miniatures are shown',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'All ${state.items.length} loaded miniatures are shown',
          textAlign: TextAlign.center,
          style: AppTypography.textXsMedium.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _MiniaturesMessageState extends StatelessWidget {
  const _MiniaturesMessageState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    super.key,
    this.isError = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(18, 48, 18, 32),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - 100).clamp(
                0,
                double.infinity,
              ),
            ),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 430),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.colors.divider),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 38,
                      color:
                          isError
                              ? context.colors.danger
                              : context.colors.iconSecondary,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: AppTypography.textLgBold.copyWith(
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: AppTypography.textSmRegular.copyWith(
                        color: context.colors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      key: const ValueKey<String>('miniatures-state-action'),
                      onPressed: onAction,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(210, 48),
                        backgroundColor: context.colors.brand,
                        foregroundColor: context.colors.textInverse,
                      ),
                      child: Text(actionLabel),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MiniaturesLoadingState extends StatelessWidget {
  const _MiniaturesLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Miniatures loading',
      liveRegion: true,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 700 ? 2 : 1;
            final rows = columns == 1 ? 4 : 2;
            return ListView.builder(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 24),
              itemCount: rows,
              itemBuilder: (context, row) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      for (var column = 0; column < columns; column++) ...[
                        if (column > 0) const SizedBox(width: 12),
                        Expanded(
                          child: _SkeletonCard(index: row * columns + column),
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    Widget line(double width, double height) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: context.colors.skeleton,
          borderRadius: BorderRadius.circular(6),
        ),
      );
    }

    return Container(
      key: ValueKey<String>('miniatures-skeleton-$index'),
      height: 206,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          line(124, 12),
          const SizedBox(height: 18),
          line(double.infinity, 18),
          const SizedBox(height: 12),
          line(double.infinity, 18),
          const SizedBox(height: 18),
          line(190, 14),
          const Spacer(),
          Row(children: [line(76, 28), const SizedBox(width: 8), line(62, 28)]),
        ],
      ),
    );
  }
}

class _MiniatureDateGroup {
  const _MiniatureDateGroup({
    required this.key,
    required this.label,
    required this.items,
  });

  final String key;
  final String label;
  final List<GamebaseMiniature> items;
}

List<_MiniatureDateGroup> _dateGroups(List<GamebaseMiniature> items) {
  final grouped = <String, List<GamebaseMiniature>>{};
  final labels = <String, String>{};
  for (final item in items) {
    final date = item.date?.toLocal();
    final key = date == null ? 'unknown' : _dayKey(date);
    grouped.putIfAbsent(key, () => <GamebaseMiniature>[]).add(item);
    labels.putIfAbsent(key, () => _dateGroupLabel(date));
  }
  return [
    for (final entry in grouped.entries)
      _MiniatureDateGroup(
        key: entry.key,
        label: labels[entry.key]!,
        items: List<GamebaseMiniature>.unmodifiable(entry.value),
      ),
  ];
}

String _dayKey(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

String _dateGroupLabel(DateTime? value) {
  if (value == null) return 'Date unavailable';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(value.year, value.month, value.day);
  final difference = today.difference(day).inDays;
  if (difference == 0) return 'Today';
  if (difference == 1) return 'Yesterday';
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[value.month - 1]} ${value.day}, ${value.year}';
}

String _sortDescription(MiniatureGamesFilter filter) {
  final direction =
      filter.order == MiniatureGamesSortOrder.desc ? 'first' : 'last';
  return switch (filter.sort) {
    MiniatureGamesSort.recent =>
      filter.order == MiniatureGamesSortOrder.desc
          ? 'newest first'
          : 'oldest first',
    MiniatureGamesSort.rating => 'strongest $direction',
    MiniatureGamesSort.moves =>
      filter.order == MiniatureGamesSortOrder.asc
          ? 'quickest wins first'
          : 'longest wins first',
  };
}

GamesTourModel _toBoardGame({
  required GamebaseMiniature miniature,
  required GamebaseGameWithPgn fullGame,
  required String pgn,
}) {
  final whiteName =
      _firstText(<String?>[fullGame.whiteName, miniature.whiteName]) ?? 'White';
  final blackName =
      _firstText(<String?>[fullGame.blackName, miniature.blackName]) ?? 'Black';
  final event =
      _firstText(<String?>[fullGame.event, miniature.event]) ?? 'Miniatures';
  final eco = _firstText(<String?>[fullGame.eco, miniature.eco]);
  final opening = _combinedOpening(
    opening: _firstText(<String?>[fullGame.opening, miniature.opening]),
    variation: _firstText(<String?>[fullGame.variation, miniature.variation]),
  );
  final whiteRating = _safeRating(fullGame.whiteElo ?? miniature.whiteElo);
  final blackRating = _safeRating(fullGame.blackElo ?? miniature.blackElo);

  return GamesTourModel(
    gameId: miniature.canonicalGameId,
    source: GameSource.gamebase,
    whitePlayer: PlayerCard(
      name: whiteName,
      federation: miniature.whiteFed?.trim() ?? '',
      title: '',
      rating: whiteRating,
      countryCode: miniature.whiteFed?.trim() ?? '',
      team: null,
      gamebasePlayerId: miniature.whitePlayerId?.trim(),
    ),
    blackPlayer: PlayerCard(
      name: blackName,
      federation: miniature.blackFed?.trim() ?? '',
      title: '',
      rating: blackRating,
      countryCode: miniature.blackFed?.trim() ?? '',
      team: null,
      gamebasePlayerId: miniature.blackPlayerId?.trim(),
    ),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus:
        miniature.result == MiniatureGameResult.whiteWins
            ? GameStatus.whiteWins
            : GameStatus.blackWins,
    roundId: 'gamebase-miniatures',
    roundSlug: eco,
    tourId: event,
    tourSlug: _firstText(<String?>[fullGame.site]),
    pgn: pgn,
    boardNr: miniature.finalMoveNumber > 0 ? miniature.finalMoveNumber : null,
    lastMoveTime: miniature.date ?? fullGame.date,
    dateStart: miniature.date ?? fullGame.date,
    gameDay: miniature.date ?? fullGame.date,
    eco: eco,
    openingName: opening,
    timeControl: _timeControlName(miniature.timeControl),
    avgElo: miniature.avgRating,
    isOnline: miniature.isOnline,
    sourceGameId: miniature.canonicalGameId,
  );
}

String? _firstText(List<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  }
  return null;
}

String? _combinedOpening({
  required String? opening,
  required String? variation,
}) {
  if (opening == null) return variation;
  if (variation == null || variation == opening) return opening;
  return '$opening · $variation';
}

int _safeRating(int? rating) =>
    rating == null || rating < 0 || rating > 4000 ? 0 : rating;

String _timeControlName(MiniatureGameTimeControl control) => switch (control) {
  MiniatureGameTimeControl.classical => 'Classical',
  MiniatureGameTimeControl.rapid => 'Rapid',
  MiniatureGameTimeControl.blitz => 'Blitz',
};

class _MiniatureOpenException implements Exception {
  const _MiniatureOpenException(this.message);

  final String message;
}
