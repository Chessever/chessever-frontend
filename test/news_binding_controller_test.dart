// Test-only in-memory implementation of the installed preferences backend.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:convert';
import 'package:chessever2/services/direct_push_service.dart';
import 'package:chessever2/services/direct_push_registration_controller.dart';
import 'package:chessever2/services/news_binding_store.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'direct_push_registration_controller_test.dart'
    show Fixture, installation;

Map<String, dynamic> callback(Map<String, dynamic> intent) => {
  'type': NewsBindingStore.type,
  'audience': NewsBindingStore.audience,
  'installationId': intent['installationId'],
  'userId': intent['userId'],
  'requestId': intent['requestId'],
  'registrationRevision': intent['registrationRevision'].toString(),
  'tokenHash': NewsBindingStore.tokenHash(intent['token'] as String),
  'platform': intent['platform'],
  'challengeId': '30000000-0000-4000-8000-000000000001',
  'nonce': 'a' * 64,
  'expiresAt': DateTime.now().add(const Duration(minutes: 4)).toIso8601String(),
};

void install(
  Fixture f, {
  Future<void> Function(Map<String, dynamic>)? onIssue,
}) {
  f.intercept = (request, body) async {
    if (request.url.path == '/v1/devices') {
      if (body['favoritePlayerNews'] == false) return null;
      f.serverRevision = body['registrationRevision'] as int;
      return http.Response(
        jsonEncode({
          ...f.ack(body),
          'favoritePlayerNews': false,
          'newsBindingRequired': true,
        }),
        200,
      );
    }
    if (request.url.path == '/v1/devices/news-challenge') {
      final active = await NewsBindingStore().intent();
      expect(
        active,
        isNotNull,
        reason: 'Intent must be durably present BEFORE issuance',
      );
      expect(active!['registrationRevision'], body['registrationRevision']);
      expect(active['requestId'], body['requestId']);
      await onIssue?.call(active);
      return http.Response(
        jsonEncode({'state': 'pending', 'requestId': body['requestId']}),
        200,
      );
    }
    if (request.url.path == '/v1/devices/news-confirm') {
      expect(body['audience'], NewsBindingStore.audience);
      expect(body['nonce'], 'a' * 64);
      expect(body['installationId'], installation);
      f.serverRevision = body['registrationRevision'] as int;
      f.serverOwner = f.session?.userId;
      f.serverNews = true;
      return f.response({...body, 'favoritePlayerNews': true});
    }
    return null;
  };
}

int confirmations(Fixture f) =>
    f.requests.where((r) => r.url.path == '/v1/devices/news-confirm').length;
