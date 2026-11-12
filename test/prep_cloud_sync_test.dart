import 'dart:convert';

import 'package:chessever2/screens/my_prep/services/prep_cloud_sync.dart';
import 'package:flutter_test/flutter_test.dart';

// The engine that keeps Prep profiles in step between devices, against an
// in-memory server and in-memory devices. The apps' own adapters are tested
// with the apps.

class _Server implements PrepCloudRemote {
  final rows = <String, PrepCloudRow>{};
  bool reachable = true;
  int writes = 0;

  @override
  Future<List<PrepCloudRow>?> fetch() async =>
      reachable ? rows.values.toList() : null;

  @override
  Future<bool> write(
    String id,
    PrepJson profile, {
    required bool deleted,
  }) async {
    if (!reachable) return false;
    writes++;
    rows[id] = PrepCloudRow(
      id: id,
      profile: jsonDecode(jsonEncode(profile)) as PrepJson,
      deleted: deleted,
    );
    return true;
  }
}

/// A device holding profiles as rows' JSON. [desktop] cannot tell a rolling
/// date range from "all dates", nor an opponent from a favourite.
class _Device implements PrepCloudDevice {
  _Device(this.server, {this.desktop = false});

  final _Server server;
  final bool desktop;
  final held = <String, PrepJson>{};
  final pinned = <String>{};
  bool loaded = true;
  late final sync = PrepCloudSync(
    remote: server,
    device: this,
    state: PrepCloudState(),
    save: (_) async {},
  );

  Future<void> pass() => sync.pass();

  void add(String id, String name, List<PrepJson> accounts, {String? kind}) {
    held[id] = {'name': name, 'kind': kind ?? 'opponent', 'accounts': accounts};
  }

  Future<void> delete(String id) async {
    held.remove(id);
    await sync.forget(id);
  }

  List<String> keys(String id) => [
    for (final a in prepCloudAccounts(held[id])) prepCloudAccountKey(a),
  ];

  @override
  Map<String, PrepJson>? profiles() => loaded
      ? {
          for (final e in held.entries)
            e.key: jsonDecode(jsonEncode(e.value)) as PrepJson,
        }
      : null;

  @override
  String preferencesCore(Object? preferences) {
    final p = preferences is Map ? preferences : const {};
    final custom = p['range'] == 'custom';
    return jsonEncode([
      p['timeControls'] ?? const [],
      if (!desktop) p['range'] ?? 'year',
      if (custom) p['fromDate'],
      if (custom) p['toDate'],
    ]);
  }

  @override
  String kindCore(Object? kind) =>
      kind == 'mine' ? 'mine' : (desktop ? 'other' : 'opponent');

  @override
  Future<bool> create(String id, PrepJson profile) async {
    if (held.containsKey(id)) return false;
    held[id] = jsonDecode(jsonEncode(profile)) as PrepJson;
    return true;
  }

  @override
  Future<void> apply(String id, PrepJson profile) async {
    held[id] = {
      ...held[id]!,
      'name': profile['name'],
      'kind': profile['kind'],
      'accounts': jsonDecode(jsonEncode(profile['accounts'])),
    };
  }

  @override
  Future<bool> remove(String id) async {
    if (pinned.contains(id)) return false;
    held.remove(id);
    return true;
  }
}

PrepJson _account(
  String source,
  String username, {
  String range = 'year',
  List<String> clocks = const ['blitz', 'rapid'],
}) => {
  'source': source,
  'username': username,
  'preferences': {
    'timeControls': clocks,
    'range': range,
    'fromDate': null,
    'toDate': null,
  },
};

