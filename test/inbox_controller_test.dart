import 'dart:async';

import 'package:chessever2/providers/app_resume_signal_provider.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/screens/inbox/inbox_message.dart';
import 'package:chessever2/screens/inbox/inbox_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'inbox_fakes.dart';

final _identity = StateProvider<String?>((ref) => inboxOwnerA);
AppUser _user(String id) =>
    AppUser(id: id, createdAt: DateTime.utc(2026), isAnonymous: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeInboxSource source;
  late FakeInboxCache cache;
  late InboxController controller;
  setUp(() {
    source = FakeInboxSource();
    cache = FakeInboxCache();
    controller = InboxController(
      ownerId: inboxOwnerA,
      source: source,
      cache: cache,
    );
  });
  tearDown(() {
    if (controller.mounted) controller.dispose();
  });

  test('startup fetches guest audience without marking any row', () async {
    await controller.start();
    expect(controller.state.loading, false);
    expect(controller.state.messages, hasLength(2));
    expect(controller.state.hasUnread, true);
    expect(source.marks, isEmpty);
    expect(source.fetches, [inboxOwnerA]);
  });
  test(
    'mark-specific-only, duplicate opens idempotent, dots until last read',
    () async {
      await controller.start();
      expect(await controller.markOpened(inboxIdA), true);
      expect(controller.state.message(inboxIdA)!.isUnread, false);
      expect(controller.state.message(inboxIdB)!.isUnread, true);
      expect(controller.state.hasUnread, true);
      expect(await controller.markOpened(inboxIdA), true);
      expect(source.marks, [(inboxOwnerA, inboxIdA)]);
      await controller.markOpened(inboxIdB);
      expect(controller.state.hasUnread, false);
    },
  );
  test('unknown ID cannot be marked', () async {
    await controller.start();
    expect(await controller.markOpened('unknown'), false);
    expect(source.marks, isEmpty);
  });
  test(
    'server-confirmed reads persist through restart while offline',
    () async {
      await controller.start();
      await controller.markOpened(inboxIdA);
      controller.dispose();
      source.failFetch = true;
      controller = InboxController(
        ownerId: inboxOwnerA,
        source: source,
        cache: cache,
      );
      await controller.start();
      expect(controller.state.message(inboxIdA)!.readAt, inboxReadTime);
      expect(controller.state.message(inboxIdB)!.isUnread, true);
      expect(controller.state.syncError, isNotNull);
      expect(controller.state.hasUnread, true);
    },
  );
  test(
    'failed fetch preserves cached rows and unread dots; retry syncs',
    () async {
      await cache.save(inboxOwnerA, [inboxFixture(inboxIdA)]);
      source.failFetch = true;
      await controller.start();
      expect(controller.state.messages, hasLength(1));
      expect(controller.state.hasUnread, true);
      source.failFetch = false;
      await controller.refresh();
      expect(controller.state.syncError, isNull);
      expect(controller.state.messages, hasLength(2));
    },
  );
  test(
    'failed mark is not persisted or optimistic; explicit retry works',
    () async {
      await controller.start();
      source.failMark = true;
      expect(await controller.markOpened(inboxIdA), false);
      expect(controller.state.message(inboxIdA)!.isUnread, true);
      expect(controller.state.markErrors[inboxIdA], isNotNull);
      expect((await cache.load(inboxOwnerA))!.first.isUnread, true);
      source.failMark = false;
      await controller.markOpened(inboxIdA);
      expect(controller.state.markErrors[inboxIdA], isNull);
      expect(controller.state.message(inboxIdA)!.isUnread, false);
    },
  );
  test(
    'pending mark leaves dots; duplicate concurrent open does not double write',
    () async {
      await controller.start();
      final gate = Completer<DateTime>();
      source.markOverride = (_, _) => gate.future;
      final mark = controller.markOpened(inboxIdA);
      expect(controller.state.hasUnread, true);
      expect(controller.state.marking, contains(inboxIdA));
      expect(await controller.markOpened(inboxIdA), false);
      gate.complete(inboxReadTime);
      expect(await mark, true);
      expect(source.marks, hasLength(1));
    },
  );
  test(
    'stale refresh cannot resurrect a concurrently confirmed read',
    () async {
      await controller.start();
      final gate = Completer<List<InboxMessage>>();
      source.fetchOverride = (_) => gate.future;
      final refreshing = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      await controller.markOpened(inboxIdA);
      gate.complete([inboxFixture(inboxIdA), inboxFixture(inboxIdB)]);
      await refreshing;
      expect(controller.state.message(inboxIdA)!.isUnread, false);
      expect(controller.state.message(inboxIdB)!.isUnread, true);
      expect((await cache.load(inboxOwnerA))!.first.isUnread, false);
    },
  );
  test(
    'startup and list refresh wait for cache restore, fetch only once',
    () async {
      cache.loadGate = Completer<void>();
      final start = controller.start();
      final refresh = controller.refresh();
      expect(source.fetches, isEmpty);
      cache.loadGate!.complete();
      await Future.wait([start, refresh]);
      expect(source.fetches, [inboxOwnerA]);
    },
  );
  test('cache failures remain visible without breaking server sync', () async {
    cache.failLoad = true;
    cache.failSave = true;
    await controller.start();
    expect(controller.state.messages, hasLength(2));
    expect(controller.state.cacheError, isNotNull);
    expect(await controller.markOpened(inboxIdA), true);
    expect(controller.state.message(inboxIdA)!.readAt, inboxReadTime);
    expect(controller.state.cacheError, isNotNull);
    cache.failSave = false;
    await controller.refresh();
    expect(controller.state.cacheError, isNull);
  });
  test('server reads from another device sync on refresh', () async {
    await controller.start();
    source.rows[inboxOwnerA] = [
      inboxFixture(inboxIdA, readAt: inboxReadTime),
      inboxFixture(inboxIdB, readAt: inboxReadTime),
    ];
    await controller.refresh();
    expect(controller.state.hasUnread, false);
    expect(source.marks, isEmpty);
  });
  test(
    'refresh reconciles lost mark acknowledgement and clears stale error',
    () async {
      await controller.start();
      source.failMark = true;
      await controller.markOpened(inboxIdA);
      expect(controller.state.markErrors[inboxIdA], isNotNull);
      source.rows[inboxOwnerA] = [
        inboxFixture(inboxIdA, readAt: inboxReadTime),
        inboxFixture(inboxIdB),
      ];
      await controller.refresh();
      expect(controller.state.markErrors[inboxIdA], isNull);
      expect(controller.state.message(inboxIdA)!.isUnread, false);
      expect(controller.state.message(inboxIdB)!.isUnread, true);
    },
  );
  test(
    'provider account switch rejects late fetch and isolates every cache',
    () async {
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWith((ref) {
            final id = ref.watch(_identity);
            return id == null ? null : _user(id);
          }),
          inboxSourceProvider.overrideWithValue(source),
          inboxCacheProvider.overrideWithValue(cache),
        ],
      );
      addTearDown(container.dispose);
      final gate = Completer<List<InboxMessage>>();
      source.fetchOverride = (owner) =>
          owner == inboxOwnerA ? gate.future : Future.value(source.rows[owner]);
      final a = container.read(inboxProvider.notifier);
      final start = a.start();
      await Future<void>.delayed(Duration.zero);
      container.read(_identity.notifier).state = inboxOwnerB;
      final b = container.read(inboxProvider.notifier);
      await b.start();
      gate.complete(source.rows[inboxOwnerA]!);
      await start;
      expect(a.mounted, false);
      expect(container.read(inboxProvider).ownerId, inboxOwnerB);
      expect(container.read(inboxProvider).messages.map((m) => m.id), [
        inboxIdB,
      ]);
      expect(cache.encoded.containsKey(inboxOwnerA), false);
      container.read(_identity.notifier).state = null;
      expect(container.read(inboxProvider).messages, isEmpty);
      expect(container.read(inboxHasUnreadProvider), false);
    },
  );
  test('late mark after switch cannot write new account cache', () async {
    await controller.start();
    final gate = Completer<DateTime>();
    source.markOverride = (_, _) => gate.future;
    final pending = controller.markOpened(inboxIdA);
    controller.dispose();
    controller = InboxController(
      ownerId: inboxOwnerB,
      source: source,
      cache: cache,
    );
    await controller.start();
    gate.complete(inboxReadTime);
    expect(await pending, false);
    expect(controller.state.message(inboxIdB)!.isUnread, true);
    expect((await cache.load(inboxOwnerB))!.single.isUnread, true);
    expect((await cache.load(inboxOwnerA))!.first.isUnread, true);
  });
  test(
    'resume signal refreshes without any push permission dependency',
    () async {
      final container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithValue(_user(inboxOwnerA)),
          inboxSourceProvider.overrideWithValue(source),
          inboxCacheProvider.overrideWithValue(cache),
        ],
      );
      addTearDown(container.dispose);
      final c = container.read(inboxProvider.notifier);
      await c.start();
      container.read(appResumedSignalProvider.notifier).state++;
      await c.refresh();
      expect(source.fetches, [inboxOwnerA, inboxOwnerA]);
      expect(source.marks, isEmpty);
    },
  );
  test(
    'successful empty source is empty, failure is not fake empty success',
    () async {
      source.rows[inboxOwnerA] = [];
      await controller.start();
      expect(controller.state.messages, isEmpty);
      expect(controller.state.syncError, isNull);
      source.failFetch = true;
      await controller.refresh();
      expect(controller.state.syncError, isNotNull);
    },
  );
}
