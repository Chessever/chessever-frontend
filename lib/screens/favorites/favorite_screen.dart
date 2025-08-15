import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_typography.dart';
import '../../widgets/rounded_search_bar.dart';
import '../players/providers/player_providers.dart';
import 'widgets/favorite_card.dart';

final _favoriteSearchQueryProvider = StateProvider<String>((ref) => '');

class FavoriteScreen extends ConsumerStatefulWidget {
  const FavoriteScreen({super.key});

  @override
  ConsumerState<FavoriteScreen> createState() => _FavoriteScreenState();
}

class _FavoriteScreenState extends ConsumerState<FavoriteScreen>
    with WidgetsBindingObserver {
  // Add a persistent TextEditingController
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onSearchChanged() {
    ref.read(_favoriteSearchQueryProvider.notifier).state =
        _searchController.text;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshData();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshData();
  }

  void _refreshData() {
    // Invalidate providers to refresh data
    ref.invalidate(favoritePlayersProvider);
  }

  @override
  Widget build(BuildContext context) {
    final favoritesAsync = ref.watch(favoritePlayersProvider);

    return Scaffold(
      backgroundColor: kBackgroundColor,

      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.sp),
          child: Column(
            children: [
              // Search bar
              Padding(
                padding: EdgeInsets.symmetric(vertical: 16.sp),
                child: RoundedSearchBar(
                  showProfile: false,
                  controller: _searchController,
                  onChanged: (value) {
                    // onChanged is handled by the controller listener now
                  },
                  hintText: 'Search favorites',
                  onFilterTap: () {
                    // Filter functionality would go here
                  },
                  onProfileTap: () {
                    // Profile tap functionality
                  },
                ),
              ),

              // Column headers
              Padding(
                padding: EdgeInsets.only(bottom: 16.sp, top: 8.sp),
                child: DefaultTextStyle(
                  style: AppTypography.textSmMedium.copyWith(
                    color: kWhiteColor,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Player header - left-aligned
                      Expanded(
                        flex: 3,
                        child: Text(
                          'Player',
                          style: AppTypography.textSmMedium,
                        ),
                      ),

                      // Elo header - center-aligned to match player screen
                      Expanded(
                        flex: 1,
                        child: Text(
                          'Elo',
                          style: AppTypography.textSmMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),

                      // Age header - center-aligned
                      Expanded(
                        flex: 1,
                        child: Text(
                          'Age',
                          style: AppTypography.textSmMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),

                      // Space for favorite icon
                      SizedBox(width: 30.w),
                    ],
                  ),
                ),
              ),

              // // Favorites list
              // Expanded(
              //   child: favoritesAsync.when(
              //     loading:
              //         () => const Center(
              //           child: CircularProgressIndicator(color: kWhiteColor),
              //         ),
              //     error:
              //         (error, stackTrace) => Center(
              //           child: Text(
              //             'Error loading favorites: $error',
              //             style: AppTypography.textSmRegular.copyWith(
              //               color: kWhiteColor,
              //             ),
              //           ),
              //         ),
              //     data:
              //         (favoritePlayers) =>
              //             _FavoritesList(favoritePlayers: favoritePlayers),
              //   ),
              // ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoritesList extends ConsumerWidget {
  const _FavoritesList({required this.favoritePlayers, super.key});

  final List<Map<String, dynamic>> favoritePlayers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchQuery = ref.watch(_favoriteSearchQueryProvider);

    // Filter favorites by search query
    final filteredFavorites =
        searchQuery.isEmpty
            ? favoritePlayers
            : favoritePlayers.where((player) {
              return player['name'].toString().toLowerCase().contains(
                searchQuery.toLowerCase(),
              );
            }).toList();

    if (filteredFavorites.isEmpty) {
      return Center(
        child: Text(
          'No favorite players found',
          style: AppTypography.textSmRegular.copyWith(color: kWhiteColor),
        ),
      );
    }

    return ListView.separated(
      itemCount: filteredFavorites.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final player = filteredFavorites[index];
        return FavoriteCard(
          rank: index + 1,
          playerName: player['name'],
          countryCode: player['countryCode'],
          elo: player['elo'],
          age: player['age'],
          onRemoveFavorite: () => _toggleFavorite(ref, player['id']),
        );
      },
    );
  }

  void _toggleFavorite(WidgetRef ref, String playerId) {
    final viewModel = ref.read(playerViewModelProvider);
    viewModel.toggleFavorite(playerId).then((_) {
      // Refresh providers to update UI
      ref.invalidate(favoritePlayersProvider);
      // ref.invalidate(playerProvider);
    });
  }
}
