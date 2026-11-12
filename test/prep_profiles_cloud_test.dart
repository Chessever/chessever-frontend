import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_profiles_cloud.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/services/prep_cloud_sync.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/screens/my_prep/services/prep_watch.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// The mobile side of Prep sync: this app's profiles as rows, and rows as
// profiles here, against an in-memory server. The rules themselves are in
// prep_cloud_sync_test.dart.

class _Server implements PrepCloudRemote {
  final rows = <String, PrepCloudRow>{};
  bool reachable = true;

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
    rows[id] = PrepCloudRow(
      id: id,
      profile: jsonDecode(jsonEncode(profile)) as PrepJson,
      deleted: deleted,
    );
    return true;
  }
}

class _Repository extends PrepRepository {
  _Repository()
    : super(
        GamebaseRepository(
          Dio(),
          baseUrl: 'https://example.test',
          apiKey: 'test',
        ),
      );

  final synced = <String>[];

  @override
  Future<PrepAccount> refreshDetails(PrepAccount account) async => account;

  @override
  Future<PrepAccount> sync(
    PrepAccount account, {
    bool forceRefresh = false,
    bool frequent = false,
    PrepProgress? onProgress,
    CancelToken? cancelToken,
    bool reinstall = false,
  }) async {
    synced.add(account.key);
    return account.copyWith(gameCount: 12, lastSyncAtMs: 1);
  }
}

class _Stars extends PrepWatchRemote {
  Map<String, PrepWatched>? onServer = {};

  @override
  Future<Map<String, PrepWatched>?> watched() async => onServer;

  @override
  Future<bool> watch(PrepProfile profile) async => true;

  @override
  Future<bool> unwatch(String profileId) async => true;
}

const _lichess = PrepAccount(
  source: PrepSource.lichess,
  username: 'YagizKaan',
  title: 'GM',
  preferences: PrepDownloadPreferences(
    timeControls: {PrepTimeControl.blitz, PrepTimeControl.rapid},
  ),
);
const _chesscom = PrepAccount(source: PrepSource.chesscom, username: 'yagiz');
const _pgn = PrepAccount(source: PrepSource.manual, username: 'club.pgn');
const _profile = PrepProfile(
  id: 'opponent-1700000000000-0',
  kind: PrepKind.opponent,
  name: 'Yagiz Kaan Erdogmus',
  createdAtMs: 1700000000000,
  accounts: [_lichess],
);

/// A row as the desktop app writes one.
PrepJson _desktopRow(
  String name,
  List<PrepJson> accounts, {
  bool own = false,
}) => {
  'name': name,
  'kind': own ? 'mine' : 'opponent',
  'createdAtMs': 1,
  'accounts': accounts,
};

