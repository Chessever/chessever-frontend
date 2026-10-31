import 'dart:async';
import 'dart:convert';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/notification_preferences_provider.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, Map<String, dynamic>> accounts;
  late List<Map<String, dynamic>> writes;
  late SupabaseClient client;
  late bool failWrite;
  Completer<void>? blockedWrite;
  setUp(() {
    accounts = {
      'account-a': {
        'favorite_player_news_alerts': true,
        'favorite_player_alerts': false,
        'favorite_event_alerts': true,
      },
      'account-b': {'favorite_player_news_alerts': true},
    };
    writes = [];
    failWrite = false;
    blockedWrite = null;
    client = SupabaseClient(
      'https://fixture.invalid',
      'synthetic-public-key',
      httpClient: MockClient((request) async {
        expect(request.url.path, '/rest/v1/user_notification_preferences');
        if (request.method == 'GET') {
          final owner = request.url.queryParameters['user_id']!.substring(3);
          return http.Response(
            jsonEncode(accounts[owner]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        final row = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
        writes.add(row);
        await blockedWrite?.future;
        if (failWrite) {
          return http.Response(
            '{"code":"synthetic","message":"Offline fixture"}',
            503,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        accounts[row['user_id']]!.addAll(row);
        return http.Response('', 201, request: request);
      }),
    );
  });
  tearDown(() async => client.dispose());
  final ownerProvider = StateProvider<String?>((ref) => 'account-a');
  ProviderContainer device() => ProviderContainer(
    overrides: [
      notificationPreferencesClientProvider.overrideWithValue(client),
      currentUserProvider.overrideWith((ref) {
        final id = ref.watch(ownerProvider);
        return id == null
            ? null
            : AppUser(id: id, createdAt: DateTime.utc(2026), isAnonymous: true);
      }),
    ],
  );

  test(
    'two devices share account News choice while games/events remain unchanged',
    () async {
      final first = device(), second = device();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      await first.read(notificationPreferencesProvider.future);
      await second.read(notificationPreferencesProvider.future);
      await first
          .read(notificationPreferencesProvider.notifier)
          .setFavoritePlayerNewsAlerts(false);
      expect(writes.single, {
        'user_id': 'account-a',
        'favorite_player_news_alerts': false,
      });
      second.invalidate(notificationPreferencesProvider);
      final restored = await second.read(
        notificationPreferencesProvider.future,
      );
      expect(restored.favoritePlayerNewsAlerts, false);
      expect(restored.favoritePlayerAlerts, false);
      expect(restored.favoriteEventAlerts, true);
    },
  );
  test(
    'changing accounts reads the new owner instead of restoring device-local News choice',
    () async {
      final c = device();
      addTearDown(c.dispose);
      await c.read(notificationPreferencesProvider.future);
      await c
          .read(notificationPreferencesProvider.notifier)
          .setFavoritePlayerNewsAlerts(false);
      c.read(ownerProvider.notifier).state = 'account-b';
      await c.read(notificationPreferencesProvider.future);
      expect(
        c
            .read(notificationPreferencesProvider)
            .requireValue
            .favoritePlayerNewsAlerts,
        true,
      );
      await c
          .read(notificationPreferencesProvider.notifier)
          .setFavoritePlayerNewsAlerts(false);
      expect(writes.map((r) => r['user_id']), ['account-a', 'account-b']);
    },
  );
  test(
    'failed account save reports an error and restores the previously confirmed toggle',
    () async {
      final c = device();
      addTearDown(c.dispose);
      await c.read(notificationPreferencesProvider.future);
      failWrite = true;
      await expectLater(
        c
            .read(notificationPreferencesProvider.notifier)
            .setFavoritePlayerNewsAlerts(false),
        throwsA(isA<PostgrestException>()),
      );
      expect(
        c
            .read(notificationPreferencesProvider)
            .requireValue
            .favoritePlayerNewsAlerts,
        true,
      );
      expect(accounts['account-a']!['favorite_player_news_alerts'], true);
    },
  );
  test('rapid toggles serialize and persist the last account choice', () async {
    final c = device();
    addTearDown(c.dispose);
    await c.read(notificationPreferencesProvider.future);
    final n = c.read(notificationPreferencesProvider.notifier);
    await Future.wait([
      n.setFavoritePlayerNewsAlerts(false),
      n.setFavoritePlayerNewsAlerts(true),
      n.setFavoritePlayerNewsAlerts(false),
    ]);
    expect(writes.map((r) => r['favorite_player_news_alerts']), [
      false,
      true,
      false,
    ]);
    expect(accounts['account-a']!['favorite_player_news_alerts'], false);
  });
  test(
    'queued toggle from the previous account cannot change the next account',
    () async {
      final c = device();
      addTearDown(c.dispose);
      await c.read(notificationPreferencesProvider.future);
      blockedWrite = Completer<void>();
      final n = c.read(notificationPreferencesProvider.notifier);
      final first = n.setFavoritePlayerNewsAlerts(false);
      await Future<void>.delayed(Duration.zero);
      final queued = n.setFavoritePlayerNewsAlerts(true);
      c.read(ownerProvider.notifier).state = 'account-b';
      await c.read(notificationPreferencesProvider.future);
      blockedWrite!.complete();
      await Future.wait([first, queued]);
      expect(writes, hasLength(1));
      expect(writes.single['user_id'], 'account-a');
      expect(
        c
            .read(notificationPreferencesProvider)
            .requireValue
            .favoritePlayerNewsAlerts,
        true,
      );
    },
  );
  test(
    'resuming another device reloads the account setting without waiting for a silent push',
    () async {
      final c = device();
      addTearDown(c.dispose);
      await c.read(notificationPreferencesProvider.future);
      accounts['account-a']!['favorite_player_news_alerts'] = false;
      c
          .read(notificationPreferencesProvider.notifier)
          .didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(
        (await c.read(
          notificationPreferencesProvider.future,
        )).favoritePlayerNewsAlerts,
        false,
      );
      expect(writes, isEmpty);
    },
  );
  test('an unrelated game preference save cannot restore stale News state from another device', () async {
    final c = device(); addTearDown(c.dispose);
    await c.read(notificationPreferencesProvider.future);
    accounts['account-a']!['favorite_player_news_alerts'] = false;
    await c.read(notificationPreferencesProvider.notifier).setHeadsUpAlerts(true);
    expect(writes.single.containsKey('favorite_player_news_alerts'), false);
    expect(accounts['account-a']!['favorite_player_news_alerts'], false);
  });
  test('disable all includes News even when this device has a stale disabled value', () async {
    accounts['account-a']!['favorite_player_news_alerts'] = false;
    final c = device(); addTearDown(c.dispose);
    await c.read(notificationPreferencesProvider.future);
    accounts['account-a']!['favorite_player_news_alerts'] = true;
    await c.read(notificationPreferencesProvider.notifier).disableAll();
    expect(writes.single['favorite_player_news_alerts'], false);
    expect(accounts['account-a']!['favorite_player_news_alerts'], false);
  });

}
