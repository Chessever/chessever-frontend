// filepath: /Users/p1/Desktop/chessever/lib/screens/favorites/favorite_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      appBar: AppBar(
        backgroundColor: kBackgroundColor,
        elevation: 0,
        title: Text(
          'Favorites',
          style: AppTypography.textMdBold.copyWith(color: kWhiteColor),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: kWhiteColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: RoundedSearchBar(
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
                  profileInitials: 'VD',
                ),
              ),

              // Column headers
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0, top: 8.0),
                child: DefaultTextStyle(
                  style: AppTypography.textSmMedium.copyWith(
                    color: kWhiteColor,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Player header - left-aligned
                      const Expanded(flex: 3, child: Text('Player')),

                      // Elo header - center-aligned to match player screen
                      Expanded(
                        flex: 1,
                        child: Text('Elo', textAlign: TextAlign.center),
                      ),

                      // Age header - center-aligned
                      const Expanded(
                        flex: 1,
                        child: Text('Age', textAlign: TextAlign.center),
                      ),

                      // Space for favorite icon
                      const SizedBox(width: 30),
                    ],
                  ),
                ),
              ),

              // Favorites list
              Expanded(
                child: favoritesAsync.when(
                  loading:
                      () => const Center(
                        child: CircularProgressIndicator(color: kWhiteColor),
                      ),
                  error:
                      (error, stackTrace) => Center(
                        child: Text(
                          'Error loading favorites: $error',
                          style: AppTypography.textSmRegular.copyWith(
                            color: kWhiteColor,
                          ),
                        ),
                      ),
                  data:
                      (favoritePlayers) =>
                          _buildFavoritesList(ref, favoritePlayers),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFavoritesList(
    WidgetRef ref,
    List<Map<String, dynamic>> favoritePlayers,
  ) {
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
      ref.invalidate(playerProvider);
    });
  }
}
