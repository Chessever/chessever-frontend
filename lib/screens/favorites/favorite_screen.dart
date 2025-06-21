// filepath: /Users/p1/Desktop/chessever/lib/screens/favorites/favorite_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_typography.dart';
import '../../widgets/rounded_search_bar.dart';
import 'providers/favorite_provider.dart';
import 'widgets/favorite_card.dart';

// Provider for filtered starred_repository players
final filteredFavoritesProvider = Provider<List<Map<String, dynamic>>>((ref) {
  final searchQuery = ref.watch(_searchQueryProvider);
  final favoriteNotifier = ref.watch(favoriteNotifierProvider.notifier);
  return favoriteNotifier.getFilteredFavoritePlayers(searchQuery);
});

// Provider to track search query
final _searchQueryProvider = StateProvider<String>((ref) => '');

class FavoriteScreen extends ConsumerWidget {
  const FavoriteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoritesAsync = ref.watch(favoriteNotifierProvider);

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
                  controller: TextEditingController(),
                  onChanged: (value) {
                    ref.read(_searchQueryProvider.notifier).state = value;
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
                    children: [
                      // Player header
                      const Expanded(flex: 3, child: Text('Player')),

                      // Elo header
                      const Expanded(
                        flex: 1,
                        child: Text('Elo', textAlign: TextAlign.center),
                      ),

                      // Age header
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
                  data: (_) => _buildFavoritesList(ref),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFavoritesList(WidgetRef ref) {
    final filteredFavorites = ref.watch(filteredFavoritesProvider);

    if (filteredFavorites.isEmpty) {
      return Center(
        child: Text(
          'No starred_repository players found',
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
          onRemoveFavorite: () => _removeFromFavorites(ref, player['name']),
        );
      },
    );
  }

  void _removeFromFavorites(WidgetRef ref, String playerName) {
    ref.read(favoriteNotifierProvider.notifier).removeFromFavorites(playerName);
  }
}
