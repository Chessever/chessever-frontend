import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../repository/supabase/game/games.dart';
import '../../../repository/supabase/group_broadcast/group_tour_repository.dart';
import '../../../widgets/search/enhanced_group_broadcast_local_storage.dart';
import '../../../widgets/search/search_result_model.dart';
import '../model/tour_event_card_model.dart';

final supabaseCombinedSearchProvider =
    AutoDisposeFutureProvider.family<EnhancedSearchResult, String>(
      (ref, query) async {
        if (query.trim().isEmpty) return EnhancedSearchResult.empty();

        final broadcasts = await ref
            .read(groupBroadcastRepositoryProvider)
            .searchGroupBroadcastsFromSupabase(query);

        final tournamentResults = <SearchResult>[];
        final playerResults = <SearchResult>[];
        final allPlayers = <SearchPlayer>[];
        final liveIds = ref.read(liveIdsProvider);

        for (final gb in broadcasts) {
          final tourEventModel = GroupEventCardModel.fromGroupBroadcast(
            gb,
            liveIds,
          );

          tournamentResults.add(
            SearchResult(
              tournament: tourEventModel,
              score: 100.0,
              matchedText: gb.name,
              type: SearchResultType.tournament,
            ),
          );

          for (final searchTerm in gb.search) {
            if (_isPlayerName(searchTerm)) {
              final player = SearchPlayer.fromSearchTerm(
                searchTerm,
                gb.id,
                gb.name,
              );
              allPlayers.add(player);

              playerResults.add(
                SearchResult(
                  tournament: tourEventModel,
                  score: 90.0,
                  matchedText: searchTerm,
                  type: SearchResultType.player,
                  player: player,
                ),
              );
            }
          }
        }

        return EnhancedSearchResult(
          tournamentResults: tournamentResults,
          playerResults: playerResults,
          allPlayers: allPlayers,
        );
      },
    );

bool _isPlayerName(String searchTerm) {
  final lowerTerm = searchTerm.toLowerCase();
  if (lowerTerm.contains('chess') ||
      lowerTerm.contains('tournament') ||
      lowerTerm.contains('championship') ||
      lowerTerm.contains('festival') ||
      lowerTerm.contains('open') ||
      lowerTerm.contains('classic')) {
    return false;
  }
  final words = searchTerm.trim().split(' ');
  if (words.length >= 2 && words.length <= 4) {
    return words.every(
      (word) =>
          word.isNotEmpty &&
          word[0] == word[0].toUpperCase() &&
          word.length > 1,
    );
  }
  return false;
}
