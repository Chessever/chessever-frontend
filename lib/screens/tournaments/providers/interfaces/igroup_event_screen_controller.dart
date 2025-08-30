import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tournaments/group_event_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';

/// Interface for the GroupEventScreenController
/// Defines the contract for managing tournament events, search functionality,
/// and navigation in the chess tournament application
abstract class IGroupEventScreenController {
  /// Reference to Riverpod's Ref for accessing other providers
  Ref get ref;

  /// Current tournament event category being displayed
  GroupEventCategory get tourEventCategory;

  /// List of live broadcast IDs
  List<String> get liveBroadcastId;

  /// List of user's favorite tournament IDs
  List<String> get favorites;

  /// Loads tournaments based on the current category and filters
  ///
  /// [inputBroadcast] - Optional list of broadcasts to load instead of fetching
  /// [sortByFavorites] - Whether to prioritize favorite tournaments in sorting
  Future<void> loadTours({List<GroupBroadcast>? inputBroadcast});

  /// Sets filtered tournament models and updates the UI
  ///
  /// [filterBroadcast] - List of filtered broadcasts to display
  Future<void> setFilteredModels(List<GroupBroadcast> filterBroadcast);

  /// Resets all applied filters and reloads tournaments
  Future<void> resetFilters();

  /// Refreshes tournament data from remote source
  Future<void> onRefresh();

  /// Handles tournament selection and navigation
  ///
  /// [context] - Build context for navigation
  /// [id] - Tournament ID to select and navigate to
  void onSelectTournament({required BuildContext context, required String id});

  /// Handles player selection and navigation to their tournament
  ///
  /// [context] - Build context for navigation
  /// [player] - Selected player object containing tournament info
  void onSelectPlayer({
    required BuildContext context,
    required SearchPlayer player,
  });

  /// Searches for tournaments based on query string
  ///
  /// [query] - Search query string
  /// [tourEventCategory] - Category to search within
  Future<void> searchForTournament(
    String query,
    GroupEventCategory tourEventCategory,
  );

  /// Loads tournaments for a specific category
  ///
  /// [tourEventCategory] - Category of tournaments to load
  Future<void> loadTournaments(GroupEventCategory tourEventCategory);

  /// Retrieves all players from currently loaded tournaments
  ///
  /// Returns list of [SearchPlayer] objects from all tournaments
  Future<List<SearchPlayer>> getAllPlayersFromCurrentTournaments();

  /// Searches for players by name across all tournaments
  ///
  /// [query] - Player name search query
  /// Returns filtered and sorted list of matching players
  Future<List<SearchPlayer>> searchPlayersOnly(String query);
}
