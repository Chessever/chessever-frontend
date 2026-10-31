import 'dart:async';

import 'package:chessever2/providers/push_token_sync_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'actual mirror controller advances token and optout while direct startup never completes',
    () async {
      final pending = Completer<void>();
      final writes = <Map<String, dynamic>>[];
      final handoffs = <List<Object>>[];
      final provider = Provider<PushTokenSyncController>((ref) {
        final value = PushTokenSyncController(
          ref,
          currentUserId: () => 'synthetic-user',
          writeMirror: (row) async => writes.add(Map.of(row)),
          directHandoff: (id, optedIn) {
            handoffs.add([id, optedIn]);
            return pending.future;
          },
        );
        ref.onDispose(value.dispose);
        return value;
      });
      final container = ProviderContainer();
      addTearDown(() {
        if (!pending.isCompleted) pending.complete();
        container.dispose();
      });
      final value = container.read(provider);
      await value.syncMirrorForTesting(
        userId: 'synthetic-user',
        subscriptionId: 'synthetic-subscription',
        token: 'synthetic-old-token',
        optedIn: true,
      );
      await value
          .syncMirrorForTesting(
            userId: 'synthetic-user',
            subscriptionId: 'synthetic-subscription',
            token: 'synthetic-new-token',
            optedIn: false,
          )
          .timeout(const Duration(milliseconds: 200));
      expect(pending.isCompleted, false);
      expect(writes.map((row) => row['push_token']), [
        'synthetic-old-token',
        'synthetic-new-token',
      ]);
      expect(writes.last['opted_in'], false);
      expect(handoffs.last, ['synthetic-subscription', false]);
      expect(
        writes.every(
          (row) =>
              !row.containsKey('favorite_player_news') &&
              !row.containsKey('registrationRevision'),
        ),
        true,
      );
    },
  );

  test('mirror writes remain serialized when direct handoff throws', () async {
    final entered = Completer<void>(), release = Completer<void>();
    final writes = <String>[];
    var active = 0, peak = 0;
    final provider = Provider<PushTokenSyncController>((ref) {
      final value = PushTokenSyncController(
        ref,
        currentUserId: () => 'synthetic-user',
        writeMirror: (row) async {
          active++;
          if (active > peak) peak = active;
          writes.add(row['push_token'] as String);
          if (writes.length == 1) {
            entered.complete();
            await release.future;
          }
          active--;
        },
        directHandoff: (_, __) async {
          throw StateError('Synthetic native startup failure');
        },
      );
      ref.onDispose(value.dispose);
      return value;
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final value = container.read(provider);
    final first = value.syncMirrorForTesting(
      userId: 'synthetic-user',
      subscriptionId: 'synthetic-subscription',
      token: 'old',
      optedIn: true,
    );
    await entered.future;
    final second = value.syncMirrorForTesting(
      userId: 'synthetic-user',
      subscriptionId: 'synthetic-subscription',
      token: 'new',
      optedIn: false,
    );
    await Future<void>.delayed(Duration.zero);
    expect(writes, ['old']);
    release.complete();
    await Future.wait([first, second]);
    expect(writes, ['old', 'new']);
    expect(peak, 1);
  });

  test(
    'auth replacement during mirror write cannot hand old account state to direct service',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      var owner = 'old-user';
      final handoffs = <String>[];
      final provider = Provider<PushTokenSyncController>((ref) {
        final value = PushTokenSyncController(
          ref,
          currentUserId: () => owner,
          writeMirror: (row) async {
            if (row['user_id'] == 'old-user') {
              entered.complete();
              await release.future;
            }
          },
          directHandoff: (id, _) async {
            handoffs.add(id);
          },
        );
        ref.onDispose(value.dispose);
        return value;
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final value = container.read(provider);
      final old = value.syncMirrorForTesting(
        userId: 'old-user',
        subscriptionId: 'old-subscription',
        token: 'old',
        optedIn: true,
      );
      await entered.future;
      owner = 'new-user';
      final next = value.syncMirrorForTesting(
        userId: 'new-user',
        subscriptionId: 'new-subscription',
        token: 'new',
        optedIn: false,
      );
      release.complete();
      await Future.wait([old, next]);
      expect(handoffs, ['new-subscription']);
    },
  );
}
