import 'package:chessever2/screens/favorites/favorite_players_provider.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/widgets/rounded_search_bar.dart';
import 'widgets/player_favorite_card.dart';

class FavoriteScreen extends ConsumerStatefulWidget {
  const FavoriteScreen({super.key});

  @override
  ConsumerState<FavoriteScreen> createState() => _FavoriteScreenState();
}

class _FavoriteScreenState extends ConsumerState<FavoriteScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    ref.read(favoriteSearchQueryProvider.notifier).state =
        _searchController.text;
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(favoriteSearchQueryProvider.notifier).state = '';
  }

  @override
  Widget build(BuildContext context) {
    final searchQuery = ref.watch(favoriteSearchQueryProvider);

    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.sp),
              child: Row(
                children: [
                  IconButton(
                    iconSize: 24.ic,
                    padding: EdgeInsets.zero,
                    onPressed: () => _handleBackPress(context),
                    icon: Icon(Icons.arrow_back_ios_new_outlined, size: 24.ic),
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 16.sp),
                      child: RoundedSearchBar(
                        showProfile: false,
                        showFilter: searchQuery.isEmpty,
                        controller: _searchController,
                        onChanged: (value) {},
                        hintText: 'Search favorites',
                        onFilterTap: searchQuery.isEmpty ? null : _clearSearch,
                        onProfileTap: () {},
                      ),
                    ),
                  ),
                  if (searchQuery.isNotEmpty)
                    IconButton(
                      icon: Icon(
                        Icons.clear,
                        color: kWhiteColor.withOpacity(0.7),
                        size: 24.ic,
                      ),
                      onPressed: _clearSearch,
                    ),
                ],
              ),
            ),
            SizedBox(height: 16.h),
            Expanded(child: _buildPlayersTab()),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayersTab() {
    final favoritesAsync = ref.watch(favoritePlayersNotifierProvider);
    final filteredPlayers = ref.watch(filteredFavoritePlayersProvider);

    return favoritesAsync.when(
      data: (_) => _buildPlayersList(filteredPlayers),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _buildErrorState(error.toString()),
    );
  }

  Widget _buildPlayersList(List<PlayerStandingModel> players) {
    final searchQuery = ref.watch(favoriteSearchQueryProvider);

    if (players.isEmpty) {
      if (searchQuery.isNotEmpty) {
        return _buildEmptyState(
          'No players found',
          'No favorites match "$searchQuery"',
        );
      }
      return _buildEmptyState(
        'No favorite players yet',
        'Tap the heart icon on players to add them to favorites',
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await ref
            .read(favoritePlayersNotifierProvider.notifier)
            .refreshFavorites();
      },
      child: Column(
        children: [
          if (searchQuery.isNotEmpty)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.sp),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${players.length} ${players.length == 1 ? 'result' : 'results'} found',
                    style: AppTypography.textSmRegular.copyWith(
                      color: kWhiteColor.withOpacity(0.7),
                    ),
                  ),
                  TextButton(
                    onPressed: _clearSearch,
                    child: Text(
                      'Clear',
                      style: AppTypography.textSmMedium.copyWith(
                        color: kPrimaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          if (searchQuery.isNotEmpty) SizedBox(height: 8.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.sp),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 12.sp),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Player',
                      style: AppTypography.textSmMedium.copyWith(
                        color: kWhiteColor.withOpacity(0.6),
                        fontSize: 14.sp,
                      ),
                    ),
                  ),

                  SizedBox(width: 16.w),

                  SizedBox(
                    width: 60.w,
                    child: Text(
                      'Elo',
                      style: AppTypography.textSmMedium.copyWith(
                        color: kWhiteColor.withOpacity(0.6),
                        fontSize: 14.sp,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  SizedBox(width: 16.w),

                  SizedBox(width: 36.w),
                ],
              ),
            ),
          ),

          SizedBox(height: 8.h),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.sp),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4.br),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: players.length,
                  itemBuilder: (context, index) {
                    final player = players[index];
                    final playerData = {
                      'name': player.name,
                      'title': player.title,
                      'countryCode': player.countryCode,
                      'rating': player.score,
                      'fideId': player.fideId?.toString(),
                    };
                    final isEven = index % 2 == 0;

                    return PlayerFavoriteCard(
                      playerData: playerData,
                      rank: index + 1,
                      isEven: isEven,
                      onRemoveFavorite: () => _removeFavoritePlayer(player),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.favorite_outline,
            size: 48.ic,
            color: kWhiteColor.withOpacity(0.5),
          ),
          SizedBox(height: 16.h),
          Text(
            title,
            style: AppTypography.textMdMedium.copyWith(
              color: kWhiteColor.withOpacity(0.7),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: 8.h),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTypography.textSmRegular.copyWith(
                color: kWhiteColor.withOpacity(0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48.ic, color: kRedColor),
          SizedBox(height: 16.h),
          Text(
            'Error loading favorites',
            style: AppTypography.textMdMedium.copyWith(
              color: kWhiteColor.withOpacity(0.7),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: 8.h),
            child: Text(
              error,
              textAlign: TextAlign.center,
              style: AppTypography.textSmRegular.copyWith(
                color: kWhiteColor.withOpacity(0.5),
              ),
            ),
          ),
          SizedBox(height: 16.h),
          ElevatedButton(
            onPressed: () {
              ref
                  .read(favoritePlayersNotifierProvider.notifier)
                  .refreshFavorites();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  void _handleBackPress(BuildContext context) {
    try {
      Navigator.of(context).pop();
    } catch (e) {
      // Error navigating back
    }
  }

  Future<void> _removeFavoritePlayer(PlayerStandingModel player) async {
    await ref
        .read(favoritePlayersNotifierProvider.notifier)
        .removeFavorite(player);
  }
}
