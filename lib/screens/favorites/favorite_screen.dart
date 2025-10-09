import 'package:chessever2/repository/local_storage/unified_favorites/unified_favorites_provider.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_typography.dart';
import '../../widgets/rounded_search_bar.dart';
import 'widgets/event_favorite_card.dart';
import 'widgets/player_favorite_card.dart';

class FavoriteScreen extends ConsumerStatefulWidget {
  const FavoriteScreen({super.key});

  @override
  ConsumerState<FavoriteScreen> createState() => _FavoriteScreenState();
}

class _FavoriteScreenState extends ConsumerState<FavoriteScreen>
    with TickerProviderStateMixin {
  late final TextEditingController _searchController;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchController.addListener(_onSearchChanged);
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    ref.read(favoritesSearchQueryProvider.notifier).state =
        _searchController.text;
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header with back button and search
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
            ),

            // Tab bar
            Container(
              margin: EdgeInsets.symmetric(horizontal: 16.sp),
              decoration: BoxDecoration(
                color: kBlack2Color,
                borderRadius: BorderRadius.circular(8.br),
              ),
              child: TabBar(
                controller: _tabController,
                onTap: (index) {
                  ref.read(selectedFavoriteTabProvider.notifier).state =
                      FavoriteTab.values[index];
                },
                indicator: BoxDecoration(
                  color: kPrimaryColor,
                  borderRadius: BorderRadius.circular(6.br),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: kWhiteColor,
                unselectedLabelColor: kWhiteColor.withValues(alpha: 0.6),
                labelStyle: AppTypography.textSmMedium,
                unselectedLabelStyle: AppTypography.textSmRegular,
                tabs: [
                  Tab(text: 'Events'),
                  Tab(text: 'Players'),
                ],
              ),
            ),

            SizedBox(height: 16.h),

            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildEventsTab(),
                  _buildPlayersTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventsTab() {
    final filteredEventsAsync = ref.watch(filteredFavoriteEventsProvider);

    return filteredEventsAsync.when(
      data: (events) => _buildEventsList(events),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => const Center(child: Text('Error loading favorite events')),
    );
  }

  Widget _buildPlayersTab() {
    // Watch tournament favorites instead of unified favorites
    // since players favorited from scoreboard don't have fideId
    final filteredPlayersAsync = ref.watch(filteredFavoriteTournamentPlayersProvider);

    return filteredPlayersAsync.when(
      data: (players) => _buildTournamentPlayersList(players),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => const Center(child: Text('Error loading favorite players')),
    );
  }


  Widget _buildEventsList(List<Map<String, dynamic>> events) {
    if (events.isEmpty) {
      return _buildEmptyState(
        'No favorite events yet',
        'Tap the star icon on events to add them to favorites',
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.sp),
      child: ListView.separated(
        itemCount: events.length,
        separatorBuilder: (context, index) => SizedBox(height: 12.h),
        itemBuilder: (context, index) {
          final event = events[index];
          return EventFavoriteCard(
            eventData: event,
            onRemoveFavorite: () => _removeFavoriteEvent(event['id'] as String),
          );
        },
      ),
    );
  }

  Widget _buildTournamentPlayersList(List<PlayerStandingModel> players) {
    if (players.isEmpty) {
      return _buildEmptyState(
        'No favorite players yet',
        'Tap the heart icon on players to add them to favorites',
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.sp),
      child: ListView.separated(
        itemCount: players.length,
        separatorBuilder: (context, index) => SizedBox(height: 12.h),
        itemBuilder: (context, index) {
          final player = players[index];
          // Convert PlayerStandingModel to Map format for PlayerFavoriteCard
          final playerData = {
            'name': player.name,
            'title': player.title,
            'countryCode': player.countryCode,
            'rating': player.score,
            'fideId': player.fideId, // Now includes fideId from PlayerStandingModel
          };
          return PlayerFavoriteCard(
            playerData: playerData,
            rank: index + 1,
            onRemoveFavorite: () => _removeTournamentFavoritePlayer(player.name),
          );
        },
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
            color: kWhiteColor.withValues(alpha: 0.5),
          ),
          SizedBox(height: 16.h),
          Text(
            title,
            style: AppTypography.textMdMedium.copyWith(
              color: kWhiteColor.withValues(alpha: 0.7),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: 8.h),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTypography.textSmRegular.copyWith(
                color: kWhiteColor.withValues(alpha: 0.5),
              ),
            ),
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

  Future<void> _removeFavoriteEvent(String eventId) async {
    await ref.removeFavoriteEvent(eventId);
  }

  Future<void> _removeTournamentFavoritePlayer(String playerName) async {
    await ref.removeFavoriteTournamentPlayer(playerName);
  }

}