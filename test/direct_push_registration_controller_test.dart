// Test-only in-memory implementation of the installed preferences backend.
// ignore_for_file: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'dart:async';
import 'dart:convert';

import 'package:chessever2/services/direct_push_registration_controller.dart';
import 'package:chessever2/services/favorite_player_news_preference_store.dart';
import 'package:chessever2/services/favorite_player_news_token_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const installation = '00000000-0000-4000-8000-000000000001';
const proof = 'synthetic-installation-proof-not-a-real-secret';

class Fixture {
  DirectPushSession? session = const DirectPushSession(
    'user-a',
    'synthetic-user-a',
  );
  final FavoritePlayerNewsPreferenceStore store;
  final requests = <http.Request>[];
  bool ready = true;
  Future<Map<String, dynamic>?> Function()? registrationReader;
  String? serverOwner;
  bool serverNews = false;
  bool serverOptedIn = true;
  bool registrationOptedIn = true;
  String registrationToken = 'synthetic-fcm-token-long-enough';
  String? serverToken;
  int serverRevision = 0;
  int active = 0;
  int peak = 0;
  Future<http.Response?> Function(http.Request, Map<String, dynamic>)?
  intercept;
  late DirectPushRegistrationController controller;

  Map<String, dynamic> ack(
    Map<String, dynamic> body, {
    bool detached = false,
  }) => {
    'id': installation,
    'registrationRevision': body['registrationRevision'],
    'favoritePlayerNews': body['favoritePlayerNews'] ?? false,
    'detached': detached,
    'newsProtocol': 1,
    'newsDrainPending': false,
  };
  http.Response response(Map<String, dynamic> body, {bool detached = false}) =>
      http.Response(jsonEncode(ack(body, detached: detached)), 200);

  Fixture({int maxAttempts = 5, FavoritePlayerNewsPreferenceStore? store})
    : store = store ?? FavoritePlayerNewsPreferenceStore() {
    controller = create(maxAttempts: maxAttempts);
  }

  DirectPushRegistrationController create({
    int maxAttempts = 5,
  }) => DirectPushRegistrationController(
    store: store,
    transport: DirectPushDeviceTransport(
      baseUri: Uri.parse('https://local-fixture.invalid'),
      client: MockClient((request) async {
        requests.add(request);
        active++;
        if (active > peak) peak = active;
        try {
          final body = Map<String, dynamic>.from(
            jsonDecode(request.body) as Map,
          );
          expect(body['installationId'], installation);
          expect(body['installationSecret'], proof);
          expect(body['registrationRevision'], isA<int>());
          expect(
            (await store.load()).revision,
            body['registrationRevision'],
            reason: 'The durable revision must exist BEFORE transport starts',
          );
          expect(
            body['registrationRevision'] as int,
            greaterThan(serverRevision),
          );
          final intercepted = await intercept?.call(request, body);
          if (intercepted != null) return intercepted;
          final path = request.url.path;
          if (path == '/v1/devices/logout') {
            expect(request.headers.containsKey('authorization'), false);
            expect(body.keys.toSet(), {
              'installationId',
              'installationSecret',
              'registrationRevision',
            });
            serverOwner = null;
            serverNews = false;
            serverRevision = body['registrationRevision'] as int;
            return response(body, detached: true);
          }
          final user =
              request.headers['authorization'] == 'Bearer synthetic-user-a'
              ? 'user-a'
              : 'user-b';
          expect(
            request.headers['authorization'],
            startsWith('Bearer synthetic-user-'),
          );
          expect(body['favoritePlayerNews'], isA<bool>());
          if (path == '/v1/devices/preferences') {
            expect(body.keys.toSet(), {
              'installationId',
              'installationSecret',
              'registrationRevision',
              'favoritePlayerNews',
            });
            if (serverOwner != user) return http.Response('{}', 403);
          } else {
            expect(path, '/v1/devices');
            expect(body['oneSignalSubscriptionId'], 'synthetic-subscription');
            expect(body['token'], startsWith('synthetic-fcm-token-'));
            serverToken = body['token'] as String;
            serverOptedIn = body['optedIn'] as bool;
            serverOwner = user;
          }
          serverRevision = body['registrationRevision'] as int;
          serverNews = body['favoritePlayerNews'] as bool;
          return response(body);
        } finally {
          active--;
        }
      }),
    ),
    readSession: () => session,
    readProof: () async => {
      'installationId': installation,
      'installationSecret': proof,
    },
    readRegistration: () async {
      if (registrationReader != null) return registrationReader!();
      return !ready
          ? null
          : {
              'token': registrationToken,
              'oneSignalSubscriptionId': 'synthetic-subscription',
              'platform': 'ios',
              'optedIn': registrationOptedIn,
              'appVersion': '0.0.0+0',
              'language': 'en',
              'timezone': 'UTC',
            };
    },
    maxAttempts: maxAttempts,
    retryDelay: const Duration(milliseconds: 10),
    readinessTimeout: const Duration(milliseconds: 20),
  );

