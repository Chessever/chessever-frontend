import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/widgets/search/enhanced_group_broadcast_local_storage.dart';
import 'package:chessever2/widgets/search/search_result_model.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';

final supabaseCombinedSearchProvider =
    AutoDisposeFutureProvider.family<EnhancedSearchResult, String>(
      (ref, query) async {
        if (query.trim().isEmpty) return EnhancedSearchResult.empty();

        final broadcasts = await ref
            .read(groupBroadcastRepositoryProvider)
            .searchGroupBroadcastsFromSupabase(query);
        final now = DateTime.now();

        int delta(GroupBroadcast b) =>
            (b.dateStart?.difference(now).abs().inSeconds ?? 999999).toInt();

        String _key(String s) => s.toLowerCase().trim();

        broadcasts.sort((a, b) {
          final keyA = _key(a.name);
          final keyB = _key(b.name);
          final qLower = query.trim().toLowerCase();

          /* 1. exact */
          final aExact = keyA == qLower;
          final bExact = keyB == qLower;
          if (aExact && !bExact) return -1;
          if (!aExact && bExact) return 1;

          /* 2. starts-with */
          final aStart = keyA.startsWith(qLower);
          final bStart = keyB.startsWith(qLower);
          if (aStart && !bStart) return -1;
          if (!aStart && bStart) return 1;
          if (aStart && bStart) return keyA.compareTo(keyB);

          /* 3. contains */
          final aContain = keyA.contains(qLower);
          final bContain = keyB.contains(qLower);
          if (aContain && !bContain) return -1;
          if (!aContain && bContain) return 1;
          if (aContain && bContain) return keyA.compareTo(keyB);
          final d = delta(a).compareTo(delta(b));
          if (d != 0) return d;
          return (b.maxAvgElo ?? 0).compareTo(a.maxAvgElo ?? 0);
        });

        final tournamentResults = <SearchResult>[];
        final playerResults = <SearchResult>[];
        final allPlayers = <SearchPlayer>[];
        final liveIds = ref.read(liveBroadcastIdsProvider);

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
        final broadcastById = <String, GroupBroadcast>{
          for (final b in broadcasts) b.id: b,
        };

        int deltaPlayer(SearchResult r) {
          final b = broadcastById[r.tournament.id]!; // original broadcast
          return (b.dateStart?.difference(now).abs().inSeconds ?? 999999);
        }

        playerResults.sort((a, b) {
          final qLower = query.trim().toLowerCase();

          // 1. exact match
          final aExact = a.matchedText.toLowerCase() == qLower;
          final bExact = b.matchedText.toLowerCase() == qLower;
          if (aExact && !bExact) return -1;
          if (!aExact && bExact) return 1;

          // 2. starts-with
          final aStart = a.matchedText.toLowerCase().startsWith(qLower);
          final bStart = b.matchedText.toLowerCase().startsWith(qLower);
          if (aStart && !bStart) return -1;
          if (!aStart && bStart) return 1;

          // 3. nearest tournament date
          final d = deltaPlayer(a).compareTo(deltaPlayer(b));
          if (d != 0) return d;

          // 4. alphabetical
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
  if (words.length == 1 || (words.length >= 2 && words.length <= 4)) {
    return words.every(
      (w) => w.isNotEmpty && w[0] == w[0].toUpperCase() && w.length >= 1,
    );
  }
  return false;
}
