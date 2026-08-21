import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/widgets/search/enhanced_group_broadcast_local_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'background tournament scoring preserves the exact matcher output',
    () async {
      final broadcasts = [
        GroupBroadcast(
          id: 'one',
          createdAt: DateTime.utc(2026, 8, 21),
          name: 'Norway Chess',
          search: const ['Magnus Carlsen', 'Norway Chess Championship'],
        ),
        GroupBroadcast(
          id: 'two',
          createdAt: DateTime.utc(2026, 8, 21),
          name: 'Titled Tuesday',
          search: const ['Hikaru Nakamura'],
        ),
        GroupBroadcast(
          id: 'three',
          createdAt: DateTime.utc(2026, 8, 21),
          name: 'Candidates Tournament',
          search: const ['FIDE Candidates'],
        ),
      ];

      for (final query in [
        'Magnus Carlsen',
        'titled',
        'FIDE Candidates',
        'does not exist',
      ]) {
        final background = await scoreTournamentBroadcastsInBackground(
          query: query,
          broadcasts: broadcasts,
        );
        final direct = <TournamentSearchScore>[];
        for (var index = 0; index < broadcasts.length; index++) {
          final broadcast = broadcasts[index];
          final match = bestFlexibleEventSearchMatch(
            query: query.toLowerCase().trim(),
            name: broadcast.name,
            aliases: broadcast.search,
          );
          if (match.score > 10) {
            direct.add(
              TournamentSearchScore(
                index: index,
                score: match.score,
                matchedText: match.matchedText,
              ),
            );
          }
        }

        expect(
          background.map((hit) => hit.index),
          direct.map((hit) => hit.index),
          reason: query,
        );
        expect(
          background.map((hit) => hit.score),
          direct.map((hit) => hit.score),
          reason: query,
        );
        expect(
          background.map((hit) => hit.matchedText),
          direct.map((hit) => hit.matchedText),
          reason: query,
        );
      }
    },
  );
}
