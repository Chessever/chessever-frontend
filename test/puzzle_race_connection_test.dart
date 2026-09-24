import 'dart:async';

import 'package:chessever2/screens/feed/race/race_client.dart';
import 'package:chessever2/screens/feed/race/race_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

import 'puzzle_race_fakes.dart';

/// Lets zero-length timers and socket events run.
Future<void> settle() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Waits real time, then lets what it triggered run.
Future<void> wait(int ms) async {
  await Future<void>.delayed(Duration(milliseconds: ms));
  await settle();
}

/// A socket whose room answers every heartbeat the way the runtime does.
class _AnsweringSocket extends FakeRaceSocket {
  @override
  void send(String frame) {
    super.send(frame);
    if (frame == RaceClientMessage.heartbeat) {
      scheduleMicrotask(() => push({'type': 'pong'}));
    }
  }
}

class _Link {
  _Link({
    Duration pingInterval = const Duration(hours: 1),
    Duration replyTimeout = RaceConnection.defaultReplyTimeout,
    int maxAttempts = 3,
    this.answering = false,
  }) {
    connection = RaceConnection(
      uri: Uri.parse('wss://race.test/v1/races/7KQ2MX/ws'),
      headers: () async => {'Authorization': 'Bearer ${token()}'},
      connector: _connect,
      onEvent: events.add,
      pingInterval: pingInterval,
      replyTimeout: replyTimeout,
      backoff: const [Duration.zero],
      maxAttempts: maxAttempts,
    );
  }

  final bool answering;
  final List<RaceLinkEvent> events = [];
  final List<FakeRaceSocket> sockets = [];
  final List<Map<String, String>> headers = [];
  final List<RaceApiException> failures = [];
  late final RaceConnection connection;
  int _tokens = 0;

  String token() => 'jwt${_tokens++}';

  Future<RaceSocket> _connect(Uri uri, Map<String, String> headers) async {
    this.headers.add(headers);
    if (failures.isNotEmpty) throw failures.removeAt(0);
    final socket = answering ? _AnsweringSocket() : FakeRaceSocket();
    sockets.add(socket);
    return socket;
  }

  Iterable<RaceLinkOpened> get opens => events.whereType<RaceLinkOpened>();
  RaceLinkClosed? get closed => events.whereType<RaceLinkClosed>().firstOrNull;
}

