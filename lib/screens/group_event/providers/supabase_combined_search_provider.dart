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
            if (_isPlayerName(searchTerm, gb.name)) {
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
        final q = query.trim().toLowerCase();
        playerResults.sort((a, b) {
          final aExact = a.matchedText.toLowerCase() == q;
          final bExact = b.matchedText.toLowerCase() == q;
          if (aExact && !bExact) return -1;
          if (!aExact && bExact) return 1;

          final aStart = a.matchedText.toLowerCase().startsWith(q);
          final bStart = b.matchedText.toLowerCase().startsWith(q);
          if (aStart && !bStart) return -1;
          if (!aStart && bStart) return 1;
          return a.matchedText.compareTo(b.matchedText);
        });

        return EnhancedSearchResult(
          tournamentResults: tournamentResults,
          playerResults: playerResults,
          allPlayers: allPlayers,
        );
      },
    );

bool _isPlayerName(String searchTerm, String tournamentName) {
  final t = searchTerm.trim().toLowerCase();
  final tn = tournamentName.trim().toLowerCase();

  // drop exact or pipe-prefixed event-title clones
  if (t == tn || t.startsWith('$tn |')) return false;

  if ([
    'chess',
    'tournament',
    'championship',
    'festival',
    'open',
    'classic',
  ].any((w) => t.contains(w)))
    return false;

  final words = searchTerm.trim().split(' ');
  if (words.length < 2 || words.length > 4) return false;

  return words.every(
    (w) => w.isNotEmpty && w[0] == w[0].toUpperCase() && w.length > 1,
  );
}
