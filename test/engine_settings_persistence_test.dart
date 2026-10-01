import 'dart:async';
import 'dart:convert';

import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/engine_settings/engine_settings_store.dart';
import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _MemoryCache implements EngineSettingsCache {
  final records = <String, String>{};
  bool failWrites = false;
  Completer<void>? writeGate;

  @override
  Future<String?> read(String key) async => records[key];

  @override
  Future<void> write(String key, String value) async {
    await writeGate?.future;
    if (failWrites) throw StateError('fake disk failure');
    records[key] = value;
  }

  @override
  Future<void> remove(String key) async => records.remove(key);
}

class _Backend implements EngineSettingsBackend {
  final rows = <String, EngineSettingsRemote>{};
  final writes = <({String userId, Map<String, dynamic> fields})>[];
  bool offline = false;
  bool failSaves = false;
  final forcedFields = <String, dynamic>{};
  Completer<void>? fetchGate;
  Completer<void>? saveGate;
  final saveStarted = Completer<void>();
  int activeSaves = 0;
  int maxActiveSaves = 0;
  int fetches = 0;

  @override
  Future<EngineSettingsRemote?> fetch(String userId) async {
    fetches++;
    // Capture before the gate to simulate a genuinely stale in-flight read.
    final row = rows[userId];
    await fetchGate?.future;
    if (offline) throw StateError('fake offline');
    return row;
  }

  @override
  Future<EngineSettingsRemote> save(
    String userId,
    Map<String, dynamic> fields,
    DateTime updatedAt,
  ) async {
    activeSaves++;
    if (activeSaves > maxActiveSaves) maxActiveSaves = activeSaves;
    writes.add((userId: userId, fields: {...fields}));
    if (!saveStarted.isCompleted) saveStarted.complete();
    try {
      await saveGate?.future;
      if (offline || failSaves) throw StateError('fake save failure');
      final saved = EngineSettingsRemote({
        ...engineSettingsDefaults,
        ...?rows[userId]?.fields,
        ...fields,
        ...forcedFields,
      }, updatedAt: updatedAt);
      rows[userId] = saved;
      return saved;
    } finally {
      activeSaves--;
    }
  }
}

EngineSettingsStore _store(
  _MemoryCache cache,
  _Backend backend, {
  String? userId = 'account-a',
  String environment = 'test:project',
  bool legacy = false,
}) => EngineSettingsStore(
  scope: (environment: environment, userId: userId),
  cache: cache,
  backend: backend,
  importLegacySurfaces: legacy,
);

Map<String, dynamic> _record(_MemoryCache cache, EngineSettingsStore store) =>
    jsonDecode(cache.records[store.cacheKey]!) as Map<String, dynamic>;

final _account = StateProvider<String?>((ref) => null);
final _environment = StateProvider<String>((ref) => 'test:project');

