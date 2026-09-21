import 'package:chessever2/repository/supabase/round/round_metadata_changes.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> round(String id) => {
  'id': id,
  'slug': 'round-6',
  'tour_id': 'olympiad',
  'tour_slug': 'olympiad',
  'name': 'Round 6',
  'created_at': '2026-09-21T09:00:00Z',
  'starts_at': null,
  'url': 'https://lichess.org/broadcast/olympiad/round-6/$id',
};

void main() {
  test('heartbeat burst does not reload an unchanged round catalog', () {
    final changes = RoundMetadataChanges();
    final accepted = <String>[];
    for (var tick = 0; tick < 100; tick++) {
      for (final id in ['open', 'women']) {
        if (changes.accept({
          ...round(id),
          'updated_at': '$tick',
          'poll_count': tick,
        }, deleted: false)) {
          accepted.add(id);
        }
      }
    }
    expect(accepted, ['open', 'women']);
  });

  test('every field consumed by Round triggers a new reconciliation', () {
    expect(
      Round.fromJson(round('open')).toJson().keys.toSet(),
      RoundMetadataChanges.columns.toSet(),
    );
    for (final column in RoundMetadataChanges.columns) {
      final changes = RoundMetadataChanges();
      expect(changes.accept(round('open'), deleted: false), isTrue);
      expect(
        changes.accept({...round('open'), column: 'changed'}, deleted: false),
        isTrue,
        reason: column,
      );
    }
  });

  test(
    'deletion, reinsertion, incomplete payload and reconnect are retained',
    () {
      final changes = RoundMetadataChanges();
      final record = round('open');
      expect(changes.accept(record, deleted: false), isTrue);
      expect(changes.accept(record, deleted: false), isFalse);
      expect(changes.accept({'id': 'open'}, deleted: true), isTrue);
      expect(changes.accept(record, deleted: false), isTrue);
      expect(changes.accept({'id': 'open'}, deleted: false), isTrue);
      expect(changes.accept(record, deleted: false), isTrue);
      changes.reset();
      expect(changes.accept(record, deleted: false), isTrue);
      expect(
        changes.accept({
          ...record,
          'starts_at': '2026-09-21T13:00:00Z',
        }, deleted: false),
        isTrue,
      );
      expect(changes.accept(record, deleted: false), isTrue);
    },
  );
}
