import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/app_typography.dart';
import '../../theme/app_theme.dart';
import '../../widgets/rounded_search_bar.dart';
import 'widgets/player_card.dart';
import 'providers/player_provider.dart';

// Provider for filtered players
final filteredPlayersProvider = Provider<List<Map<String, dynamic>>>((ref) {
  final searchQuery = ref.watch(_searchQueryProvider);
  final playerNotifier = ref.watch(playerNotifierProvider.notifier);
  return playerNotifier.getFilteredPlayers(searchQuery);
});

// Provider to track search query
final _searchQueryProvider = StateProvider<String>((ref) => '');

class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerAsync = ref.watch(playerNotifierProvider);

    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        backgroundColor: kBackgroundColor,
        elevation: 0,
        title: Text(
          'Players',
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
                  hintText: 'Search players',
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
                      // const SizedBox(width: 24), // Space for rank number
                      // const SizedBox(width: 28), // Space for flag
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

              // Player list
              Expanded(
                child: playerAsync.when(
                  loading:
                      () => const Center(
                        child: CircularProgressIndicator(color: kWhiteColor),
                      ),
                  error:
                      (error, stackTrace) => Center(
                        child: Text(
                          'Error loading players: $error',
                          style: AppTypography.textSmRegular.copyWith(
                            color: kWhiteColor,
                          ),
                        ),
                      ),
                  data: (_) => _buildPlayerList(ref),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerList(WidgetRef ref) {
    final filteredPlayers = ref.watch(filteredPlayersProvider);

    if (filteredPlayers.isEmpty) {
      return Center(
        child: Text(
          'No players found',
          style: AppTypography.textSmRegular.copyWith(color: kWhiteColor),
        ),
      );
    }

    return ListView.separated(
      itemCount: filteredPlayers.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final player = filteredPlayers[index];
        return PlayerCard(
          rank: index + 1,
          playerName: player['name'],
          countryCode: player['countryCode'],
          elo: player['elo'],
          age: player['age'],
          isFavorite: player['isFavorite'],
          onFavoriteToggle: () => _toggleFavorite(ref, player['name']),
        );
      },
    );
  }

  void _toggleFavorite(WidgetRef ref, String playerName) {
    ref.read(playerNotifierProvider.notifier).toggleFavorite(playerName);
  }
}
