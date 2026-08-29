import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GroupBroadcast writer attribution', () {
    GroupBroadcast fromWriter(Object? writer) => GroupBroadcast.fromJson({
      'id': 'event-1',
      'created_at': '2026-08-24T12:00:00.000Z',
      'name': 'Event',
      'search': const <String>[],
      'broadcast_writer': writer,
    });

    test('direct uses the exact approved public copy', () {
      final broadcast = fromWriter('chessever_direct');

      expect(broadcast.broadcastWriter, GroupBroadcast.chesseverDirectWriter);
      expect(broadcast.writerAttributionLabel, 'Powered by ChessEver');
    });

    test('null, absent, legacy and invalid values stay Lichess-powered', () {
      for (final value in <Object?>[
        null,
        '',
        'lichess_data_hub',
        'future_writer',
      ]) {
        final broadcast = fromWriter(value);
        expect(broadcast.broadcastWriter, GroupBroadcast.lichessDataHubWriter);
        expect(broadcast.writerAttributionLabel, 'Powered by Lichess');
      }
    });

    test('serialization preserves the normalized writer', () {
      expect(
        fromWriter('chessever_direct').toJson()['broadcast_writer'],
        'chessever_direct',
      );
    });
  });
}
