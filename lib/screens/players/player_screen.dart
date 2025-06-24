import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/app_typography.dart';
import '../../theme/app_theme.dart';
import '../../widgets/rounded_search_bar.dart';
import 'widgets/player_card.dart';
import 'providers/player_providers.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
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
    ref.read(playerSearchQueryProvider.notifier).state = _searchController.text;
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
    ref.invalidate(playerProvider);
  }

  @override
  Widget build(BuildContext context) {
    final playerAsync = ref.watch(playerProvider);

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
                  controller: _searchController,
                  onChanged: (value) {
                    // onChanged is handled by the controller listener now
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
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Expanded(flex: 3, child: Text('Player')),

                      // Elo header - right aligned to match player card
                      Expanded(
                        flex: 1,
                        child: Text('Elo', textAlign: TextAlign.center),
                      ),

                      // Age header - center aligned to match player card
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
          playerId: player['id'],
          playerName: player['name'],
          countryCode: player['countryCode'],
          elo: player['elo'],
          age: player['age'],
          isFavorite: player['isFavorite'],
          onFavoriteToggle: () => _toggleFavorite(ref, player['id']),
        );
      },
    );
  }

  void _toggleFavorite(WidgetRef ref, String playerId) {
    final viewModel = ref.read(playerViewModelProvider);
    viewModel.toggleFavorite(playerId).then((_) {
      // Refresh the UI by invalidating the provider
      ref.invalidate(playerProvider);
    });
  }
}