void main() {
  late _Server server;
  late _Device phone;
  late _Device desktop;

  setUp(() {
    server = _Server();
    phone = _Device(server);
    desktop = _Device(server, desktop: true);
  });

  /// Both devices, twice: what one writes the other reads.
  Future<void> both() async {
    for (var i = 0; i < 2; i++) {
      await phone.pass();
      await desktop.pass();
    }
  }

  test('a profile made on the phone appears on the desktop, under the same '
      'id', () async {
    phone.add('opponent-1', 'Yagiz', [_account('lichess', 'YagizKaan')]);
    await both();
    expect(desktop.held.keys, ['opponent-1']);
    expect(desktop.held['opponent-1']!['name'], 'Yagiz');
    expect(desktop.keys('opponent-1'), ['lichess:yagizkaan']);
    expect(server.rows.keys, ['opponent-1']);
  });

  test('and one made on the desktop appears on the phone', () async {
    desktop.add('player-9-hikaru', 'Hikaru', [_account('chesscom', 'Hikaru')]);
    await both();
    expect(phone.held.keys, ['player-9-hikaru']);
    expect(phone.keys('player-9-hikaru'), ['chesscom:hikaru']);
  });

  test('two devices already in step write nothing', () async {
    phone.add('opponent-1', 'Yagiz', [_account('lichess', 'YagizKaan')]);
    await both();
    final writes = server.writes;
    await both();
    await both();
    expect(server.writes, writes);
    expect(phone.sync.dirty, isFalse);
    expect(desktop.sync.dirty, isFalse);
  });

  test('a source added on one device is added on the other', () async {
    phone.add('opponent-1', 'Yagiz', [_account('lichess', 'YagizKaan')]);
    await both();
    desktop.held['opponent-1']!['accounts'] = [
      _account('lichess', 'YagizKaan'),
      _account('chesscom', 'yagiz'),
    ];
    expect(desktop.sync.dirty, isTrue);
    await both();
    expect(phone.keys('opponent-1'), ['lichess:yagizkaan', 'chesscom:yagiz']);
  });

  test('a source removed on one device is removed on the other', () async {
    phone.add('opponent-1', 'Yagiz', [
      _account('lichess', 'YagizKaan'),
      _account('chesscom', 'yagiz'),
    ]);
    await both();
    phone.held['opponent-1']!['accounts'] = [_account('lichess', 'YagizKaan')];
    await both();
    expect(desktop.keys('opponent-1'), ['lichess:yagizkaan']);
  });

  test('a rename reaches the other device', () async {
    phone.add('opponent-1', 'Yagiz', [_account('lichess', 'YagizKaan')]);
    await both();
    desktop.held['opponent-1']!['name'] = 'Yagiz Kaan Erdogmus';
    await both();
    expect(phone.held['opponent-1']!['name'], 'Yagiz Kaan Erdogmus');
  });

  test('a profile deleted on one device is removed from the other, and '
      'never written back', () async {
    phone.add('opponent-1', 'Yagiz', [_account('lichess', 'YagizKaan')]);
    await both();
    await desktop.delete('opponent-1');
    await both();
    expect(phone.held, isEmpty);
    expect(desktop.held, isEmpty);
    expect(server.rows['opponent-1']!.deleted, isTrue);
    await both();
    expect(phone.held, isEmpty);
    expect(desktop.held, isEmpty);
  });

  test('a profile holding imported files on a device stays there when it '
      'is deleted elsewhere', () async {
    phone.add('opponent-1', 'Yagiz', [_account('lichess', 'YagizKaan')]);
    await both();
    phone.pinned.add('opponent-1');
    await desktop.delete('opponent-1');
    await both();
    expect(phone.held.keys, ['opponent-1']);
    expect(desktop.held, isEmpty);
  });

  test('a profile deleted on one device while it was changed on the other '
      'lives on', () async {
    phone.add('opponent-1', 'Yagiz', [_account('lichess', 'YagizKaan')]);
    await both();
    await desktop.delete('opponent-1');
    await desktop.pass();
    phone.held['opponent-1']!['accounts'] = [
      _account('lichess', 'YagizKaan'),
      _account('chesscom', 'yagiz'),
    ];
    await both();
    expect(phone.keys('opponent-1'), hasLength(2));
    expect(desktop.keys('opponent-1'), hasLength(2));
    expect(server.rows['opponent-1']!.deleted, isFalse);
  });

  test('a deletion made offline is told to the server later', () async {
    phone.add('opponent-1', 'Yagiz', [_account('lichess', 'YagizKaan')]);
    await both();
    server.reachable = false;
    await phone.delete('opponent-1');
    await phone.pass();
    expect(server.rows['opponent-1']!.deleted, isFalse);
    server.reachable = true;
    await both();
    expect(desktop.held, isEmpty);
    expect(phone.held, isEmpty);
  });

  test(
    'the same player added on both before they synced becomes one row; '
    'each device keeps its own profile, and both hold every source',
    () async {
      phone.add('opponent-1', 'Yagiz', [_account('lichess', 'YagizKaan')]);
      desktop.add('player-7-yagiz', 'Yagiz K', [
        _account('lichess', 'yagizkaan'),
        _account('chesscom', 'yagiz'),
      ]);
      await both();
      expect(phone.held.keys, ['opponent-1']);
      expect(desktop.held.keys, ['player-7-yagiz']);
      expect(server.rows.keys, ['opponent-1']);
      expect(phone.keys('opponent-1'), ['lichess:yagizkaan', 'chesscom:yagiz']);
      expect(desktop.keys('player-7-yagiz').toSet(), {
        'lichess:yagizkaan',
        'chesscom:yagiz',
      });
      // Afterwards a removal on one is a removal on the other.
      desktop.held['player-7-yagiz']!['accounts'] = [
        _account('lichess', 'yagizkaan'),
      ];
      await both();
      expect(phone.keys('opponent-1'), ['lichess:yagizkaan']);
    },
  );

  test('your own profile on both devices is one profile, with the accounts '
      'of both', () async {
    phone.add('mine-1', 'Me', [_account('lichess', 'me_li')], kind: 'mine');
    desktop.add('player-2-me', 'Me', [
      _account('chesscom', 'me_cc'),
    ], kind: 'mine');
    await both();
    expect(phone.held.keys, ['mine-1']);
    expect(desktop.held.keys, ['player-2-me']);
    expect(phone.keys('mine-1').toSet(), {'lichess:me_li', 'chesscom:me_cc'});
    expect(desktop.keys('player-2-me').toSet(), {
      'lichess:me_li',
      'chesscom:me_cc',
    });
    expect(server.rows, hasLength(1));
  });

  test('the desktop, which has no rolling date range, never rewrites the '
      'phone\'s, and only its own changes come back', () async {
    phone.add('opponent-1', 'Yagiz', [
      _account('lichess', 'YagizKaan', range: 'months3'),
    ]);
    await both();
    // The desktop adds a source: the first one's range is kept as written.
    desktop.held['opponent-1']!['accounts'] = [
      _account('lichess', 'YagizKaan', range: 'all'),
      _account('chesscom', 'yagiz', range: 'all'),
    ];
    await both();
    final accounts = prepCloudAccounts(phone.held['opponent-1']);
    expect(accounts.first['preferences']['range'], 'months3');
    expect(accounts.last['source'], 'chesscom');
    // The desktop changes the clocks: that is its own change.
    desktop.held['opponent-1']!['accounts'] = [
      _account('lichess', 'YagizKaan', range: 'all', clocks: ['classical']),
      _account('chesscom', 'yagiz', range: 'all'),
    ];
    await both();
    expect(
      prepCloudAccounts(
        phone.held['opponent-1'],
      ).first['preferences']['timeControls'],
      ['classical'],
    );
  });

  test(
    'keys another app wrote are kept when this one writes the row',
    () async {
      phone.add('opponent-1', 'Yagiz', [
        {
          ..._account('lichess', 'YagizKaan'),
          'playerAliases': ['yk'],
        },
      ]);
      phone.held['opponent-1']!['favoriteId'] = 'fav-1';
      await both();
      desktop.held['opponent-1'] = {
        'name': 'Yagiz K',
        'kind': 'opponent',
        'accounts': [_account('lichess', 'YagizKaan', range: 'all')],
      };
      await both();
      final row = server.rows['opponent-1']!.profile;
      expect(row['name'], 'Yagiz K');
      expect(row['favoriteId'], 'fav-1');
      expect((row['accounts'] as List).single['playerAliases'], ['yk']);
    },
  );

  test('nothing is concluded while the server cannot be read or the '
      'profiles here are not loaded', () async {
    phone.add('opponent-1', 'Yagiz', [_account('lichess', 'YagizKaan')]);
    await both();
    server.reachable = false;
    desktop.held.clear();
    await desktop.pass();
    server.reachable = true;
    desktop.loaded = false;
    await desktop.pass();
    expect(server.rows['opponent-1']!.deleted, isFalse);
    // Its data was cleared, not deleted by the reader: it comes back.
    desktop.loaded = true;
    await both();
    expect(desktop.held.keys, ['opponent-1']);
    expect(phone.held.keys, ['opponent-1']);
  });

  test(
    'a profile with nothing another device could download is not '
    'written, and losing its last such source removes it elsewhere',
    () async {
      phone.add('opponent-1', 'Club', []);
      await both();
      expect(server.rows, isEmpty);
      phone.held['opponent-1']!['accounts'] = [_account('lichess', 'club')];
      await both();
      expect(desktop.held.keys, ['opponent-1']);
      phone.held['opponent-1']!['accounts'] = [];
      await both();
      expect(desktop.held, isEmpty);
      expect(phone.held.keys, ['opponent-1']);
    },
  );

  test('what a device remembers survives a restart', () {
    final state = PrepCloudState(
      rowOf: {'a': 'b'},
      base: {'a': 'core'},
      deletes: {'c'},
    );
    final back = PrepCloudState.fromJson(
      jsonDecode(jsonEncode(state.toJson())),
    );
    expect(back.rowOf, {'a': 'b'});
    expect(back.base, {'a': 'core'});
    expect(back.deletes, {'c'});
  });
}
