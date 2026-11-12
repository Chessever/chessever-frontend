import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_space_shortcut.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/screens/my_prep/services/prep_watch.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Prep profiles are kept on the device and My Space pins on the account, so
// a pin reaches devices its profile never did. These cover what keeps such
// a card working: the pin carries the profile's sources, pins saved before
// they did are filled in by the device that holds the profile, and a device
// that lacks the profile rebuilds it.

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

class _Store extends SpaceShortcutsNotifier {
  _Store(this.pins);
  final List<SpaceShortcut> pins;

  @override
  Future<List<SpaceShortcut>> build() async => pins;
}

class _Remote extends PrepWatchRemote {
  final calls = <String>[];
  Map<String, PrepWatched>? onServer = {};

  @override
  Future<Map<String, PrepWatched>?> watched() async => onServer;

  @override
  Future<bool> watch(PrepProfile profile) async {
    calls.add('watch ${profile.id}');
    return true;
  }

  @override
  Future<bool> unwatch(String profileId) async {
    calls.add('unwatch $profileId');
    return true;
  }
}

const _lichess = PrepAccount(
  source: PrepSource.lichess,
  username: 'YagizKaan',
  displayName: 'Yagiz Kaan Erdogmus',
  title: 'GM',
  preferences: PrepDownloadPreferences(
    timeControls: {PrepTimeControl.blitz, PrepTimeControl.rapid},
  ),
);
const _pgn = PrepAccount(source: PrepSource.manual, username: 'club.pgn');
const _profile = PrepProfile(
  id: 'opponent-1700000000000-0',
  kind: PrepKind.opponent,
  name: 'Yagiz Kaan Erdogmus',
  createdAtMs: 1700000000000,
  accounts: [_lichess],
);

