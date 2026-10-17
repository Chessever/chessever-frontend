import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/services/prep_watch.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _chesscom = PrepAccount(
  source: PrepSource.chesscom,
  username: 'Hikaru',
  preferences: PrepDownloadPreferences(
    timeControls: {PrepTimeControl.rapid, PrepTimeControl.blitz},
  ),
);
const _lichess = PrepAccount(
  source: PrepSource.lichess,
  username: 'DrNykterstein',
);
const _database = PrepAccount(
  source: PrepSource.chessever,
  username: 'Carlsen, Magnus',
);
const _profile = PrepProfile(
  id: 'opponent-1',
  kind: PrepKind.opponent,
  name: 'Hikaru Nakamura',
  createdAtMs: 1,
  accounts: [_chesscom, _database],
);

class _Remote extends PrepWatchRemote {
  final calls = <String>[];
  bool reachable = true;

  @override
  Future<bool> watch(PrepProfile profile) async {
    calls.add('watch ${profile.id} ${profile.name}');
    return reachable;
  }

  @override
  Future<bool> unwatch(String profileId) async {
    calls.add('unwatch $profileId');
    return reachable;
  }
}

/// A container over a profiles.json holding [json], and that file.
Future<(ProviderContainer, File)> _container(
  Map<String, Object?> json,
  _Remote remote,
) async {
  final directory = Directory.systemTemp.createTempSync('prep_watch_');
  final file = File('${directory.path}/prep/profiles.json');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(jsonEncode(json));
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => directory.path,
  );
  final container = ProviderContainer(
    overrides: [prepWatchRemoteProvider.overrideWithValue(remote)],
  );
  final loaded = Completer<void>();
  final sub = container.listen(prepProfilesProvider, (_, next) {
    if (!next.isLoading && !loaded.isCompleted) loaded.complete();
  }, fireImmediately: true);
  await loaded.future;
  sub.close();
  addTearDown(() async {
    await container.read(prepProfilesProvider.notifier).debugDrainWatches();
    container.dispose();
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    directory.deleteSync(recursive: true);
  });
  return (container, file);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the server watches online accounts over the clocks they download', () {
    expect(prepWatchAccounts(_profile), [
      {
        'source': 'chesscom',
        'username': 'Hikaru',
        'time_controls': ['blitz', 'rapid'],
      },
    ]);
    // A fixed end date gets no new games.
    final ended = _profile.copyWith(
      accounts: [
        _chesscom.copyWith(
          preferences: PrepDownloadPreferences(
            range: PrepDateRange.custom,
            toDate: DateTime.utc(2025),
          ),
        ),
      ],
    );
    expect(prepCanWatch(ended), isFalse);
    expect(
      prepCanWatch(
        const PrepProfile(
          id: 'mine',
          kind: PrepKind.mine,
          name: 'Me',
          createdAtMs: 1,
          accounts: [_lichess],
        ),
      ),
      isFalse,
    );
    expect(prepWatchSignature(_profile), isNull);
    expect(prepWatchSignature(_profile.copyWith(watching: true)), isNotNull);
  });

  test('a star survives a save', () {
    final saved = PrepProfile.fromJson(
      jsonDecode(jsonEncode(_profile.copyWith(watching: true).toJson())),
    );
    expect(saved?.watching, isTrue);
    expect(_profile.toJson().containsKey('watching'), isFalse);
  });

  test(
    'starring, renaming and losing the online source reach the server',
    () async {
      final remote = _Remote();
      final (container, _) = await _container({
        'profiles': [_profile.toJson()],
      }, remote);
      final profiles = container.read(prepProfilesProvider.notifier);

      profiles.setWatching(_profile.id, true);
      await profiles.debugDrainWatches();
      expect(remote.calls, ['watch opponent-1 Hikaru Nakamura']);

      // Nothing the server holds changed: no write.
      profiles.edit(
        _profile.id,
        (p) => p.replaceAccount(_chesscom.copyWith(gameCount: 40)),
      );
      await profiles.debugDrainWatches();
      expect(remote.calls, hasLength(1));

      profiles.edit(_profile.id, (p) => p.copyWith(name: 'Hikaru'));
      await profiles.debugDrainWatches();
      expect(remote.calls.last, 'watch opponent-1 Hikaru');

      profiles.edit(_profile.id, (p) => p.copyWith(accounts: [_database]));
      await profiles.debugDrainWatches();
      expect(remote.calls.last, 'unwatch opponent-1');

      profiles.edit(_profile.id, (p) => p.copyWith(accounts: [_lichess]));
      await profiles.debugDrainWatches();
      expect(remote.calls.last, 'watch opponent-1 Hikaru');
    },
  );

  test('an unstar the server missed is kept and retried at launch', () async {
    final remote = _Remote()..reachable = false;
    final (container, file) = await _container({
      'profiles': [_profile.copyWith(watching: true).toJson()],
    }, remote);
    final profiles = container.read(prepProfilesProvider.notifier);
    await profiles.debugDrainWatches();
    // Launch writes every star again, which also carries today's offset.
    expect(remote.calls, ['watch opponent-1 Hikaru Nakamura']);

    profiles.setWatching(_profile.id, false);
    await profiles.debugDrainWatches();
    expect(remote.calls.last, 'unwatch opponent-1');
    final saved = jsonDecode(file.readAsStringSync()) as Map;
    expect(saved['unwatch'], ['opponent-1']);

    // The next launch, now online.
    final next = _Remote();
    final (relaunched, again) = await _container(
      saved.cast<String, Object?>(),
      next,
    );
    await relaunched.read(prepProfilesProvider.notifier).debugDrainWatches();
    expect(next.calls, ['unwatch opponent-1']);
    expect((jsonDecode(again.readAsStringSync()) as Map)['unwatch'], isNull);
  });

  test('a push for a profile this device does not star unstars it', () async {
    final remote = _Remote();
    final (container, _) = await _container({
      'profiles': [_profile.toJson()],
    }, remote);
    final profiles = container.read(prepProfilesProvider.notifier);
    profiles.settleWatch('gone-from-this-device');
    profiles.settleWatch(_profile.id);
    await profiles.debugDrainWatches();
    expect(remote.calls, [
      'unwatch gone-from-this-device',
      'unwatch opponent-1',
    ]);
  });
}