int issues(Fixture f) =>
    f.requests.where((r) => r.url.path == '/v1/devices/news-challenge').length;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  test(
    'pre-confirmation readiness refresh preserves newer destination reconciliation',
    () async {
      final f = Fixture(maxAttempts: 1);
      addTearDown(f.controller.dispose);
      install(f);
      await f.controller.sync(register: true);
      final active = (await NewsBindingStore().intent())!;
      await directPushBackgroundHandler(RemoteMessage(data: callback(active)));
      final entered = Completer<void>();
      final release = Completer<Map<String, dynamic>?>();
      var firstRead = true;
      final old = <String, dynamic>{
        'token': active['token'],
        'platform': active['platform'],
        'optedIn': active['optedIn'],
        'appVersion': '0.0.0+0',
        'oneSignalSubscriptionId': 'synthetic-subscription',
        'language': 'en',
        'timezone': 'UTC',
      };
      f.registrationReader = () {
        if (firstRead) {
          firstRead = false;
          entered.complete();
          return release.future;
        }
        return Future.value({...old, 'token': f.registrationToken});
      };
      final first = f.controller.sync(resetRetries: true);
      await entered.future;
      f.registrationToken = 'synthetic-fcm-token-new-during-readiness';
      final next = f.controller.sync(register: true, resetRetries: true);
      await Future<void>.delayed(Duration.zero);
      release.complete(old);
      await Future.wait([first, next]);
      expect(issues(f), 2);
      expect((await NewsBindingStore().intent())?['token'], f.registrationToken);
      expect(f.controller.status.value.confirmed, false);
    },
  );
  test(
    'token refresh during blocked confirmation retains newer registration and reproves rotated destination',
    () async {
      final f = Fixture();
      addTearDown(f.controller.dispose);
      install(f);
      await f.controller.sync(register: true);
      final active = (await NewsBindingStore().intent())!;
      await directPushBackgroundHandler(RemoteMessage(data: callback(active)));
      final entered = Completer<void>(), release = Completer<void>();
      final base = f.intercept!;
      f.intercept = (request, body) async {
        if (request.url.path == '/v1/devices/news-confirm') {
          entered.complete();
          await release.future;
        }
        return base(request, body);
      };
      final first = f.controller.sync(resetRetries: true);
      await entered.future;
      f.registrationToken = 'synthetic-fcm-token-newer-in-flight';
      final next = f.controller.sync(register: true, resetRetries: true);
      release.complete();
      await first;
      await next;
      expect(confirmations(f), 1);
      expect(issues(f), 2);
      expect(
        (await NewsBindingStore().intent())!['token'],
        f.registrationToken,
      );
      expect(f.controller.status.value.confirmed, false);
    },
  );
  test(
    'unproved competing legacy destination still reaches challenge and actual confirmation',
    () async {
      final f = Fixture();
      addTearDown(f.controller.dispose);
      f.serverOwner = 'foreign-legacy-owner';
      install(
        f,
        onIssue: (active) =>
            directPushBackgroundHandler(RemoteMessage(data: callback(active))),
      );
      await f.controller.sync(register: true);
      expect(issues(f), 1);
      expect(confirmations(f), 1);
      expect(f.serverOwner, 'user-a');
      expect(f.controller.status.value.confirmed, true);
    },
  );
  test(
    'real background callback before issue acknowledgement confirms exact durable intent',
    () async {
      final f = Fixture();
      addTearDown(f.controller.dispose);
      install(
        f,
        onIssue: (active) =>
            directPushBackgroundHandler(RemoteMessage(data: callback(active))),
      );
      await f.controller.sync(register: true);
      expect(confirmations(f), 1);
      expect(issues(f), 1);
      expect(f.controller.status.value.confirmed, true);
      expect(await NewsBindingStore().intent(), isNull);
    },
  );
  test(
    'cold restart drains background callback without allocating a newer revision or reissuing',
    () async {
      final f = Fixture();
      install(f);
      await f.controller.sync(register: true);
      final active = (await NewsBindingStore().intent())!;
      final revision = (await f.store.load()).revision;
      f.controller.dispose();
      // The background isolate does not need Supabase/session initialization.
      f.session = null;
      await directPushBackgroundHandler(RemoteMessage(data: callback(active)));
      f.session = const DirectPushSession('user-a', 'synthetic-user-a');
      f.controller = f.create();
      addTearDown(f.controller.dispose);
      await f.controller.sync(register: true);
      expect(confirmations(f), 1);
      expect(issues(f), 1);
      expect((await f.store.load()).revision, revision);
      expect(f.controller.status.value.confirmed, true);
    },
  );
  test(
    'missing callback stays visibly pending and bounded retries do not invalidate own intent',
    () async {
      final f = Fixture(maxAttempts: 3);
      addTearDown(f.controller.dispose);
      install(f);
      await f.controller.sync(register: true);
      final revision = (await f.store.load()).revision;
      for (var n = 0; n < 4; n++) {
        await f.controller.sync(resetRetries: true);
      }
      expect(issues(f), 1);
      expect(confirmations(f), 0);
      expect((await f.store.load()).revision, revision);
      expect(f.controller.status.value.confirmed, false);
    },
  );
  for (final field in [
    'installationId',
    'userId',
    'requestId',
    'registrationRevision',
    'tokenHash',
    'platform',
    'audience',
    'nonce',
    'challengeId',
    'expiresAt',
  ]) {
    test(
      'actual background callback rejects wrong $field without confirmation or receipt',
      () async {
        final f = Fixture();
        addTearDown(f.controller.dispose);
        install(f);
        await f.controller.sync(register: true);
        final active = (await NewsBindingStore().intent())!;
        final data = callback(active);
        data[field] = 'wrong';
        data['delivery_id'] = 'must-not-become-receipt';
        await directPushBackgroundHandler(RemoteMessage(data: data));
        await f.controller.sync(resetRetries: true);
        expect(confirmations(f), 0);
        expect(await NewsBindingStore().callback(active), isNull);
        expect(
          (await SharedPreferencesAsync().getKeys()).any(
            (k) => k.startsWith('direct_push_event_'),
          ),
          false,
        );
      },
    );
  }
  test(
    'copied victim token callback with attacker installation/request never acknowledges',
    () async {
      final f = Fixture();
      addTearDown(f.controller.dispose);
      install(f);
      await f.controller.sync(register: true);
      final active = (await NewsBindingStore().intent())!;
      final data = callback(active)
        ..['installationId'] = 'attacker-installation'
        ..['requestId'] = 'attacker-request'
        ..['userId'] = 'attacker-owner';
      await directPushBackgroundHandler(RemoteMessage(data: data));
      await f.controller.sync(resetRetries: true);
      expect(confirmations(f), 0);
      expect(f.controller.status.value.confirmed, false);
    },
  );
  test(
    'token rotation invalidates old callback, registers current token and creates fresh intent',
    () async {
      final f = Fixture();
      addTearDown(f.controller.dispose);
      install(f);
      await f.controller.sync(register: true);
      final old = (await NewsBindingStore().intent())!;
      await directPushBackgroundHandler(RemoteMessage(data: callback(old)));
      f.registrationToken = 'synthetic-fcm-token-rotated-now';
      await f.controller.sync(register: true, resetRetries: true);
      final active = (await NewsBindingStore().intent())!;
      expect(confirmations(f), 0);
      expect(active['token'], f.registrationToken);
      expect(active['requestId'], isNot(old['requestId']));
      expect(issues(f), 2);
    },
  );
  test(
    'optout invalidates queued callback while preserving category-only acknowledgement',
    () async {
      final f = Fixture();
      addTearDown(f.controller.dispose);
      install(f);
      await f.controller.sync(register: true);
      final active = (await NewsBindingStore().intent())!;
      await directPushBackgroundHandler(RemoteMessage(data: callback(active)));
      await f.store.write(false);
      await f.controller.preferenceChanged();
      expect(confirmations(f), 0);
      expect(f.serverNews, false);
      expect(f.controller.status.value.confirmed, true);
      expect(await NewsBindingStore().intent(), isNull);
    },
  );
  test(
    'logout while issue response is delayed cannot confirm or restore stale intent',
    () async {
      final f = Fixture();
      addTearDown(f.controller.dispose);
      final entered = Completer<void>(), release = Completer<void>();
      install(
        f,
        onIssue: (active) async {
          await directPushBackgroundHandler(
            RemoteMessage(data: callback(active)),
          );
          entered.complete();
          await release.future;
        },
      );
      final sync = f.controller.sync(register: true);
      await entered.future;
      f.session = null;
      final logout = f.controller.authChanged(null);
      release.complete();
      await sync;
      await logout;
      expect(confirmations(f), 0);
      expect(f.serverOwner, isNull);
      expect(await NewsBindingStore().intent(), isNull);
      expect((await f.store.load()).detachPending, false);
    },
  );
  test(
    'account replacement discards queued callback and cannot reuse old owner intent',
    () async {
      final f = Fixture();
      addTearDown(f.controller.dispose);
      install(f);
      await f.controller.sync(register: true);
      final active = (await NewsBindingStore().intent())!;
      await directPushBackgroundHandler(RemoteMessage(data: callback(active)));
      f.session = const DirectPushSession('user-b', 'synthetic-user-b');
      await f.controller.authChanged('user-b');
      expect(confirmations(f), 0);
      expect((await NewsBindingStore().intent())!['userId'], 'user-b');
      expect(issues(f), 2);
    },
  );
  test(
    'expired callback and arbitrary reserved type are swallowed, no local event',
    () async {
      final f = Fixture();
      addTearDown(f.controller.dispose);
      install(f);
      await f.controller.sync(register: true);
      final active = (await NewsBindingStore().intent())!;
      await directPushBackgroundHandler(
        RemoteMessage(
          data: {
            ...callback(active),
            'expiresAt': DateTime.now()
                .subtract(const Duration(seconds: 1))
                .toIso8601String(),
          },
        ),
      );
      expect(
        await NewsBindingStore().receive({
          'type': NewsBindingStore.type,
          'route': '/attacker',
        }),
        true,
      );
      await f.controller.sync(resetRetries: true);
      expect(confirmations(f), 0);
    },
  );
  test(
    'old background writes cannot replace newer foreground intent or callback',
    () async {
      final store = NewsBindingStore();
      final old = {
        'installationId': installation,
        'userId': 'user-a',
        'requestId': NewsBindingStore.requestId(),
        'registrationRevision': 1,
        'token': 'synthetic-token',
        'platform': 'ios',
      };
      await store.save(old);
      await store.receive(callback(old));
      final current = {
        ...old,
        'requestId': NewsBindingStore.requestId(),
        'registrationRevision': 2,
      };
      await store.save(current);
      await NewsBindingStore().receive(callback(old));
      expect((await store.intent())!['requestId'], current['requestId']);
      expect(await store.callback(current), isNull);
      await NewsBindingStore().receive(callback(current));
      expect(await store.callback(current), isNotNull);
    },
  );
}
