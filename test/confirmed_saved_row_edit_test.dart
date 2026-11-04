import 'package:chessever2/utils/confirmed_saved_row_edit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/saved_smart_event_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SavedRowsTransport transport;
  setUp(() {
    transport = SavedRowsTransport([]);
  });
  tearDown(() async {
    await transport.client.dispose();
  });

  final oldPin = <String, dynamic>{
    'id': 'fixture-row',
    'created_at': fixtureStamp.toIso8601String(),
    'kind': 'smartEvent',
    'target_id': 'old-criteria',
    'title': 'Study',
    'subtitle': 'My note',
    'sort_index': 17.0,
    'open_count': 4,
    'last_opened_at': fixtureStamp.toIso8601String(),
    'params': {
      'request': {'ecoCode': 'B90'},
      'custom': true,
    },
  };
  Map<String, dynamic> seedPin(Map<String, dynamic> pin) => {
    ...pin, 'user_id': fixtureOwner,
    // Postgres may serialize UTC differently from Dart. It is the same instant.
    'last_opened_at': '2026-01-01T00:00:00+00:00',
  };
  Future<void> write(
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
  ) => writeConfirmedSavedRow(
    client: transport.client,
    userId: fixtureOwner,
    table: 'user_space_shortcuts',
    keyColumns: const ['kind', 'target_id'],
    before: before,
    after: after,
  );

  test(
    'remote shortcut retarget updates identity/params in place with history and metadata',
    () async {
      transport.tables['user_space_shortcuts'] = [seedPin(oldPin)];
      final after = {
        ...oldPin,
        'target_id': 'new-criteria',
        'params': {
          'request': {'ecoCode': 'C42'},
          'custom': true,
        },
      };
      await write(oldPin, after);
      final rows = transport.tables['user_space_shortcuts']!;
      expect(rows, hasLength(1));
      expect(rows.single['target_id'], 'new-criteria');
      expect(rows.single['id'], 'fixture-row');
      expect(rows.single['sort_index'], 17);
      expect(rows.single['open_count'], 4);
      expect(rows.single['params'], after['params']);
      await write(oldPin, after); // successful ambiguous-reply retry is a no-op
      expect(transport.writes, ['PATCH:user_space_shortcuts']);
      await write(after, oldPin); // guarded compensation
      expect(rows.single['target_id'], 'old-criteria');
    },
  );

  test(
    'a concurrent change after GET makes CAS affect zero rows, never overwrites it',
    () async {
      transport.tables['user_space_shortcuts'] = [seedPin(oldPin)];
      transport.beforeWrite = (_) async {
        transport.tables['user_space_shortcuts']!.single['title'] =
            'Changed elsewhere';
      };
      await expectLater(
        write(oldPin, {...oldPin, 'target_id': 'new-criteria'}),
        throwsA(isA<SavedRowConflict>()),
      );
      expect(
        transport.tables['user_space_shortcuts']!.single['title'],
        'Changed elsewhere',
      );
      expect(
        transport.tables['user_space_shortcuts']!.single['target_id'],
        'old-criteria',
      );
    },
  );

  test(
    'deleting a duplicate source retains the existing target unchanged; rollback is idempotent',
    () async {
      final target = {
        ...oldPin,
        'id': 'target-fixture-row',
        'target_id': 'target-criteria',
        'title': 'Keep target',
      };
      transport.tables['user_space_shortcuts'] = [
        seedPin(oldPin),
        seedPin(target),
      ];
      await write(oldPin, null);
      expect(
        transport.tables['user_space_shortcuts']!.single['title'],
        'Keep target',
      );
      await write(null, oldPin);
      await write(null, oldPin);
      expect(transport.tables['user_space_shortcuts'], hasLength(2));
      expect(
        transport.tables['user_space_shortcuts']!
            .where((s) => s['target_id'] == 'old-criteria')
            .single['id'],
        'fixture-row',
      );
      expect(transport.writes, [
        'DELETE:user_space_shortcuts',
        'POST:user_space_shortcuts',
      ]);
    },
  );

  test(
    'lost remote shortcut reply can be compensated without repeating the forward write',
    () async {
      transport.tables['user_space_shortcuts'] = [seedPin(oldPin)];
      final after = {...oldPin, 'target_id': 'new-criteria'};
      var fail = true;
      transport.afterWrite = (_) async {
        if (fail) {
          fail = false;
          throw StateError('Fixture lost reply');
        }
      };
      await expectLater(write(oldPin, after), throwsStateError);
      await write(after, oldPin);
      expect(
        transport.tables['user_space_shortcuts']!.single['target_id'],
        'old-criteria',
      );
      expect(transport.writes, [
        'PATCH:user_space_shortcuts',
        'PATCH:user_space_shortcuts',
      ]);
    },
  );
}