  Future<void> registered() async {
    await controller.sync(register: true);
    expect(controller.status.value.confirmed, true);
    expect(serverOwner, 'user-a');
    expect(serverNews, true);
  }
}

Future<void> _waitFor(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!predicate() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(
    predicate(),
    true,
    reason: 'Bounded real controller timer did not finish',
  );
}

class RejectRevisionStore extends FavoritePlayerNewsPreferenceStore {
  @override
  Future<FavoritePlayerNewsRegistrationState> update(
    void Function(FavoritePlayerNewsRegistrationState) change,
  ) => super.update((state) {
    final revision = state.revision;
    change(state);
    if (state.revision != revision) {
      throw StateError('Synthetic storage failure');
    }
  });
}

class RecoverableStore extends FavoritePlayerNewsPreferenceStore {
  bool reject = false;
  @override
  Future<FavoritePlayerNewsRegistrationState> update(
    void Function(FavoritePlayerNewsRegistrationState) change,
  ) => super.update((state) {
    if (reject) throw StateError('Synthetic transient storage failure');
    change(state);
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test(
    'first registration always carries desired default and monotonic revision',
    () async {
      final f = Fixture();
      addTearDown(f.controller.dispose);
      await f.registered();
      expect(f.requests.map((r) => r.url.path), [
        '/v1/devices/preferences',
        '/v1/devices',
      ]);
      expect(f.serverRevision, 2);
      expect((await f.store.load()).ackRevision, 2);
      expect(f.serverOptedIn, true);
      expect(f.peak, 1);
    },
  );

  test(
    'opt-out acknowledges without OneSignal, APNs or FCM readiness and preserves game/event transport',
    () async {
      final f = Fixture();
      addTearDown(f.controller.dispose);
      await f.registered();
      f.requests.clear();
      f.ready = false;
      await f.store.write(false);
      await f.controller.preferenceChanged();
      expect(f.requests.map((r) => r.url.path), ['/v1/devices/preferences']);
      expect(f.serverNews, false);
      expect(f.serverOptedIn, true);
      expect(f.controller.status.value.confirmed, true);
      expect(f.controller.status.value.enabled, false);
      final persisted = await f.store.load();
      expect(persisted.ackOwner, 'user-a');
      expect(persisted.ackChoice, persisted.choice);
    },
  );

  test(
    'actual controller exhausts transport retries, persists desired pending and recovers on resume',
    () async {
      final f = Fixture(maxAttempts: 3);
      addTearDown(() => f.controller.dispose());
      await f.registered();
      f.requests.clear();
      f.intercept = (_, __) async => http.Response('{}', 503);
      await f.store.write(false);
      await expectLater(f.controller.preferenceChanged(), throwsStateError);
      expect(f.controller.status.value.confirmed, false);
      await _waitFor(() => f.controller.failedAttempts == 3);
      expect(f.controller.failedAttempts, 3);
      expect(f.requests, hasLength(3));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(f.requests, hasLength(3));
      expect(f.serverNews, true); // Local off is not a remote success claim.
      final pending = await f.store.load();
      expect(pending.enabled, false);
      expect(pending.ackChoice, isNull);
      final beforeRevision = pending.revision;
      f.controller.dispose();
      f.controller = f.create();
      f.ready = false;
      await f.controller.initialize();
      expect(f.controller.status.value.enabled, false);
      expect(f.controller.status.value.confirmed, false);
      f.intercept = null;
      await f.controller.sync(register: true, resetRetries: true);
      expect(f.controller.status.value.confirmed, true);
      expect(f.serverNews, false);
      expect((await f.store.load()).revision, greaterThan(beforeRevision));
    },
  );

  test(
    'readiness retries stop bounded, then readiness event registers without changing desired value',
    () async {
      final f = Fixture(maxAttempts: 3);
      addTearDown(f.controller.dispose);
      f.ready = false;
      await f.controller.sync(register: true);
      await _waitFor(() => f.controller.failedAttempts == 3);
      expect(f.controller.failedAttempts, 3);
      expect(
        f.requests.every((r) => r.url.path.endsWith('/preferences')),
        true,
      );
      expect(f.controller.status.value.confirmed, false);
      f.ready = true;
      await f.controller.sync(register: true, resetRetries: true);
      expect(f.controller.status.value.confirmed, true);
      expect(f.serverNews, true);
    },
  );

  test(
    'persistent confirmed signature restores only for the same authenticated owner',
    () async {
      final f = Fixture();
      await f.registered();
      f.controller.dispose();
      f.controller = f.create();
      addTearDown(() => f.controller.dispose());
      await f.controller.initialize();
      expect(f.controller.status.value.confirmed, true);
      f.session = const DirectPushSession('user-b', 'synthetic-user-b');
      f.intercept = (_, __) async => http.Response('{}', 503);
      await f.controller.sync(register: true, resetRetries: true);
      expect(f.controller.status.value.confirmed, false);
      expect((await f.store.load()).detachPending, true);
      expect((await f.store.load()).ackOwner, isNull);
      expect(f.serverOwner, 'user-a');
    },
  );

  test(
    'failed detach persists across restart and expired auth; no new registration can bypass it',
    () async {
      final f = Fixture();
      await f.registered();
      f.requests.clear();
      f.session = null; // Revoked/expired session, no usable JWT remains.
      f.intercept = (_, __) async => http.Response('{}', 503);
      await f.controller.sync(register: true, resetRetries: true);
      expect((await f.store.load()).detachPending, true);
      expect(f.requests.map((r) => r.url.path), ['/v1/devices/logout']);
      f.controller.dispose();
      f.controller = f.create();
      addTearDown(() => f.controller.dispose());
      f.session = const DirectPushSession('user-b', 'synthetic-user-b');
      await f.controller.sync(register: true, resetRetries: true);
      expect(f.requests.every((r) => r.url.path.endsWith('/logout')), true);
      expect((await f.store.load()).detachPending, true);
      f.intercept = null;
      await f.controller.sync(register: true, resetRetries: true);
      expect(f.requests.skip(2).map((r) => r.url.path), [
        '/v1/devices/logout',
        '/v1/devices/preferences',
        '/v1/devices',
      ]);
      expect(f.serverOwner, 'user-b');
      expect((await f.store.load()).detachPending, false);
      expect(f.controller.status.value.confirmed, true);
      expect(f.peak, 1);
    },
  );

  test('old-server empty logout success never clears durable detach', () async {
    final f = Fixture();
    await f.registered();
    addTearDown(f.controller.dispose);
    f.session = null;
    f.intercept = (_, __) async => http.Response('{}', 200);
    await f.controller.sync(register: true, resetRetries: true);
    expect((await f.store.load()).detachPending, true);
    expect((await f.store.load()).owner, 'user-a');
    expect(f.controller.status.value.confirmed, false);
  });

  test(
    'old-server registration success does not falsely acknowledge News',
    () async {
      final f = Fixture();
      addTearDown(f.controller.dispose);
      f.intercept = (_, __) async =>
          http.Response('{"id":"$installation"}', 200);
      await f.controller.sync(register: true);
      expect(
        f.requests.last.url.path,
        '/v1/devices',
      ); // Game/event registration still attempted.
      expect(f.controller.status.value.confirmed, false);
      expect((await f.store.load()).ackRevision, isNull);
    },
  );

  test(
    'in-flight old account registration cannot acknowledge replacement or overtake durable detach',
    () async {
      final f = Fixture();
      addTearDown(f.controller.dispose);
      final entered = Completer<void>();
      final release = Completer<void>();
      var detachFails = true;
      f.intercept = (request, body) async {
        if (request.url.path == '/v1/devices' && !entered.isCompleted) {
          entered.complete();
          await release.future;
        }
        if (request.url.path.endsWith('/logout') && detachFails) {
          return http.Response('{}', 503);
        }
        return null;
      };
      final first = f.controller.sync(register: true);
      await entered.future;
      f.session = const DirectPushSession('user-b', 'synthetic-user-b');
      final second = f.controller.sync(register: true, resetRetries: true);
      await Future<void>.delayed(Duration.zero);
      release.complete();
      await Future.wait([first, second]);
      expect(f.controller.status.value.confirmed, false);
      expect((await f.store.load()).detachPending, true);
      expect(f.serverOwner, 'user-a');
      expect(
        f.requests.where(
          (r) =>
              r.url.path == '/v1/devices' &&
              r.headers['authorization'] == 'Bearer synthetic-user-b',
        ),
        isEmpty,
      );
      detachFails = false;
      await f.controller.sync(register: true, resetRetries: true);
      expect(f.serverOwner, 'user-b');
      expect(f.controller.status.value.confirmed, true);
      expect(f.peak, 1);
    },
  );

  test(
    'old preference ack cannot confirm newer persisted choice, including an ABA toggle',
    () async {
      final f = Fixture();
      addTearDown(f.controller.dispose);
      await f.registered();
      await f.store.write(false);
      final entered = Completer<void>();
      final release = Completer<void>();
      f.intercept = (request, body) async {
        if (request.url.path.endsWith('/preferences') && !entered.isCompleted) {
          entered.complete();
          await release.future;
        }
        return null;
      };
      final first = f.controller.preferenceChanged();
      final firstResult = expectLater(first, throwsStateError);
      await entered.future;
      await f.store.write(true);
      await f.store.write(false);
      release.complete();
      await firstResult;
      expect(f.controller.status.value.confirmed, false);
      expect((await f.store.load()).ackChoice, isNull);
      f.intercept = null;
      await f.controller.preferenceChanged();
      expect(f.controller.status.value.confirmed, true);
      expect(f.serverNews, false);
    },
  );

  test(
    'timezone fallback preserves payload and persists a new revision before each attempt',
    () async {
      final f = Fixture();
      addTearDown(f.controller.dispose);
      f.intercept = (request, body) async {
        if (request.url.path == '/v1/devices' && body.containsKey('timezone')) {
          return http.Response('{}', 400);
        }
        return null;
      };
      await f.registered();
      final registrations = f.requests
          .where((r) => r.url.path == '/v1/devices')
          .toList();
      expect(registrations, hasLength(2));
      final first = jsonDecode(registrations.first.body) as Map;
      final last = jsonDecode(registrations.last.body) as Map;
      expect(
        last['registrationRevision'],
        greaterThan(first['registrationRevision'] as int),
      );
      expect(last.containsKey('timezone'), false);
      expect(last['favoritePlayerNews'], true);
      expect(last['optedIn'], true);
    },
  );

  test(
    'legacy owner/detach migration remains proof-only without a session',
    () async {
      SharedPreferences.setMockInitialValues({
        'direct_push_owner': 'user-a',
        'direct_push_detach_pending': true,
        FavoritePlayerNewsPreferenceStore.key: false,
      });
      final f = Fixture();
      addTearDown(f.controller.dispose);
      f.session = null;
      await f.controller.sync();
      expect(f.requests.map((r) => r.url.path), ['/v1/devices/logout']);
      expect((await f.store.load()).detachPending, false);
      expect((await f.store.load()).enabled, false);
      expect(f.controller.status.value.confirmed, false);
    },
  );

  test(
    'rapid sign-out/sign-in to the same account still detaches before fresh registration',
    () async {
      final f = Fixture();
      addTearDown(f.controller.dispose);
      await f.registered();
      f.requests.clear();
      // Both events arrive before the SDK getter is observed again. Reading only
      // that getter would miss sign-out and incorrectly keep the old ack.
      final out = f.controller.authChanged(null);
      final back = f.controller.authChanged('user-a');
      await Future.wait([out, back]);
      expect(f.requests.first.url.path, '/v1/devices/logout');
      expect(f.serverOwner, 'user-a');
      expect(f.controller.status.value.confirmed, true);
      expect(f.peak, 1);
    },
  );

  test('explicit detach retries proof-only while JWT is absent', () async {
    final f = Fixture();
    addTearDown(f.controller.dispose);
    await f.registered();
    f.requests.clear();
    f.session = null;
    var failures = 0;
    f.intercept = (request, body) async {
      if (request.url.path.endsWith('/logout') && failures++ < 2) {
        return http.Response('{}', 503);
      }
      return null;
    };
    expect(await f.controller.detach(), false);
    expect((await f.store.load()).detachPending, true);
    await _waitFor(() => f.serverOwner == null);
    expect((await f.store.load()).detachPending, false);
    expect(f.requests.every((r) => r.url.path.endsWith('/logout')), true);
    expect(
      f.requests.every((r) => !r.headers.containsKey('authorization')),
      true,
    );
  });

  test(
    'a rejected JWT never becomes registration or an acknowledgement',
    () async {
      final f = Fixture();
      addTearDown(f.controller.dispose);
      f.intercept = (_, __) async => http.Response('{}', 401);
      await f.controller.sync(register: true);
      expect(f.requests.map((r) => r.url.path), ['/v1/devices/preferences']);
      expect(f.controller.status.value.confirmed, false);
      expect((await f.store.load()).ackRevision, isNull);
    },
  );

  for (final code in [400, 403, 404, 409, 503]) {
    test(
      'category rejection HTTP $code stays pending then retries a newer revision',
      () async {
        final f = Fixture();
        addTearDown(f.controller.dispose);
        await f.registered();
        f.requests.clear();
        await f.store.write(false);
        f.intercept = (_, __) async => http.Response('{}', code);
        await expectLater(f.controller.preferenceChanged(), throwsStateError);
        final failedRevision = (await f.store.load()).revision;
        expect(f.controller.status.value.confirmed, false);
        expect(f.serverNews, true);
        f.intercept = null;
        await f.controller.sync(resetRetries: true);
        expect((await f.store.load()).revision, greaterThan(failedRevision));
        expect(f.controller.status.value.confirmed, true);
        expect(f.serverNews, false);
      },
    );
  }

  test(
    'network exception preserves opt-out for later reconciliation',
    () async {
      final f = Fixture();
      addTearDown(f.controller.dispose);
      await f.registered();
      await f.store.write(false);
      f.intercept = (_, __) async =>
          throw http.ClientException('synthetic offline');
      await expectLater(f.controller.preferenceChanged(), throwsStateError);
      expect(await f.store.read(), false);
      expect(f.controller.status.value.confirmed, false);
      f.intercept = null;
      await f.controller.sync(resetRetries: true);
      expect(f.serverNews, false);
      expect(f.controller.status.value.confirmed, true);
    },
  );

  test(
    'wrong installation, revision or category cannot acknowledge an actual controller request',
    () async {
      for (final mismatch in [
        'id',
        'registrationRevision',
        'favoritePlayerNews',
        'newsProtocol',
      ]) {
        SharedPreferences.setMockInitialValues({});
        final f = Fixture();
        try {
          await f.registered();
          await f.store.write(false);
          f.intercept = (_, body) async {
            final ack = f.ack(body);
            ack[mismatch] = switch (mismatch) {
              'id' => 'other-installation',
              'registrationRevision' =>
                (body['registrationRevision'] as int) - 1,
              'favoritePlayerNews' => true,
              _ => 0,
            };
            return http.Response(jsonEncode(ack), 200);
          };
          await expectLater(f.controller.preferenceChanged(), throwsStateError);
          expect(f.controller.status.value.confirmed, false);
          expect((await f.store.load()).ackRevision, isNull);
        } finally {
          f.controller.dispose();
        }
      }
    },
  );

  test(
    'failed revision persistence prevents every network attempt including detach',
    () async {
      final f = Fixture(store: RejectRevisionStore());
      addTearDown(f.controller.dispose);
      await f.controller.sync(register: true);
      expect(f.requests, isEmpty);
      expect((await f.store.load()).revision, 0);
      expect(await f.controller.detach(), false);
      expect(f.requests, isEmpty);
      expect((await f.store.load()).detachPending, true);
      expect(f.controller.status.value.confirmed, false);
    },
  );

  test('corrupt lifecycle never resets the fence or sends a request', () async {
    const encoded = '{"revision":"corrupt","enabled":false}';
    SharedPreferences.setMockInitialValues({
      FavoritePlayerNewsPreferenceStore.stateKey: encoded,
    });
    final f = Fixture();
    addTearDown(f.controller.dispose);
    await f.controller.sync(register: true);
    expect(f.requests, isEmpty);
    expect(f.controller.status.value.confirmed, false);
    expect(
      (await SharedPreferences.getInstance()).getString(
        FavoritePlayerNewsPreferenceStore.stateKey,
      ),
      encoded,
    );
  });

  test(
    'transient auth-barrier persistence failure stays pending and recovers without losing detach',
    () async {
      final store = RecoverableStore();
      final f = Fixture(store: store);
      addTearDown(f.controller.dispose);
      await f.registered();
      f.requests.clear();
      store.reject = true;
      f.session = const DirectPushSession('user-b', 'synthetic-user-b');
      await f.controller.authChanged('user-b');
      expect(f.controller.status.value.confirmed, false);
      expect(f.requests, isEmpty);
      store.reject = false;
      await f.controller.sync(register: true, resetRetries: true);
      expect(f.requests.first.url.path, '/v1/devices/logout');
      expect(f.serverOwner, 'user-b');
      expect(f.controller.status.value.confirmed, true);
    },
  );

  test(
    'category requests never change a disabled game/event installation opt-in',
    () async {
      final f = Fixture();
      addTearDown(f.controller.dispose);
      f.registrationOptedIn = false;
      await f.registered();
      expect(f.serverOptedIn, false);
      await f.store.write(false);
      await f.controller.preferenceChanged();
      expect(f.serverOptedIn, false);
      expect(f.serverNews, false);
      expect(f.controller.status.value.confirmed, true);
    },
  );

  test(
    'session expiry during an accepted registration retries detach without an SDK auth event',
    () async {
      final f = Fixture();
      addTearDown(f.controller.dispose);
      var expired = false;
      f.intercept = (request, body) async {
        if (request.url.path == '/v1/devices' && !expired) {
          expired = true;
          f.serverOwner = 'user-a';
          f.serverNews = body['favoritePlayerNews'] as bool;
          f.serverRevision = body['registrationRevision'] as int;
          f.session =
              null; // No authChanged event is delivered in this regression.
          return f.response(body);
        }
        return null;
      };
      await f.controller.sync(register: true);
      expect(f.controller.status.value.confirmed, false);
      expect((await f.store.load()).detachPending, true);
      await _waitFor(() => f.serverOwner == null);
      await f.controller.sync();
      expect((await f.store.load()).detachPending, false);
      expect(f.serverNews, false);
      expect(f.requests.last.url.path, '/v1/devices/logout');
      expect(f.requests.last.headers.containsKey('authorization'), false);
    },
  );

  test(
    'a hung platform readiness read cannot indefinitely block a queued opt-out',
    () async {
      final f = Fixture();
      addTearDown(f.controller.dispose);
      await f.registered();
      final sdk = Completer<Map<String, dynamic>?>();
      final entered = Completer<void>();
      var reads = 0;
      f.registrationReader = () {
        if (reads++ == 0) {
          entered.complete();
          return sdk.future;
        }
        return Future.value(null);
      };
      final registration = f.controller.sync(register: true);
      await entered.future;
      await f.store.write(false);
      final preference = f.controller.preferenceChanged();
      await Future.wait([registration, preference]);
      expect(sdk.isCompleted, false);
      expect(f.serverNews, false);
      expect(f.controller.status.value.confirmed, true);
      sdk.complete(null);
    },
  );

  test(
    'a newer token/readiness event queued during registration cannot be erased by its older ack',
    () async {
      final f = Fixture();
      addTearDown(f.controller.dispose);
      final entered = Completer<void>();
      final release = Completer<void>();
      f.intercept = (request, body) async {
        if (request.url.path == '/v1/devices' && !entered.isCompleted) {
          entered.complete();
          await release.future;
        }
        return null;
      };
      final initial = f.controller.sync(register: true);
      await entered.future;
      f.registrationToken = 'synthetic-fcm-token-refreshed-long';
      final refreshed = f.controller.sync(register: true, resetRetries: true);
      await Future<void>.delayed(Duration.zero);
      release.complete();
      await Future.wait([initial, refreshed]);
      expect(f.serverToken, f.registrationToken);
      expect(
        f.requests.where((r) => r.url.path == '/v1/devices'),
        hasLength(2),
      );
      expect(f.controller.status.value.confirmed, true);
      expect(f.serverOptedIn, true);
      expect(f.peak, 1);
    },
  );

  test(
    'provider drain pending cannot acknowledge optout until explicitly false',
    () async {
      final f = Fixture(maxAttempts: 1);
      addTearDown(f.controller.dispose);
      await f.registered();
      f.intercept = (request, body) async {
        if (request.url.path != '/v1/devices/preferences') return null;
        f.serverNews = false;
        f.serverRevision = body['registrationRevision'] as int;
        return http.Response(
          jsonEncode({...f.ack(body), 'newsDrainPending': true}),
          200,
        );
      };
      await f.store.write(false);
      await expectLater(f.controller.preferenceChanged(), throwsStateError);
      expect(f.controller.status.value.confirmed, false);
      expect((await f.store.load()).ackRevision, isNull);
      f.intercept = null;
      await f.controller.sync(resetRetries: true);
      expect(f.controller.status.value.confirmed, true);
      expect(f.serverNews, false);
    },
  );

  test(
    'provider drain pending keeps proof-only detach durable through session loss',
    () async {
      final f = Fixture(maxAttempts: 1);
      addTearDown(f.controller.dispose);
      await f.registered();
      f.intercept = (request, body) async {
        if (request.url.path != '/v1/devices/logout') return null;
        f.serverOwner = null;
        f.serverNews = false;
        f.serverRevision = body['registrationRevision'] as int;
        return http.Response(
          jsonEncode({
            ...f.ack(body, detached: true),
            'newsDrainPending': true,
          }),
          200,
        );
      };
      expect(await f.controller.detach(), false);
      expect((await f.store.load()).detachPending, true);
      f.intercept = null;
      f.session = null;
      await f.controller.sync(resetRetries: true);
      expect((await f.store.load()).detachPending, false);
      expect((await f.store.load()).owner, isNull);
      expect(f.requests.last.url.path, '/v1/devices/logout');
      expect(f.requests.last.headers.containsKey('authorization'), false);
    },
  );

  test('exhausted revision fails closed without resetting fence', () async {
    final f = Fixture();
    addTearDown(f.controller.dispose);
    await f.store.update((s) => s.revision = 9007199254740991);
    await f.controller.sync(register: true);
    expect(f.requests, isEmpty);
    expect(f.controller.status.value.confirmed, false);
    expect((await f.store.load()).revision, 9007199254740991);
  });
}
