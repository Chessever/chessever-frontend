import 'dart:async';
import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/liquid_glass/glass_full_screen_page.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_stack.dart';
import 'package:chessever2/widgets/liquid_glass/glass_motion.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_search.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_top_bar.dart';
import 'package:chessever2/widgets/liquid_glass/glass_loading.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/repository/local_storage/favorite/favourate_standings_player_services.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/favorite_constants.dart';
import 'package:chessever2/utils/favorite_limit_guard.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'widgets/player_card.dart';
import 'providers/player_providers.dart';

enum _PlayerDirectoryFilter { all, favorites }

enum _PlayerDirectorySort { ranking, name, rating }

class PlayerListScreen extends ConsumerStatefulWidget {
  const PlayerListScreen({super.key});

  @override
  ConsumerState<PlayerListScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerListScreen> {
  late final TextEditingController _searchController;
  final ScrollController _scrollController = ScrollController();
  final double _scrollThreshold = 200.0;
  Timer? _searchAnalyticsTimer;
  bool _searchExpanded = false;
  _PlayerDirectoryFilter _filter = _PlayerDirectoryFilter.all;
  _PlayerDirectorySort _sort = _PlayerDirectorySort.ranking;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchAnalyticsTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text;
    ref.read(playerSearchQueryProvider.notifier).state = query;

    _searchAnalyticsTimer?.cancel();
    final normalized = query.trim();
    if (normalized.isEmpty) return;

    _searchAnalyticsTimer = Timer(const Duration(milliseconds: 350), () {
      AnalyticsService.instance.trackEventDetached(
        'Player Search',
        properties: {'query': normalized, 'query_length': normalized.length},
      );
    });
  }

  void _onScroll() {
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;

    if (maxScroll - currentScroll <= _scrollThreshold) {
      ref.read(playerPaginationProvider.notifier).fetchNextPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(playerInitializationProvider);

    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.sp,
      tablet: 24.sp,
    );
    final scaledLabelHeight = MediaQuery.textScalerOf(context).scale(14) * 1.2;
    final controlHeight = (scaledLabelHeight + 20).clamp(48.0, 72.0);

    return GlassFullScreenPage(
      key: e2eKey(E2eIds.playersRoot),
      backgroundColor: context.colors.background,
      contentPadding: EdgeInsets.fromLTRB(
        horizontalPadding,
        controlHeight * 2 + 26,
        horizontalPadding,
        8,
      ),
      topOverlayPadding: const EdgeInsets.only(top: 4),
      topOverlay: GlassIslandStack(
        key: const ValueKey<String>('players-floating-controls'),
        includeStatusBar: false,
        gap: 6,
        children: [
          GlassIslandTopBar(
            topPadding: 0,
            height: controlHeight,
            horizontalPadding: horizontalPadding,
            title:
                _searchExpanded
                    ? null
                    : Semantics(
                      header: true,
                      child: _DirectoryChip(
                        label: 'Players',
                        controlHeight: controlHeight,
                      ),
                    ),
            center: Semantics(
              label:
                  _searchExpanded ? 'Search players field' : 'Search players',
              button: !_searchExpanded,
              textField: _searchExpanded,
              child: GlassIslandSearch(
                controller: _searchController,
                expanded: _searchExpanded,
                textFieldKey: e2eKey(E2eIds.playersSearchField),
                hintText: 'Search players',
                collapsedSize: controlHeight,
                expandedHeight: controlHeight,
                onExpandedChanged:
                    (expanded) => setState(() => _searchExpanded = expanded),
                onChanged: (_) {},
                onClear: _searchController.clear,
              ),
            ),
          ),
          _buildDirectoryControls(
            horizontalPadding: horizontalPadding,
            controlHeight: controlHeight,
          ),
        ],
      ),
      content: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: _PlayerList(
            scrollController: _scrollController,
            searchController: _searchController,
            filter: _filter,
            sort: _sort,
          ),
        ),
      ),
    );
  }

  Widget _buildDirectoryControls({
    required double horizontalPadding,
    required double controlHeight,
  }) {
    final filterLabel =
        _filter == _PlayerDirectoryFilter.all ? 'All players' : 'Favorites';
    final sortLabel = switch (_sort) {
      _PlayerDirectorySort.ranking => 'Rank',
      _PlayerDirectorySort.name => 'Player',
      _PlayerDirectorySort.rating => 'Elo',
    };

    return SingleChildScrollView(
      key: const ValueKey<String>('players-floating-control-rail'),
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Row(
        children: [
          _DirectoryChip(
            label: filterLabel,
            controlHeight: controlHeight,
            selected: _filter == _PlayerDirectoryFilter.favorites,
            semanticsLabel: 'Filter players, $filterLabel',
            onTap: () {
              setState(() {
                _filter =
                    _filter == _PlayerDirectoryFilter.all
                        ? _PlayerDirectoryFilter.favorites
                        : _PlayerDirectoryFilter.all;
              });
            },
          ),
          const SizedBox(width: 8),
          _DirectoryChip(
            label: 'Sort · $sortLabel',
            controlHeight: controlHeight,
            semanticsLabel: 'Sort players by $sortLabel',
            onTap: () {
              setState(() {
                _sort = switch (_sort) {
                  _PlayerDirectorySort.ranking => _PlayerDirectorySort.name,
                  _PlayerDirectorySort.name => _PlayerDirectorySort.rating,
                  _PlayerDirectorySort.rating => _PlayerDirectorySort.ranking,
                };
              });
            },
          ),
          const SizedBox(width: 8),
          _DirectoryChip(
            label: 'Player · Elo · Age',
            controlHeight: controlHeight,
            semanticsLabel: 'Columns: Player, Elo, Age',
          ),
        ],
      ),
    );
  }
}

