import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../utils/app_typography.dart';
import '../../theme/app_theme.dart';
import '../../widgets/rounded_search_bar.dart';
import 'widgets/player_card.dart';
import 'providers/player_providers.dart';

class PlayerListScreen extends ConsumerStatefulWidget {
  const PlayerListScreen({super.key});

  @override
  ConsumerState<PlayerListScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerListScreen> {
  late final TextEditingController _searchController;
  final ScrollController _scrollController = ScrollController();
  final double _scrollThreshold = 200.0;

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
    super.dispose();
  }

  void _onSearchChanged() {
    ref.read(playerSearchQueryProvider.notifier).state = _searchController.text;
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

    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.sp),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(vertical: 16.sp),
                child: RoundedSearchBar(
                  showProfile: false,
                  controller: _searchController,
                  hintText: 'Search players',
                  onFilterTap: () {},
                  onProfileTap: () {},
                ),
              ),

              Padding(
                padding: EdgeInsets.only(bottom: 16.sp, top: 8.sp),
                child: DefaultTextStyle(
                  style: AppTypography.textSmMedium.copyWith(
                    color: kWhiteColor,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Player',
                          style: AppTypography.textSmMedium,
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(
                          'Elo',
                          style: AppTypography.textSmMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(
                          'Age',
                          style: AppTypography.textSmMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      SizedBox(width: 30.w),
                    ],
                  ),
                ),
              ),

              Expanded(
                child: _PlayerList(
                  scrollController: _scrollController,
                  searchController: _searchController,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerList extends ConsumerWidget {
  final ScrollController scrollController;
  final TextEditingController searchController;

  const _PlayerList({
    required this.scrollController,
    required this.searchController,
  });

  Future<void> _handleRefresh(WidgetRef ref) async {
    searchController.clear(); // Clear search on refresh
    final notifier = ref.read(playerPaginationProvider.notifier);
    await notifier.initFirstPage();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playersState = ref.watch(playerPaginationProvider);
    final filteredPlayers = ref.watch(filteredPlayersProvider);
    final notifier = ref.read(playerPaginationProvider.notifier);

    return RefreshIndicator(
      color: kWhiteColor,
      backgroundColor: kBackgroundColor,
      displacement: 40.0,
      onRefresh: () => _handleRefresh(ref),
      child: playersState.when(
        loading:
            () => const Center(
              child: CircularProgressIndicator(color: kWhiteColor),
            ),
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
                          color: kWhiteColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Pull down to retry',
                        style: AppTypography.textXsRegular.copyWith(
                          color: kWhiteColor.withOpacity(0.7),
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
                            color: kWhiteColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Pull down to refresh',
                          style: AppTypography.textXsRegular.copyWith(
                            color: kWhiteColor.withOpacity(0.7),
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
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(color: kWhiteColor),
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
                onFavoriteToggle:
                    () => _toggleFavorite(ref, player['fideId'].toString()),
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

  void _toggleFavorite(WidgetRef ref, String playerId) {
    final viewModel = ref.read(playerViewModelProvider);
    viewModel.toggleFavorite(playerId);
  }
}
