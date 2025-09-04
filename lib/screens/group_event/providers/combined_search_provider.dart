import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/repository/local_storage/group_broadcast/group_broadcast_local_storage.dart';
import 'package:chessever2/widgets/search/enhanced_group_broadcast_local_storage.dart';
import '../../../widgets/search/search_result_model.dart';
import '../group_event_screen.dart';

final combinedSearchProvider = FutureProvider.family<
  EnhancedSearchResult,
  String
>(
  (ref, query) async {
    final current = await ref
        .read(groupBroadcastLocalStorage(GroupEventCategory.current))
        .searchWithScoring(query);

    final upcoming = await ref
        .read(groupBroadcastLocalStorage(GroupEventCategory.upcoming))
        .searchWithScoring(query);

    final Map<String, SearchResult> uniqT = {};
    for (final r in [
      ...current.tournamentResults,
      ...upcoming.tournamentResults,
    ]) {
      final id = r.tournament.id;
      if (!uniqT.containsKey(id) || r.score > uniqT[id]!.score) uniqT[id] = r;
    }

    final Map<String, SearchResult> uniqP = {};
    for (final r in [...current.playerResults, ...upcoming.playerResults]) {
      final id = r.player!.id;
      if (!uniqP.containsKey(id) || r.score > uniqP[id]!.score) uniqP[id] = r;
    }

    return EnhancedSearchResult(
      tournamentResults:
          uniqT.values.toList()..sort((a, b) => b.score.compareTo(a.score)),
      playerResults:
          uniqP.values.toList()..sort((a, b) => b.score.compareTo(a.score)),
      allPlayers: [...current.allPlayers, ...upcoming.allPlayers],
    );
  },
);