/// The pin as a build before pins carried the profile saved it.
SpaceShortcut _oldPin(PrepProfile profile) => SpaceShortcut.draft(
  kind: SpaceShortcutKind.prepProfile,
  targetId: profile.id,
  title: profile.name,
  subtitle: 'Prep',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late _Repository repo;
  late _Remote remote;
  late ProviderContainer container;
  var started = false;

  /// Lets the loads, the server read and the downloads run out.
  Future<void> settle() async {
    final loaded = Completer<void>();
    final sub = container.listen(prepProfilesProvider, (_, state) {
      if (!state.isLoading && !loaded.isCompleted) loaded.complete();
    }, fireImmediately: true);
    await loaded.future;
    sub.close();
    await container.read(spaceShortcutsProvider.future);
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    final profiles = container.read(prepProfilesProvider.notifier);
    await profiles.debugDrainWatches();
    await profiles.debugDrainWrites();
  }

  /// A device holding [profiles], signed in to an account whose My Space
  /// holds [pins], settled.
  Future<void> device({
    List<PrepProfile> profiles = const [],
    List<SpaceShortcut> pins = const [],
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
        currentUserProvider.overrideWithValue(null),
        prepRepositoryProvider.overrideWithValue(repo),
        prepWatchRemoteProvider.overrideWithValue(remote),
        spaceShortcutsProvider.overrideWith(() => _Store(pins)),
      ],
    );
    container.listen(prepSpaceSyncProvider, (_, _) {});
    await settle();
  }

  List<PrepProfile> held() => container.read(prepProfilesProvider).requireValue;
  List<SpaceShortcut> pinned() =>
      container.read(spaceShortcutsProvider).requireValue;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    directory = Directory.systemTemp.createTempSync('prep_space_sync_');
    repo = _Repository();
    remote = _Remote();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => directory.path,
        );
  });

  tearDown(() async {
    if (started) {
      await container.read(prepProfilesProvider.notifier).debugDrainWrites();
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

  test('a new pin carries the profile, without its games or PGN files', () {
    final pin = prepProfileSpaceDraft(
      _profile.copyWith(
        accounts: [_lichess.copyWith(gameCount: 158, lastSyncAtMs: 9), _pgn],
      ),
    );
    final carried = prepProfileFromPin(pin)!;
    expect(carried.id, _profile.id);
    expect(carried.kind, PrepKind.opponent);
    expect(carried.name, 'Yagiz Kaan Erdogmus');
    expect(carried.accounts.single.key, _lichess.key);
    expect(carried.accounts.single.title, 'GM');
    expect(carried.accounts.single.preferences, _lichess.preferences);
    expect(carried.accounts.single.gameCount, 0);
    expect(carried.accounts.single.lastSyncAtMs, isNull);
  });

  test('a profile of PGN files only has nothing another device can '
      'rebuild', () {
    final pin = prepProfileSpaceDraft(_profile.copyWith(accounts: [_pgn]));
    expect(pin.params, isEmpty);
    expect(prepProfileFromPin(pin), isNull);
  });

  test('the device that holds a profile fills in a pin saved before pins '
      'carried it', () async {
    await device(profiles: [_profile], pins: [_oldPin(_profile)]);
    expect(
      prepProfileFromPin(pinned().single)!.accounts.single.key,
      _lichess.key,
    );
    // Nothing here was rebuilt or downloaded.
    expect(held().single.toJson(), _profile.toJson());
    expect(repo.synced, isEmpty);
  });

  test('a device without the profile rebuilds it from the pin, under the '
      'same id, and downloads its games', () async {
    await device(pins: [prepProfileSpaceDraft(_profile)]);
    final profile = held().single;
    expect(profile.id, _profile.id);
    expect(profile.name, _profile.name);
    expect(profile.kind, PrepKind.opponent);
    expect(profile.accounts.single.key, _lichess.key);
    expect(profile.accounts.single.gameCount, 12);
    expect(repo.synced, [_lichess.key]);
    // Not starred there, not starred here.
    expect(profile.watching, isFalse);
    expect(remote.calls, isEmpty);
    expect(prepProfileForPin(pinned().single, held()), same(profile));
  });

  test('a starred profile is rebuilt starred, even from a pin saved before '
      'pins carried it', () async {
    remote.onServer = {
      _profile.id: const PrepWatched(
        name: 'Yagiz Kaan Erdogmus',
        title: 'GM',
        kind: PrepKind.opponent,
        accounts: [_lichess],
      ),
    };
    await device(pins: [_oldPin(_profile)]);
    final profile = held().single;
    expect(profile.id, _profile.id);
    expect(profile.watching, isTrue);
    expect(profile.accounts.single.key, _lichess.key);
    expect(repo.synced, [_lichess.key]);
    // The pin now carries it for the next device.
    expect(prepProfileFromPin(pinned().single), isNotNull);
  });

  test('an old pin of an unstarred profile waits for the device that holds '
      'it', () async {
    await device(pins: [_oldPin(_profile)]);
    expect(held(), isEmpty);
    expect(pinned().single.params, isEmpty);
    expect(prepProfileForPin(pinned().single, held()), isNull);
  });

  test('nothing is rebuilt while the server cannot be read', () async {
    remote.onServer = null;
    await device(pins: [prepProfileSpaceDraft(_profile)]);
    expect(held(), isEmpty);
    expect(repo.synced, isEmpty);
  });

  test('a pin made on another device for a player already here opens the '
      'profile here instead of adding a second one', () async {
    final here = _profile.copyWith(name: 'Yagiz').copyWithId('opponent-2-0');
    await device(profiles: [here], pins: [prepProfileSpaceDraft(_profile)]);
    expect(held().single.id, here.id);
    expect(prepProfileForPin(pinned().single, held())!.id, here.id);
    expect(repo.synced, isEmpty);
  });

  test('your own profile from another device joins the one here: one '
      'profile of your own, holding the accounts of both', () async {
    const here = PrepProfile(
      id: 'mine-2-0',
      kind: PrepKind.mine,
      name: 'Me',
      createdAtMs: 2,
      accounts: [PrepAccount(source: PrepSource.chesscom, username: 'me_cc')],
    );
    const there = PrepProfile(
      id: 'mine-1-0',
      kind: PrepKind.mine,
      name: 'Me',
      createdAtMs: 1,
      accounts: [
        PrepAccount(source: PrepSource.lichess, username: 'me_li'),
        PrepAccount(source: PrepSource.chesscom, username: 'me_cc'),
      ],
    );
    await device(profiles: [here], pins: [_oldPin(here)]);
    // The other device's card arrives.
    await container
        .read(spaceShortcutsProvider.notifier)
        .add(prepProfileSpaceDraft(there));
    await settle();
    final own = held().single;
    expect(own.id, here.id);
    expect(own.accounts.map((a) => a.key), ['chesscom:me_cc', 'lichess:me_li']);
    // Both cards open it.
    for (final pin in pinned()) {
      expect(prepProfileForPin(pin, held())!.id, here.id);
    }
  });

  test('changing a profile here updates what its pin carries', () async {
    await device(profiles: [_profile], pins: [prepProfileSpaceDraft(_profile)]);
    const chesscom = PrepAccount(
      source: PrepSource.chesscom,
      username: 'yagizkaan',
    );
    container.read(prepProfilesProvider.notifier).attach(_profile.id, [
      chesscom,
    ]);
    await settle();
    expect(prepProfileFromPin(pinned().single)!.accounts.map((a) => a.key), [
      _lichess.key,
      chesscom.key,
    ]);
  });

  test('deleting a profile takes its pin with it, so the pin never puts it '
      'back', () async {
    await device(profiles: [_profile], pins: [prepProfileSpaceDraft(_profile)]);
    await container.read(prepProfilesProvider.notifier).delete(_profile.id);
    await settle();
    expect(held(), isEmpty);
    expect(pinned(), isEmpty);
    expect(repo.synced, isEmpty);
  });

  test('the server\'s rows, one per account, read as starred profiles', () {
    final watched = prepWatchedFromRows([
      {
        'profile_id': 'mine-1-0',
        'profile_name': 'Me',
        'profile_title': null,
        'source': 'lichess',
        'username': 'me_li',
        'time_controls': ['blitz'],
      },
      {
        'profile_id': 'mine-1-0',
        'profile_name': 'Me',
        'source': 'chesscom',
        'username': 'me_cc',
        'time_controls': <String>[],
      },
    ]);
    final profile = watched['mine-1-0']!.asProfile('mine-1-0');
    // Rows written before the server kept the kind: the id still has it.
    expect(profile.kind, PrepKind.mine);
    expect(profile.watching, isTrue);
    expect(profile.accounts.map((a) => a.key), [
      'lichess:me_li',
      'chesscom:me_cc',
    ]);
    expect(profile.accounts.first.preferences.timeControls, {
      PrepTimeControl.blitz,
    });
  });
}

extension on PrepProfile {
  PrepProfile copyWithId(String id) =>
      PrepProfile.fromJson({...toJson(), 'id': id})!;
}
