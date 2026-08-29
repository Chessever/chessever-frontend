import 'dart:async';

import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

GroupBroadcast _broadcast(String writer) => GroupBroadcast.fromJson({
  'id': 'gb-event-1',
  'created_at': '2026-08-24T12:00:00.000Z',
  'name': 'Event',
  'search': const <String>[],
  'broadcast_writer': writer,
});

void main() {
  test(
    'canonical base row overrides a legacy view row for attribution',
    () async {
      final container = ProviderContainer(
        overrides: [
          selectedBroadcastModelProvider.overrideWith(
            (ref) => _broadcast(GroupBroadcast.lichessDataHubWriter),
          ),
          canonicalSelectedBroadcastProvider.overrideWith(
            (ref) async => _broadcast(GroupBroadcast.chesseverDirectWriter),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(canonicalSelectedBroadcastProvider.future);

      expect(
        container.read(selectedBroadcastWriterAttributionProvider),
        'Powered by ChessEver',
      );
    },
  );

  test('selected row remains the safe label while canonical row loads', () {
    final container = ProviderContainer(
      overrides: [
        selectedBroadcastModelProvider.overrideWith(
          (ref) => _broadcast(GroupBroadcast.lichessDataHubWriter),
        ),
        canonicalSelectedBroadcastProvider.overrideWith(
          (ref) => Completer<GroupBroadcast?>().future,
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(selectedBroadcastWriterAttributionProvider),
      'Powered by Lichess',
    );
  });
}