class _DirectoryChip extends StatelessWidget {
  const _DirectoryChip({
    required this.label,
    required this.controlHeight,
    this.selected = false,
    this.semanticsLabel,
    this.onTap,
  });

  final String label;
  final double controlHeight;
  final bool selected;
  final String? semanticsLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = GlassMotion.reduceMotion(context);
    return Semantics(
      button: onTap != null,
      selected: onTap == null ? null : selected,
      label: semanticsLabel ?? label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: controlHeight),
          child: GlassChip(
            label: label,
            selected: selected,
            useOwnLayer: true,
            quality: GlassQuality.standard,
            labelStyle: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            interactionScale: reduceMotion ? 1 : 1.03,
            stretch: reduceMotion ? 0 : 0.3,
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}

class _PlayerList extends ConsumerWidget {
  final ScrollController scrollController;
  final TextEditingController searchController;
  final _PlayerDirectoryFilter filter;
  final _PlayerDirectorySort sort;

  const _PlayerList({
    required this.scrollController,
    required this.searchController,
    required this.filter,
    required this.sort,
  });

  Future<void> _handleRefresh(WidgetRef ref) async {
    HapticFeedbackService.medium();
    searchController.clear(); // Clear search on refresh
    final notifier = ref.read(playerPaginationProvider.notifier);
    await notifier.initFirstPage();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playersState = ref.watch(playerPaginationProvider);
    final players = ref.watch(filteredPlayersProvider);
    final filteredPlayers = _visiblePlayers(players);
    final notifier = ref.read(playerPaginationProvider.notifier);

    return RefreshIndicator(
      color: context.colors.textPrimary,
      backgroundColor: context.colors.background,
      displacement: 40.0,
      onRefresh: () => _handleRefresh(ref),
      child: playersState.when(
        loading: () => Center(child: const GlassLoading.circular(size: 28)),
        error: (error, stack) {
          return RefreshIndicator(
            onRefresh: () => _handleRefresh(ref),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Error loading players',
                        style: AppTypography.textSmRegular.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Pull down to retry',
                        style: AppTypography.textXsRegular.copyWith(
                          color: context.colors.textPrimary.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
        data: (_) {
          if (filteredPlayers.isEmpty) {
            return RefreshIndicator(
              onRefresh: () => _handleRefresh(ref),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.7,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'No players found',
                          style: AppTypography.textSmRegular.copyWith(
                            color: context.colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Pull down to refresh',
                          style: AppTypography.textXsRegular.copyWith(
                            color: context.colors.textPrimary.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          return ListView.builder(
            controller: scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: filteredPlayers.length + (notifier.hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= filteredPlayers.length) {
                return Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: const GlassLoading.circular(size: 28),
                  ),
                );
              }

              final player = filteredPlayers[index];
              return PlayerCard(
                rank: index + 1,
                playerId: player['fideId'].toString(),
                playerName: '${player['title']} ${player['name']}',
                countryCode: player['fed']?.toString() ?? '',
                elo: player['rating'],
                age: 0,
                isFavorite: player['isFavorite'] ?? false,
                onBeforeToggle: () async {
                  final authOk = await requireFullAuthGuard(context);
                  if (!authOk) return false;
                  if (!context.mounted) return false;
                  // Check limit if adding (not currently favorite)
                  if (player['isFavorite'] != true) {
                    return await canAddMoreFavorites(context, ref);
                  }
                  return true;
                },
                onFavoriteToggle:
                    () => _toggleFavorite(
                      context,
                      ref,
                      player['fideId'].toString(),
                    ),
                index: index,
                isFirst: index == 0,
                isLast: index == filteredPlayers.length - 1,
              );
            },
          );
        },
      ),
    );
  }

  List<Map<String, dynamic>> _visiblePlayers(
    List<Map<String, dynamic>> players,
  ) {
    final visible =
        filter == _PlayerDirectoryFilter.favorites
            ? players.where((player) => player['isFavorite'] == true).toList()
            : List<Map<String, dynamic>>.of(players);

    switch (sort) {
      case _PlayerDirectorySort.ranking:
        return visible;
      case _PlayerDirectorySort.name:
        visible.sort((a, b) {
          final aName = a['name']?.toString().toLowerCase() ?? '';
          final bName = b['name']?.toString().toLowerCase() ?? '';
          return aName.compareTo(bName);
        });
      case _PlayerDirectorySort.rating:
        visible.sort((a, b) {
          final aRating = a['rating'] as int? ?? 0;
          final bRating = b['rating'] as int? ?? 0;
          return bRating.compareTo(aRating);
        });
    }
    return visible;
  }

  void _toggleFavorite(
    BuildContext context,
    WidgetRef ref,
    String playerId,
  ) async {
    final viewModel = ref.read(playerViewModelProvider);
    viewModel.toggleFavorite(playerId);

    // Also update the Supabase-backed favorites system so auto-pin updates immediately
    try {
      final players = ref.read(playerPaginationProvider).valueOrNull ?? [];
      final player = players.firstWhere(
        (p) => p['fideId'].toString() == playerId,
        orElse: () => <String, dynamic>{},
      );

      if (player.isNotEmpty) {
        final wasFavorite = player['isFavorite'] == true;
        final playerModel = PlayerStandingModel(
          name: '${player['title'] ?? ''} ${player['name']}'.trim(),
          countryCode: player['fed']?.toString() ?? '',
          score: player['rating'] ?? 0,
          scoreChange: 0,
          matchScore: null,
          fideId: int.tryParse(playerId),
          title: player['title']?.toString(),
        );

        final favService = ref.read(favoriteStandingsPlayerService);
        await favService.toggleFavorite(playerModel);

        // Increment favorites version to trigger auto-pin recomputation
        // This will cause the games list to re-sort immediately
        ref.read(favoritesVersionProvider.notifier).state++;
        debugPrint(
          '[PlayerScreen] Incremented favorites version to trigger games resort',
        );

        AnalyticsService.instance.trackEventDetached(
          'Player Favorite Toggled',
          properties: {
            'player_id': playerId,
            'player_name': playerModel.name,
            'country_code': playerModel.countryCode,
            'rating': playerModel.score,
            'title': playerModel.title,
            'is_favorited': !wasFavorite,
            'source': 'player_list',
          },
        );
      }
    } on FavoriteLimitExceededException {
      // Pre-flight `canAddMoreFavorites` already gates the common path; this
      // catches the race where the server-side count is ahead of local state.
      if (context.mounted) {
        await showPremiumPaywallSheet(context: context);
      }
    } catch (e) {
      debugPrint('Error updating Supabase favorites: $e');
    }
  }
}
