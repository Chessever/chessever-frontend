import 'package:chessever2/repository/local_storage/favorite/favourate_standings_player_services.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_typography.dart';
import '../../utils/location_service_provider.dart';
import '../../widgets/rounded_search_bar.dart';
import 'widgets/favorite_card.dart';

final _favoriteSearchQueryProvider = StateProvider<String>((ref) => '');

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
    ref.read(_favoriteSearchQueryProvider.notifier).state =
        _searchController.text;
  }

  @override
  Widget build(BuildContext context) {
    final favoritePlayersAsync = ref.watch(favoritePlayersProvider);
    final searchQuery = ref.watch(_favoriteSearchQueryProvider);

    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.sp),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    iconSize: 24.ic,
                    padding: EdgeInsets.zero,
                    onPressed: () => _handleBackPress(context),
                    icon: Icon(Icons.arrow_back_ios_new_outlined, size: 24.ic),
                  ),
                  // Search bar
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 16.sp),
                      child: RoundedSearchBar(
                        showProfile: false,
                        controller: _searchController,
                        onChanged: (value) {},
                        hintText: 'Search favorites',
                        onFilterTap: () {},
                        onProfileTap: () {},
                      ),
                    ),
                  ),
                ],
              ),
              favoritePlayersAsync.when(
                data: (favoritePlayers) {
                  return Expanded(
                    child: _buildFavoritesList(favoritePlayers, searchQuery),
                  );
                },
                loading:
                    () => Expanded(
                      child: Center(child: CircularProgressIndicator()),
                    ),
                error:
                    (error, stack) => Expanded(
                      child: Center(child: Text('Error loading favorites')),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleBackPress(BuildContext context) {
    try {
      Navigator.of(context).pop();
    } catch (e) {
      print('Error navigating back: $e');
    }
  }

  Widget _buildFavoritesList(
    List<PlayerStandingModel> favoritePlayers,
    String searchQuery,
  ) {
    // Filter by search query
    final filteredPlayers =
        searchQuery.isEmpty
            ? favoritePlayers
            : favoritePlayers.where((player) {
              return player.name.toLowerCase().contains(
                searchQuery.toLowerCase(),
              );
            }).toList();

    if (filteredPlayers.isEmpty) {
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
              searchQuery.isEmpty
                  ? 'No favorite players yet'
                  : 'No players found',
              style: AppTypography.textMdMedium.copyWith(
                color: kWhiteColor.withOpacity(0.7),
              ),
            ),
            if (searchQuery.isEmpty)
              Padding(
                padding: EdgeInsets.only(top: 8.h),
                child: Text(
                  'Tap the favourate icon on player standings\nto add them to favorites',
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

    return Column(
      children: [
        // Column headers
        Padding(
          padding: EdgeInsets.only(bottom: 16.sp, top: 8.sp),
          child: DefaultTextStyle(
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
            child: Row(
              children: [
                // Rank header
                SizedBox(
                  width: 40.w,
                  child: Text(
                    '#',
                    style: AppTypography.textSmMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(width: 12.w),

                // Player header
                Expanded(
                  child: Text('Player', style: AppTypography.textSmMedium),
                ),

                // Elo header
                SizedBox(
                  width: 60.w,
                  child: Text(
                    'Elo',
                    style: AppTypography.textSmMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(width: 12.w),

                // Score header
                SizedBox(
                  width: 60.w,
                  child: Text(
                    'Score',
                    style: AppTypography.textSmMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(width: 12.w),

                // Favorite icon space
                SizedBox(width: 30.w),
              ],
            ),
          ),
        ),

        // Favorites list
        Expanded(
          child: ListView.separated(
            itemCount: filteredPlayers.length,
            separatorBuilder: (context, index) => SizedBox(height: 12.h),
            itemBuilder: (context, index) {
              final player = filteredPlayers[index];
              final validCountryCode = ref
                  .read(locationServiceProvider)
                  .getValidCountryCode(player.countryCode);

              return FavoriteCard(
                playerName: player.name,
                elo: player.score,
                rank: index + 1,
                countryCode: validCountryCode,
                age: player.matchScore ?? "0",
                onRemoveFavorite: () => _toggleFavorite(player),
              );
            },
          ),
        ),
      ],
    );
  }

  void _toggleFavorite(PlayerStandingModel player) async {
    final favoritesService = ref.read(favoriteStandingsPlayerService);
    await favoritesService.toggleFavorite(player);

    ref.invalidate(favoritePlayersProvider);
  }
}
