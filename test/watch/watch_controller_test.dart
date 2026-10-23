import 'dart:async';
import 'dart:convert';
import 'package:chessever2/watch/core/watch_account.dart';
import 'package:chessever2/watch/core/watch_repository.dart';
import 'package:chessever2/watch/watch_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_watch_link/flutter_watch_link.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeWatchLink extends WatchLinkBackend {
  final incoming = StreamController<WatchLinkMessage>.broadcast(sync: true);
  final stateChanges = StreamController<WatchLinkState>.broadcast(sync: true);
  Map<String, Object?>? context;
  final sent = <Map<String, Object?>>[];
  final queued = <Map<String, Object?>>[];
  WatchLinkState state = const WatchLinkState(
    activated: true,
    reachable: true,
    counterpartInstalled: true,
    counterpartPaired: true,
  );
  @override
  Stream<WatchLinkMessage> get messages => incoming.stream;
  @override
  Stream<WatchLinkState> get states => stateChanges.stream;
  @override
  Stream<String> get errors => const Stream.empty();
  @override
  Future<void> activate() async {
    stateChanges.add(state);
  }

  @override
  Future<Map<String, Object?>?> receivedApplicationContext() async => context;
  @override
  Future<void> sendMessage(Map<String, Object?> payload) async {
    sent.add(payload);
  }

  @override
  Future<void> transferUserInfo(Map<String, Object?> payload) async {
    queued.add(payload);
  }

  @override
  Future<int> outstandingTransferCount() async => queued.length;
  @override
  Future<Map<String, Object?>> sendMessageWithReply(
    Map<String, Object?> payload, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    sent.add(payload);
    return {'accepted': true};
  }

  @override
  Future<void> dispose() async {
    await incoming.close();
    await stateChanges.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeWatchLink link;
  late WatchController controller;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    link = FakeWatchLink();
    WatchLink.backendOverride = link;
    controller = WatchController(
      repository: WatchRepository(
        apiKey: 'key',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode([
              {'id': 'one', 'name': 'One'},
              {'id': 'two', 'name': 'Two'},
            ]),
            200,
          ),
        ),
      ),
    );
  });
  tearDown(() async {
    controller.dispose();
    await link.dispose();
    WatchLink.backendOverride = null;
  });

  void deliver(WatchAccount account) => link.incoming.add(
    WatchLinkMessage(payload: account.toJson(), tier: WatchLinkTier.message),
  );

  test(
    'cold context sync, duplicate delivery and logout cannot resurrect an old account',
    () async {
      link.context = const WatchAccount(
        revision: 10,
        userId: 'old',
        name: 'Old',
        eventIds: ['two'],
      ).toJson();
      await controller.initialize();
      expect(controller.visibleEvents.first.id, 'two');
      deliver(const WatchAccount(revision: 10, userId: 'old'));
      expect(controller.account.eventIds, ['two']);
      deliver(const WatchAccount(revision: 11));
      deliver(
        const WatchAccount(revision: 10, userId: 'old', eventIds: ['two']),
      );
      expect(controller.account.signedIn, isFalse);
      expect(controller.account.eventIds, isEmpty);
      expect(controller.repository.configured, isTrue);
    },
  );

  test(
    'requesting sync offline queues one request and game handoff requires reachability',
    () async {
      link.state = const WatchLinkState(
        activated: true,
        reachable: false,
        counterpartInstalled: true,
        counterpartPaired: true,
      );
      await controller.initialize();
      expect(await controller.requestSync(), isTrue);
      expect(await controller.requestSync(), isTrue);
      expect(link.queued.length, 1);
      expect(await controller.openOnPhone('game'), isFalse);
      link.stateChanges.add(
        const WatchLinkState(
          activated: true,
          reachable: true,
          counterpartInstalled: true,
          counterpartPaired: true,
        ),
      );
      expect(await controller.openOnPhone('game'), isTrue);
      expect(
        link.sent
            .where((p) => p['kind'] == 'chessever.open-game.v1')
            .single['gameId'],
        'game',
      );
    },
  );
}