ProviderContainer _container(_MemoryCache cache, _Backend backend) {
  final container = ProviderContainer(
    overrides: [
      engineSettingsCacheProvider.overrideWithValue(cache),
      engineSettingsBackendProvider.overrideWithValue(backend),
      engineSettingsAccountProvider.overrideWith((ref) => ref.watch(_account)),
      engineSettingsEnvironmentProvider.overrideWith(
        (ref) => ref.watch(_environment),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

EngineSettings _settings(ProviderContainer container) =>
    container.read(engineSettingsProviderNew).requireValue;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('durable scoped engine store', () {
    late _MemoryCache cache;
    late _Backend backend;
    setUp(() {
      cache = _MemoryCache();
      backend = _Backend();
    });

    test('20s survives a guest cold restart without auth or network', () async {
      final first = _store(cache, backend, userId: null);
      await first.change({'searchTimeIndex': 2, 'principalVariationIndex': 1});
      await first.sync();
      final restart = _store(cache, backend, userId: null);
      expect((await restart.loadLocal())['searchTimeIndex'], 2);
      expect(restart.values['principalVariationIndex'], 1);
      expect(backend.fetches, 0);
      expect(backend.writes, isEmpty);
    });

    test(
      'offline authenticated restart preserves snapshot and outbox',
      () async {
        backend.offline = true;
        final first = _store(cache, backend);
        await first.change({'searchTimeIndex': 2});
        await first.sync();
        final restart = _store(cache, backend);
        expect((await restart.loadLocal())['searchTimeIndex'], 2);
        await restart.sync();
        expect(restart.values['searchTimeIndex'], 2);
        expect(_record(cache, restart)['pending'], contains('searchTimeIndex'));
      },
    );

    test(
      'failed save plus stale cloud cannot erase 20s after restart',
      () async {
        backend.rows['account-a'] = EngineSettingsRemote({
          'searchTimeIndex': 0,
          'principalVariationIndex': 0,
        }, updatedAt: DateTime.utc(2026));
        backend.failSaves = true;
        final first = _store(cache, backend);
        await first.change({'searchTimeIndex': 2});
        await first.sync();
        final restart = _store(cache, backend);
        await restart.loadLocal();
        await restart.sync();
        expect(restart.values['searchTimeIndex'], 2);
        expect(restart.values['principalVariationIndex'], 0);
        expect(_record(cache, restart)['pending'], contains('searchTimeIndex'));
        backend.failSaves = false;
        await restart.sync();
        expect(backend.rows['account-a']!.fields['searchTimeIndex'], 2);
        expect(_record(cache, restart)['pending'], isEmpty);
      },
    );

    test(
      'ack clears outbox, newer remote changes then win across restart',
      () async {
        final first = _store(cache, backend);
        await first.change({'searchTimeIndex': 2});
        await first.sync();
        final savedVersion = backend.rows['account-a']!.updatedAt!;
        backend.rows['account-a'] = EngineSettingsRemote({
          'searchTimeIndex': 3,
          'maxArrowsOnBoard': 4,
        }, updatedAt: savedVersion.add(const Duration(seconds: 1)));
        final restart = _store(cache, backend);
        await restart.loadLocal();
        await restart.sync();
        expect(restart.values['searchTimeIndex'], 3);
        expect(restart.values['maxArrowsOnBoard'], 4);
        expect(backend.writes, hasLength(1));
      },
    );

    test(
      'older confirmed cloud snapshot is ignored, not permanently local',
      () async {
        final store = _store(cache, backend);
        await store.change({'searchTimeIndex': 2});
        await store.sync();
        final version = backend.rows['account-a']!.updatedAt!;
        backend.rows['account-a'] = EngineSettingsRemote({
          'searchTimeIndex': 0,
        }, updatedAt: version.subtract(const Duration(seconds: 1)));
        final restart = _store(cache, backend);
        await restart.loadLocal();
        await restart.sync();
        expect(restart.values['searchTimeIndex'], 2);
        backend.rows['account-a'] = EngineSettingsRemote({
          'searchTimeIndex': 4,
        }, updatedAt: version.add(const Duration(seconds: 1)));
        await restart.sync();
        expect(restart.values['searchTimeIndex'], 4);
      },
    );

    test(
      'delayed acknowledgement does not clear newer same-field revision',
      () async {
        final store = _store(cache, backend);
        await store.change({'searchTimeIndex': 1});
        backend.saveGate = Completer<void>();
        final firstSync = store.sync();
        await backend.saveStarted.future;
        // Local persistence completes while the first network write is stalled.
        await store.change({'searchTimeIndex': 2, 'showEngineAnalysis': false});
        final queuedSync = store.sync();
        expect(_record(cache, store)['values']['searchTimeIndex'], 2);
        backend.saveGate!.complete();
        await firstSync;
        await queuedSync;
        expect(store.values['searchTimeIndex'], 2);
        expect(backend.rows['account-a']!.fields['searchTimeIndex'], 2);
        expect(backend.maxActiveSaves, 1);
        expect(backend.writes, hasLength(2));
        expect(_record(cache, store)['pending'], isEmpty);
      },
    );

    test(
      'ABA selections retain the newest revision until acknowledged',
      () async {
        final store = _store(cache, backend);
        await store.change({'searchTimeIndex': 2});
        backend.saveGate = Completer<void>();
        final syncing = store.sync();
        await backend.saveStarted.future;
        await store.change({'searchTimeIndex': 3});
        await store.change({'searchTimeIndex': 2});
        backend.saveGate!.complete();
        await syncing;
        expect(_record(cache, store)['pending'], contains('searchTimeIndex'));
        await store.sync();
        expect(_record(cache, store)['pending'], isEmpty);
      },
    );

    test('mutation during stale fetch overlays only pending fields', () async {
      backend.rows['account-a'] = EngineSettingsRemote({
        'searchTimeIndex': 0,
        'showDepthOverlay': false,
      }, updatedAt: DateTime.utc(2026));
      backend.fetchGate = Completer<void>();
      final store = _store(cache, backend);
      await store.loadLocal();
      final syncing = store.sync();
      await Future<void>.delayed(Duration.zero);
      await store.change({'searchTimeIndex': 2});
      backend.fetchGate!.complete();
      await syncing;
      expect(store.values['searchTimeIndex'], 2);
      expect(store.values['showDepthOverlay'], false);
      expect(backend.writes.single.fields, {'searchTimeIndex': 2});
    });

    test(
      'surface flags persist locally and never enter cloud patches',
      () async {
        final store = _store(cache, backend);
        await store.change({
          'showEngineGaugeOnBoard': false,
          'showEngineGaugeInGrid': false,
        });
        await store.sync();
        expect(backend.writes, isEmpty);
        await store.change({'searchTimeIndex': 2});
        await store.sync();
        expect(backend.writes.single.fields, {'searchTimeIndex': 2});
        final restart = _store(cache, backend);
        await restart.loadLocal();
        await restart.sync();
        expect(restart.values['showEngineGaugeOnBoard'], false);
        expect(restart.values['showEngineGaugeInGrid'], false);
      },
    );

    test(
      'partial saves preserve unrelated fresh cross-device fields',
      () async {
        backend.rows['account-a'] = EngineSettingsRemote({
          'searchTimeIndex': 0,
          'principalVariationIndex': 0,
          'showPvArrows': false,
          'engineLinesView': 0,
        }, updatedAt: DateTime.utc(2026));
        final store = _store(cache, backend);
        await store.change({'searchTimeIndex': 2});
        await store.sync();
        expect(backend.writes.single.fields, {'searchTimeIndex': 2});
        expect(backend.rows['account-a']!.fields['principalVariationIndex'], 0);
        expect(store.values['showPvArrows'], false);
        expect(store.values['engineLinesView'], 0);
      },
    );

    test(
      'rapid local commits are ordered even when SQLite is delayed',
      () async {
        cache.writeGate = Completer<void>();
        final store = _store(cache, backend);
        final one = store.change({'searchTimeIndex': 1});
        final two = store.change({'searchTimeIndex': 2});
        final pv = store.change({'principalVariationIndex': 0});
        cache.writeGate!.complete();
        await Future.wait([one, two, pv]);
        final restart = _store(cache, backend);
        await restart.loadLocal();
        expect(restart.values['searchTimeIndex'], 2);
        expect(restart.values['principalVariationIndex'], 0);
      },
    );

    test(
      'account, guest and environment snapshots/outboxes are isolated',
      () async {
        final a = _store(cache, backend);
        await a.change({'searchTimeIndex': 2});
        for (final isolated in [
          _store(cache, backend, userId: 'account-b'),
          _store(cache, backend, userId: null),
          _store(cache, backend, environment: 'production:other-project'),
        ]) {
          expect((await isolated.loadLocal())['searchTimeIndex'], 0);
          expect(isolated.cacheKey, isNot(a.cacheKey));
        }
        expect(
          (await _store(cache, backend).loadLocal())['searchTimeIndex'],
          2,
        );
      },
    );

    test(
      'unowned legacy synced fields are quarantined; surface flags survive',
      () async {
        cache.records[EngineSettingsStore.legacyKey] = jsonEncode({
          'searchTimeIndex': 2,
          'showPvArrows': false,
          'showEngineGaugeOnBoard': false,
        });
        final store = _store(cache, backend, legacy: true);
        final restored = await store.loadLocal();
        expect(restored['searchTimeIndex'], 0);
        expect(restored['showPvArrows'], true);
        expect(restored['showEngineGaugeOnBoard'], false);
        await store.sync();
        expect(backend.writes, isEmpty);
        expect(cache.records, contains(EngineSettingsStore.legacyKey));
      },
    );

    test(
      'partial owned snapshot retains 20s despite missing newer fields',
      () async {
        final store = _store(cache, backend);
        cache.records[store.cacheKey] = jsonEncode({
          'schema': 2,
          'values': {'searchTimeIndex': 2, 'showPvArrows': 'bad'},
          'pending': {'searchTimeIndex': 7, 'unknown': 9, 'showPvArrows': 8},
          'revision': 'bad',
          'remoteVersion': 'bad',
        });
        expect((await store.loadLocal())['searchTimeIndex'], 2);
        expect(store.values['showPvArrows'], true);
        await store.sync();
        expect(backend.writes.single.fields, {'searchTimeIndex': 2});
      },
    );

    test('malformed JSON/non-map/index fields safely fall back', () async {
      for (final raw in [
        '{bad',
        '[]',
        'null',
        jsonEncode({
          'schema': 2,
          'values': {'searchTimeIndex': 99, 'engineLinesView': '1'},
          'pending': [],
        }),
      ]) {
        final store = _store(cache, backend);
        cache.records[store.cacheKey] = raw;
        expect((await store.loadLocal())['searchTimeIndex'], 0);
        expect(store.values['engineLinesView'], 1);
      }
    });

    test(
      'failed local commit is not acknowledged or sent; lane recovers',
      () async {
        final store = _store(cache, backend);
        cache.failWrites = true;
        await expectLater(
          store.change({'searchTimeIndex': 2}),
          throwsStateError,
        );
        expect(store.values['searchTimeIndex'], 0);
        expect(backend.writes, isEmpty);
        cache.failWrites = false;
        await store.change({'searchTimeIndex': 2});
        await store.sync();
        expect(backend.rows['account-a']!.fields['searchTimeIndex'], 2);
      },
    );

    test('missing cloud row creates only explicitly changed fields', () async {
      final store = _store(cache, backend);
      await store.loadLocal();
      await store.sync();
      expect(backend.writes, isEmpty);
      await store.change({'searchTimeIndex': 2});
      await store.sync();
      expect(backend.writes.single.fields, {'searchTimeIndex': 2});
    });
  });

  test(
    '2xx server coercion retains pending time across restart and retries',
    () async {
      final cache = _MemoryCache();
      final backend = _Backend()..forcedFields['searchTimeIndex'] = 0;
      final store = _store(cache, backend);
      await store.change({'searchTimeIndex': 2, 'showEngineAnalysis': false});
      await store.sync();
      expect(store.values['searchTimeIndex'], 2);
      expect(backend.rows['account-a']!.fields['searchTimeIndex'], 0);
      expect(_record(cache, store)['pending'].keys, ['searchTimeIndex']);
      final restart = _store(cache, backend);
      await restart.loadLocal();
      await restart.sync();
      expect(restart.values['searchTimeIndex'], 2);
      expect(restart.values['showEngineAnalysis'], false);
      backend.forcedFields.clear();
      await restart.sync();
      expect(backend.rows['account-a']!.fields['searchTimeIndex'], 2);
      expect(_record(cache, restart)['pending'], isEmpty);
    },
  );

  test('clear cannot be undone by an old in-flight acknowledgement', () async {
    final cache = _MemoryCache();
    final backend = _Backend()..saveGate = Completer<void>();
    final store = _store(cache, backend);
    await store.change({'searchTimeIndex': 2});
    final syncing = store.sync();
    await backend.saveStarted.future;
    await store.clear();
    await store.change({'searchTimeIndex': 3});
    backend.saveGate!.complete();
    await syncing;
    expect(store.values['searchTimeIndex'], 3);
    expect(_record(cache, store)['pending'], contains('searchTimeIndex'));
    await store.sync();
    expect(backend.rows['account-a']!.fields['searchTimeIndex'], 3);
  });

  group('real engine settings provider with fake persistence/backend', () {
    test(
      'successful sync allows newer remote time; surfaces stay local',
      () async {
        final cache = _MemoryCache();
        final backend = _Backend();
        final container = _container(cache, backend);
        container.read(_account.notifier).state = 'account-a';
        await container.read(engineSettingsProviderNew.future);
        final notifier = container.read(engineSettingsProviderNew.notifier);
        await notifier.setSearchTimeIndex(2);
        await notifier.toggleEngineGaugeOnBoard(false);
        await notifier.refresh();
        final version = backend.rows['account-a']!.updatedAt!;
        backend.rows['account-a'] = EngineSettingsRemote({
          'searchTimeIndex': 3,
          'showEngineGaugeOnBoard': true,
        }, updatedAt: version.add(const Duration(seconds: 1)));
        await notifier.syncFromSupabase();
        expect(_settings(container).baseSearchTimeSeconds(), 30);
        expect(_settings(container).showEngineGaugeOnBoard, false);
      },
    );

    test(
      'late save cannot publish A settings into B or serialize B behind A',
      () async {
        final cache = _MemoryCache();
        final backend = _Backend()..saveGate = Completer<void>();
        final container = _container(cache, backend);
        container.read(_account.notifier).state = 'account-a';
        await container.read(engineSettingsProviderNew.future);
        await container
            .read(engineSettingsProviderNew.notifier)
            .setSearchTimeIndex(2);
        await backend.saveStarted.future;
        container.read(_account.notifier).state = 'account-b';
        await container.read(engineSettingsProviderNew.future);
        final b = container.read(engineSettingsProviderNew.notifier);
        expect(_settings(container).searchTimeIndex, 0);
        await b.setSearchTimeIndex(3);
        backend.saveGate!.complete();
        await b.refresh();
        expect(_settings(container).searchTimeIndex, 3);
        expect(backend.rows['account-a']!.fields['searchTimeIndex'], 2);
        expect(backend.rows['account-b']!.fields['searchTimeIndex'], 3);
      },
    );

    test(
      'disposed notifier finishes disk write without using disposed Ref',
      () async {
        final cache = _MemoryCache()..writeGate = Completer<void>();
        final backend = _Backend();
        final container = ProviderContainer(
          overrides: [
            engineSettingsCacheProvider.overrideWithValue(cache),
            engineSettingsBackendProvider.overrideWithValue(backend),
            engineSettingsAccountProvider.overrideWithValue(null),
            engineSettingsEnvironmentProvider.overrideWithValue('test:project'),
          ],
        );
        await container.read(engineSettingsProviderNew.future);
        final changing = container
            .read(engineSettingsProviderNew.notifier)
            .setSearchTimeIndex(2);
        container.dispose();
        cache.writeGate!.complete();
        await changing;
        expect(
          (await _store(
            cache,
            backend,
            userId: null,
          ).loadLocal())['searchTimeIndex'],
          2,
        );
      },
    );
    test(
      '20s cold restart restores duration and other guest settings',
      () async {
        final cache = _MemoryCache();
        final backend = _Backend();
        final first = _container(cache, backend);
        await first.read(engineSettingsProviderNew.future);
        final notifier = first.read(engineSettingsProviderNew.notifier);
        await notifier.setSearchTimeIndex(2);
        await notifier.setPrincipalVariationIndex(1);
        await notifier.toggleEngineGaugeInGrid(false);
        final restart = _container(cache, backend);
        final restored = await restart.read(engineSettingsProviderNew.future);
        expect(restored.baseSearchTimeSeconds(), 20);
        expect(
          restored.resolveBoardSearchProfile().searchDuration,
          const Duration(seconds: 20),
        );
        expect(restored.principalVariationIndex, 1);
        expect(restored.showEngineGaugeInGrid, false);
        expect(backend.writes, isEmpty);
      },
    );

    test(
      'engine off/on and rapid mutations cannot reload stale cloud time',
      () async {
        final cache = _MemoryCache();
        final backend = _Backend()..failSaves = true;
        backend.rows['anonymous-a'] = EngineSettingsRemote({
          'searchTimeIndex': 0,
        }, updatedAt: DateTime.utc(2026));
        final container = _container(cache, backend);
        container.read(_account.notifier).state = 'anonymous-a';
        await container.read(engineSettingsProviderNew.future);
        final notifier = container.read(engineSettingsProviderNew.notifier);
        await notifier.refresh();
        await Future.wait([
          notifier.setSearchTimeIndex(2),
          notifier.toggleEngineAnalysis(false),
          notifier.setPrincipalVariationIndex(0),
        ]);
        await notifier.toggleEngineAnalysis(true);
        await notifier.refresh();
        expect(_settings(container).baseSearchTimeSeconds(), 20);
        expect(_settings(container).principalVariationIndex, 0);
        expect(_settings(container).showEngineAnalysis, true);
        // Do not bypass the intentional debug Stockfish kill switch.
        expect(kEnableStockfishInDebug, false);
        backend.failSaves = false;
        await notifier.refresh();
        expect(backend.rows['anonymous-a']!.fields['searchTimeIndex'], 2);
      },
    );

    test(
      'delayed fetch does not block local startup or overwrite mutation',
      () async {
        final cache = _MemoryCache();
        final backend = _Backend()..fetchGate = Completer<void>();
        backend.rows['account-a'] = EngineSettingsRemote({
          'searchTimeIndex': 0,
        }, updatedAt: DateTime.utc(2026));
        final container = _container(cache, backend);
        container.read(_account.notifier).state = 'account-a';
        await container.read(engineSettingsProviderNew.future);
        final notifier = container.read(engineSettingsProviderNew.notifier);
        await notifier.setSearchTimeIndex(2);
        expect(_settings(container).searchTimeIndex, 2);
        backend.fetchGate!.complete();
        await notifier.refresh();
        expect(_settings(container).searchTimeIndex, 2);
      },
    );

    test(
      'auth restoration/switch and flavor rebuild never leak snapshots',
      () async {
        final cache = _MemoryCache();
        final backend = _Backend()..offline = true;
        final container = _container(cache, backend);
        await container.read(engineSettingsProviderNew.future);
        await container
            .read(engineSettingsProviderNew.notifier)
            .setSearchTimeIndex(2);
        container.read(_account.notifier).state = 'account-a';
        await container.read(engineSettingsProviderNew.future);
        expect(_settings(container).searchTimeIndex, 0);
        await container
            .read(engineSettingsProviderNew.notifier)
            .setSearchTimeIndex(3);
        container.read(_account.notifier).state = 'account-b';
        await container.read(engineSettingsProviderNew.future);
        expect(_settings(container).searchTimeIndex, 0);
        container.read(_account.notifier).state = 'account-a';
        await container.read(engineSettingsProviderNew.future);
        expect(_settings(container).searchTimeIndex, 3);
        container.read(_environment.notifier).state =
            'production:other-project';
        await container.read(engineSettingsProviderNew.future);
        expect(_settings(container).searchTimeIndex, 0);
        container.read(_account.notifier).state = null;
        container.read(_environment.notifier).state = 'test:project';
        await container.read(engineSettingsProviderNew.future);
        expect(_settings(container).searchTimeIndex, 2);
      },
    );

    test('disposed provider ignores late sync publication', () async {
      final cache = _MemoryCache();
      final backend = _Backend()..fetchGate = Completer<void>();
      final container = ProviderContainer(
        overrides: [
          engineSettingsCacheProvider.overrideWithValue(cache),
          engineSettingsBackendProvider.overrideWithValue(backend),
          engineSettingsAccountProvider.overrideWithValue('account-a'),
          engineSettingsEnvironmentProvider.overrideWithValue('test:project'),
        ],
      );
      await container.read(engineSettingsProviderNew.future);
      final refresh = container
          .read(engineSettingsProviderNew.notifier)
          .refresh();
      container.dispose();
      backend.fetchGate!.complete();
      await refresh;
    });
  });
}