PrepJson _desktopAccount(
  String source,
  String username, {
  List<String> clocks = const [],
}) => {
  'source': source,
  'username': username,
  'preferences': {
    'timeControls': clocks,
    'range': 'all',
    'fromDate': null,
    'toDate': null,
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _Server server;
  late _Repository repo;
  late _Stars stars;
  late ProviderContainer container;
  var started = false;

  Future<void> settle() async {
    final loaded = Completer<void>();
    final sub = container.listen(prepProfilesProvider, (_, state) {
      if (!state.isLoading && !loaded.isCompleted) loaded.complete();
    }, fireImmediately: true);
    await loaded.future;
    sub.close();
    // Past the two seconds a change here waits before it is written.
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    final profiles = container.read(prepProfilesProvider.notifier);
    await profiles.debugDrainWatches();
    await profiles.debugDrainWrites();
  }

  /// This phone, holding [profiles], signed in as [user].
  Future<void> phone({
    List<PrepProfile> profiles = const [],
    String? user = 'reader',
  }) async {
    File('${directory.path}/prep/profiles.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'profiles': [for (final p in profiles) p.toJson()],
        }),
      );
    started = true;
    container = ProviderContainer(
      overrides: [
        prepCloudUserProvider.overrideWithValue(user),
        prepCloudRemoteProvider.overrideWith((ref, _) => server),
        prepRepositoryProvider.overrideWithValue(repo),
        prepWatchRemoteProvider.overrideWithValue(stars),
      ],
    );
    container.listen(prepCloudSyncProvider, (_, _) {});
    await settle();
  }

  /// Another device changed the server: the app comes back to the front.
  Future<void> resume() async {
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.inactive,
    );
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await settle();
  }

  List<PrepProfile> held() => container.read(prepProfilesProvider).requireValue;
  PrepProfilesNotifier store() => container.read(prepProfilesProvider.notifier);

  setUp(() {
    directory = Directory.systemTemp.createTempSync('prep_cloud_');
    server = _Server();
    repo = _Repository();
    stars = _Stars();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
  });

  tearDown(() async {
    if (started) {
      await store().debugDrainWrites();
      container.dispose();
      started = false;
    }
    repo.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  test('a profile already on this phone is written as a row: who it is and '
      'its sources, never its games or its PGN files', () async {
    await phone(
      profiles: [
        _profile.copyWith(
          accounts: [_lichess.copyWith(gameCount: 158, lastSyncAtMs: 9), _pgn],
        ),
      ],
    );
    final row = server.rows[_profile.id]!;
    expect(row.deleted, isFalse);
    expect(row.profile['name'], 'Yagiz Kaan Erdogmus');
    expect(row.profile['kind'], 'opponent');
    final account = (row.profile['accounts'] as List).single as Map;
    expect(account['source'], 'lichess');
    expect(account['username'], 'YagizKaan');
    expect(account['preferences']['timeControls'], ['blitz', 'rapid']);
    expect(account.containsKey('gameCount'), isFalse);
    // Nothing on the phone changed.
    expect(held().single.accounts, hasLength(2));
    expect(held().single.accounts.first.gameCount, 158);
    expect(repo.synced, isEmpty);
  });

  test('a profile made in the desktop app appears here and downloads its '
      'games', () async {
    server.rows['player-9-hikaru'] = PrepCloudRow(
      id: 'player-9-hikaru',
      profile: _desktopRow('Hikaru Nakamura', [
        _desktopAccount('chesscom', 'Hikaru', clocks: ['blitz']),
      ]),
    );
    await phone();
    final profile = held().single;
    expect(profile.id, 'player-9-hikaru');
    expect(profile.name, 'Hikaru Nakamura');
    expect(profile.kind, PrepKind.opponent);
    final account = profile.accounts.single;
    expect(account.key, 'chesscom:hikaru');
    expect(account.preferences.range, PrepDateRange.all);
    expect(account.preferences.timeControls, {PrepTimeControl.blitz});
    expect(account.gameCount, 12);
    expect(repo.synced, ['chesscom:hikaru']);
  });

  test('your own profile from the desktop app joins the one here', () async {
    const mine = PrepProfile(
      id: 'mine-1-0',
      kind: PrepKind.mine,
      name: 'Me',
      createdAtMs: 1,
      accounts: [PrepAccount(source: PrepSource.lichess, username: 'me_li')],
    );
    server.rows['player-2-me'] = PrepCloudRow(
      id: 'player-2-me',
      profile: _desktopRow('Me', [
        _desktopAccount('chesscom', 'me_cc'),
      ], own: true),
    );
    await phone(profiles: [mine]);
    final own = held().single;
    expect(own.id, 'mine-1-0');
    expect(own.kind, PrepKind.mine);
    expect(own.accounts.map((a) => a.key), ['lichess:me_li', 'chesscom:me_cc']);
    expect(repo.synced, ['chesscom:me_cc']);
    // One row for the reader's own profile, holding both.
    expect(server.rows.keys, ['player-2-me']);
    expect(server.rows['player-2-me']!.profile['accounts'], hasLength(2));
  });

  test('a source added, changed and removed in the desktop app follows '
      'here', () async {
    await phone(
      profiles: [
        _profile.copyWith(accounts: [_lichess, _chesscom]),
      ],
    );
    final row = server.rows[_profile.id]!.profile;
    final accounts = [...row['accounts'] as List];
    // The desktop drops Chess.com, narrows Lichess to classical.
    server.rows[_profile.id] = PrepCloudRow(
      id: _profile.id,
      profile: {
        ...row,
        'name': 'Yagiz K. Erdogmus',
        'accounts': [
          {
            ...accounts.first as Map,
            'preferences': {
              'timeControls': ['classical'],
              'range': 'all',
              'fromDate': null,
              'toDate': null,
            },
          },
        ],
      },
    );
    await resume();
    final profile = held().single;
    expect(profile.name, 'Yagiz K. Erdogmus');
    expect(profile.accounts.map((a) => a.key), ['lichess:yagizkaan']);
    expect(profile.accounts.single.preferences.timeControls, {
      PrepTimeControl.classical,
    });
    expect(profile.accounts.single.preferences.range, PrepDateRange.all);
    // It was applied, not written back.
    expect(server.rows[_profile.id]!.profile['name'], 'Yagiz K. Erdogmus');
    expect(server.rows[_profile.id]!.profile['accounts'], hasLength(1));
  });

  test('a profile deleted in the desktop app is removed here; one holding '
      'PGN files stays', () async {
    final withFiles = PrepProfile.fromJson({
      ..._profile.copyWith(accounts: [_chesscom, _pgn]).toJson(),
      'id': 'opponent-2-0',
      'name': 'Club rival',
    })!;
    await phone(profiles: [_profile, withFiles]);
    for (final id in [_profile.id, withFiles.id]) {
      server.rows[id] = PrepCloudRow(
        id: id,
        profile: server.rows[id]!.profile,
        deleted: true,
      );
    }
    await resume();
    expect(held().map((p) => p.id), [withFiles.id]);
    expect(held().single.accounts, hasLength(2));
  });

  test('deleting a profile here marks its row deleted, and it is not '
      'brought back', () async {
    await phone(profiles: [_profile]);
    await store().delete(_profile.id);
    await settle();
    expect(server.rows[_profile.id]!.deleted, isTrue);
    await resume();
    expect(held(), isEmpty);
  });

  test('a change made here is written', () async {
    await phone(profiles: [_profile]);
    store().attach(_profile.id, [_chesscom]);
    await settle();
    expect(
      (server.rows[_profile.id]!.profile['accounts'] as List).map(
        (a) => (a as Map)['source'],
      ),
      ['lichess', 'chesscom'],
    );
  });

  test('a player kept only for their games (Players) has no row', () async {
    await phone(
      profiles: [
        PrepProfile.fromJson({..._profile.toJson(), 'kind': 'favorite'})!,
      ],
    );
    expect(server.rows, isEmpty);
  });

  test('signed out, nothing is read or written', () async {
    await phone(profiles: [_profile], user: null);
    expect(server.rows, isEmpty);
    expect(held().single.id, _profile.id);
  });

  test('on a shared phone, one reader\'s profiles never go to the next '
      'reader\'s account', () async {
    await phone(profiles: [_profile]);
    expect(server.rows.keys, [_profile.id]);
    container.dispose();
    // Another reader signs in on the same phone.
    final theirs = _Server();
    container = ProviderContainer(
      overrides: [
        prepCloudUserProvider.overrideWithValue('someone-else'),
        prepCloudRemoteProvider.overrideWith((ref, _) => theirs),
        prepRepositoryProvider.overrideWithValue(repo),
        prepWatchRemoteProvider.overrideWithValue(stars),
      ],
    );
    container.listen(prepCloudSyncProvider, (_, _) {});
    await settle();
    expect(theirs.rows, isEmpty);
    expect(held().single.id, _profile.id);
  });

  test('a profile rebuilt here that is starred on the device that made it '
      'shows its star', () async {
    server.rows[_profile.id] = PrepCloudRow(
      id: _profile.id,
      profile: prepCloudProfile(_profile),
    );
    stars.onServer = {
      _profile.id: const PrepWatched(name: 'Yagiz Kaan Erdogmus'),
    };
    await phone();
    expect(held().single.watching, isTrue);
  });
}