void main() {
  group('liveness', () {
    test('an answered heartbeat keeps the link', () async {
      final link = _Link(
        pingInterval: const Duration(milliseconds: 15),
        answering: true,
      );
      addTearDown(link.connection.close);
      await link.connection.open();
      await wait(150);
      expect(link.sockets, hasLength(1));
      expect(
        link.sockets.single.sent.where((f) => f == RaceClientMessage.heartbeat),
        isNotEmpty,
      );
      expect(link.connection.isOpen, isTrue);
    });

    test('a heartbeat left unanswered drops the socket and resumes', () async {
      final link = _Link(pingInterval: const Duration(milliseconds: 15));
      addTearDown(link.connection.close);
      await link.connection.open();
      final first = link.sockets.single;
      // Half-open: frames go out, nothing ever comes back.
      await wait(150);
      expect(first.sent, contains(RaceClientMessage.heartbeat));
      expect(first.closedByApp, isTrue);
      expect(first.closeCode, RaceConnection.silentCloseCode);
      expect(link.sockets.length, greaterThanOrEqualTo(2));
      expect(link.events.whereType<RaceLinkReconnecting>(), isNotEmpty);
      expect(link.opens.skip(1).first.resumed, isTrue);
      expect(link.closed, isNull);
    });

    test('a move with no frame back is not left holding the board', () async {
      final link = _Link(replyTimeout: const Duration(milliseconds: 30));
      addTearDown(link.connection.close);
      await link.connection.open();
      final first = link.sockets.single;
      expect(
        link.connection.send('{"type":"move"}', expectReply: true),
        isTrue,
      );
      await wait(120);
      expect(first.closeCode, RaceConnection.silentCloseCode);
      expect(link.sockets, hasLength(2));
      expect(link.opens.last.resumed, isTrue);
    });

    test(
      'any frame back answers the move; plain sends set no deadline',
      () async {
        final link = _Link(replyTimeout: const Duration(milliseconds: 30));
        addTearDown(link.connection.close);
        await link.connection.open();
        final socket = link.sockets.single;
        link.connection.send('{"type":"move"}', expectReply: true);
        socket.push({'type': 'pong'});
        link.connection.send('{"type":"ready","ready":true}');
        await wait(120);
        expect(link.sockets, hasLength(1));
        expect(socket.closedByApp, isFalse);
        expect(link.connection.isOpen, isTrue);
      },
    );

    test('the dropped socket\'s late end changes nothing', () async {
      final link = _Link(replyTimeout: const Duration(milliseconds: 20));
      addTearDown(link.connection.close);
      await link.connection.open();
      final first = link.sockets.single;
      link.connection.send('{"type":"move"}', expectReply: true);
      await wait(80);
      expect(link.sockets, hasLength(2));
      await first.drop(1000);
      await settle();
      expect(link.closed, isNull);
      expect(link.connection.isOpen, isTrue);
    });
  });

  group('401 on a resumed link', () {
    test('is tried again with a fresh token', () async {
      final link = _Link();
      addTearDown(link.connection.close);
      await link.connection.open();
      link.failures.addAll(const [
        RaceApiException('authentication_required', statusCode: 401),
        RaceApiException('authentication_required', statusCode: 401),
      ]);
      await link.sockets.single.drop(1006);
      await settle();
      expect(link.headers.map((h) => h['Authorization']), [
        'Bearer jwt0',
        'Bearer jwt1',
        'Bearer jwt2',
        'Bearer jwt3',
      ]);
      expect(link.sockets, hasLength(2));
      expect(link.opens.last.resumed, isTrue);
      expect(link.closed, isNull);
    });

    test('ends the link once the retries are spent', () async {
      final link = _Link(maxAttempts: 7);
      addTearDown(link.connection.close);
      await link.connection.open();
      link.failures.addAll(const [
        RaceApiException('authentication_required', statusCode: 401),
        RaceApiException('authentication_required', statusCode: 401),
        RaceApiException('authentication_required', statusCode: 401),
      ]);
      await link.sockets.single.drop(1006);
      await settle();
      expect(link.headers, hasLength(4));
      expect(link.closed!.error!.statusCode, 401);
    });

    test('the first upgrade\'s 401 stays final', () async {
      final link = _Link();
      addTearDown(link.connection.close);
      link.failures.add(
        const RaceApiException('authentication_required', statusCode: 401),
      );
      await link.connection.open();
      await settle();
      expect(link.headers, hasLength(1));
      expect(link.closed!.error!.code, 'authentication_required');
    });
  });

  group('raceFreshToken', () {
    const nowMs = 1790000000000;
    int nowSec(int offset) => nowMs ~/ 1000 + offset;

    test('a token with time left goes as it is', () async {
      final token = await raceFreshToken(
        read: () => (token: 'a', expiresAt: nowSec(600)),
        changes: const Stream.empty(),
        nowMs: () => nowMs,
      );
      expect(token, 'a');
    });

    test('near expiry: waits for the refresh, not a replayed event', () async {
      var session = (token: 'old', expiresAt: nowSec(10));
      final changes = StreamController<Object?>();
      addTearDown(changes.close);
      final result = raceFreshToken(
        read: () => session,
        changes: changes.stream,
        nowMs: () => nowMs,
      );
      await settle();
      // An older event replayed on listen: the session is still stale.
      changes.add('tokenRefreshed');
      await settle();
      session = (token: 'new', expiresAt: nowSec(3600));
      changes.add('tokenRefreshed');
      expect(await result, 'new');
    });

    test('no refresh in time: the current token still goes', () async {
      final silent = StreamController<Object?>();
      addTearDown(silent.close);
      final token = await raceFreshToken(
        read: () => (token: 'old', expiresAt: nowSec(-5)),
        changes: silent.stream,
        nowMs: () => nowMs,
        wait: const Duration(milliseconds: 20),
      );
      expect(token, 'old');
    });

    test('signed out: no token', () async {
      expect(
        await raceFreshToken(
          read: () => null,
          changes: const Stream.empty(),
          nowMs: () => nowMs,
        ),
        isNull,
      );
    });
  });
}
