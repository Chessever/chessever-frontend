import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chessever2/screens/feed/race/race_protocol.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Networking for Puzzle Race: `POST /v1/races` to open a room and one
/// WebSocket per room (`GET /v1/races/{code}/ws`).
///
/// The socket is `dart:io`'s, because the room reads its credential from an
/// upgrade header (`Authorization: Bearer …` or `X-Race-Seat: …`), which a
/// browser-style socket cannot set.

/// Something went wrong reaching a room. [code] is the Worker's own error
/// code where there is one (`room_not_found`, `room_full`, …), or one of
/// `network`, `not_configured`, `bad_response`, `connection_lost`, `replaced`.
class RaceApiException implements Exception {
  const RaceApiException(this.code, {this.statusCode, this.retryAfter});

  final String code;
  final int? statusCode;
  final Duration? retryAfter;

  @override
  String toString() => 'RaceApiException($code, ${statusCode ?? '-'})';
}

/// Opens rooms. Overridden in tests.
abstract interface class RaceApi {
  /// False when no service URL is configured: nothing is ever sent then.
  bool get isConfigured;

  /// Creates a room. [token] is the Supabase access token of a signed-in
  /// user; without one the room is a guest's and the answer carries a seat.
  /// [minRating] is where the ladder starts; [maxRating], when given, caps
  /// it. The app sends only the start so a race climbs freely; the ceiling
  /// stays for older callers. Omitted, the room starts where it always did.
  Future<RaceCreated> create({
    required RaceMode mode,
    required bool multiplayer,
    String? token,
    int? minRating,
    int? maxRating,
  });

  /// The socket address of room [code].
  Uri socketUri(String code);

  /// Room [code]'s standings (`GET /v1/races/{code}/results`), for a run
  /// whose socket ended before the room's `finished` reached this device.
  /// Throws a [RaceApiException] when the room cannot be read.
  Future<RaceRoomSummary> results(String code);

  /// The signed-in player's kept flames and bests (`GET /v1/me/stats`).
  /// Null when the service keeps none for this token or does not know the
  /// route yet (an older Worker); throws a [RaceApiException] when it
  /// cannot be reached.
  Future<RaceServerStats?> myStats(String token);
}

class RaceHttpApi implements RaceApi {
  RaceHttpApi({required String baseUrl, http.Client? client})
    : _base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), ''),
      _http = client ?? http.Client(),
      _ownsHttp = client == null;

  static const String racesPath = '/v1/races';
  static const Duration requestTimeout = Duration(seconds: 12);

  final String _base;
  final http.Client _http;
  final bool _ownsHttp;

  @override
  bool get isConfigured => _base.isNotEmpty;

  @override
  Future<RaceCreated> create({
    required RaceMode mode,
    required bool multiplayer,
    String? token,
    int? minRating,
    int? maxRating,
  }) async {
    if (!isConfigured) throw const RaceApiException('not_configured');
    final http.Response response;
    try {
      response = await _http
          .post(
            Uri.parse('$_base$racesPath'),
            headers: {
              'content-type': 'application/json',
              'accept': 'application/json',
              if (token != null && token.isNotEmpty)
                'authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'mode': mode.wire,
              'multiplayer': multiplayer,
              'minRating': ?minRating,
              'maxRating': ?maxRating,
            }),
          )
          .timeout(requestTimeout);
    } on TimeoutException {
      throw const RaceApiException('network');
    } catch (error) {
      debugPrint('[Race] create failed: ${error.runtimeType}');
      throw const RaceApiException('network');
    }

    Map<String, Object?>? body;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) body = decoded.cast<String, Object?>();
    } catch (_) {
      body = null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final retry = int.tryParse(response.headers['retry-after'] ?? '');
      throw RaceApiException(
        (body?['error'] as String?) ?? 'http_${response.statusCode}',
        statusCode: response.statusCode,
        retryAfter: retry == null ? null : Duration(seconds: retry),
      );
    }
    final created = body == null ? null : RaceCreated.fromJson(body);
    if (created == null) throw const RaceApiException('bad_response');
    return created;
  }

  @override
  Future<RaceRoomSummary> results(String code) async {
    if (!isConfigured) throw const RaceApiException('not_configured');
    final http.Response response;
    try {
      response = await _http
          .get(
            Uri.parse('$_base$racesPath/$code/results'),
            headers: const {'accept': 'application/json'},
          )
          .timeout(requestTimeout);
    } on TimeoutException {
      throw const RaceApiException('network');
    } catch (error) {
      debugPrint('[Race] results failed: ${error.runtimeType}');
      throw const RaceApiException('network');
    }

    Map<String, Object?>? body;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) body = decoded.cast<String, Object?>();
    } catch (_) {
      body = null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RaceApiException(
        (body?['error'] as String?) ?? 'http_${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    if (body == null) throw const RaceApiException('bad_response');
    return RaceRoomSummary.fromJson(body);
  }

  @override
  Future<RaceServerStats?> myStats(String token) async {
    if (!isConfigured) throw const RaceApiException('not_configured');
    final http.Response response;
    try {
      response = await _http
          .get(
            Uri.parse('$_base/v1/me/stats'),
            headers: {
              'accept': 'application/json',
              'authorization': 'Bearer $token',
            },
          )
          .timeout(requestTimeout);
    } on TimeoutException {
      throw const RaceApiException('network');
    } catch (error) {
      debugPrint('[Race] stats failed: ${error.runtimeType}');
      throw const RaceApiException('network');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        return RaceServerStats.fromJson(decoded.cast<String, Object?>());
      }
    } catch (_) {
      // Unreadable: nothing kept to show.
    }
    return null;
  }

  @override
  Uri socketUri(String code) {
    final base = Uri.parse(_base);
    return base.replace(
      scheme: base.scheme == 'http' ? 'ws' : 'wss',
      path: '${base.path}$racesPath/$code/ws',
    );
  }

  void close() {
    if (_ownsHttp) _http.close();
  }
}

/// A signed-in session's access token, and when it expires in epoch seconds
/// (null when unknown).
typedef RaceSessionToken = ({String token, int? expiresAt});

/// The access token to send now: [read]'s own while it has more than
/// [margin] to live. Closer to expiry than that, waits up to [wait] for the
/// auth SDK's refresh to land (checked on each [changes] event, so a
/// replayed older event is not taken for it), then sends whatever is current
/// then; a room that still refuses it answers 401, which [RaceConnection]
/// retries on a link that was open. Null when signed out.
///
/// Never refreshes by itself: the SDK owns refresh, and a second refresh
/// racing it can replay an already-rotated refresh token, which revokes the
/// whole session (the resume note in `main.dart`).
Future<String?> raceFreshToken({
  required RaceSessionToken? Function() read,
  required Stream<Object?> changes,
  int Function()? nowMs,
  Duration margin = const Duration(seconds: 30),
  Duration wait = const Duration(seconds: 4),
}) async {
  final now = nowMs ?? () => DateTime.now().millisecondsSinceEpoch;
  RaceSessionToken? current() {
    try {
      return read();
    } catch (_) {
      return null;
    }
  }

  bool usable(RaceSessionToken? session) {
    final expiresAt = session?.expiresAt;
    return expiresAt == null ||
        expiresAt * 1000 > now() + margin.inMilliseconds;
  }

  final session = current();
  if (usable(session)) return session?.token;

  final landed = Completer<void>();
  void check() {
    if (!landed.isCompleted && usable(current())) landed.complete();
  }

  StreamSubscription<Object?>? subscription;
  try {
    subscription = changes.listen(
      (_) => check(),
      onError: (Object _) {},
      onDone: () {
        if (!landed.isCompleted) landed.complete();
      },
    );
    // A refresh that landed between the first read and the listen.
    check();
    await landed.future.timeout(wait, onTimeout: () {});
  } catch (_) {
    // Nothing to wait on; the current token is all there is.
  } finally {
    unawaited(subscription?.cancel());
  }
  return current()?.token;
}

/// One open socket to a room. [frames] ends when the socket closes; then
/// [closeCode] and [closeReason] say why.
abstract interface class RaceSocket {
  Stream<String> get frames;
  void send(String frame);
  Future<void> close([int code, String? reason]);
  int? get closeCode;
  String? get closeReason;
}

/// Opens a [RaceSocket] with upgrade [headers]. Throws a
/// [RaceApiException] (with the HTTP status of a refused upgrade) on failure.
typedef RaceSocketConnector =
    Future<RaceSocket> Function(Uri uri, Map<String, String> headers);

/// The production connector: `dart:io`'s [WebSocket] with headers.
Future<RaceSocket> connectRaceSocket(
  Uri uri,
  Map<String, String> headers,
) async {
  Future<WebSocket>? connecting;
  try {
    connecting = WebSocket.connect(uri.toString(), headers: headers);
    final socket = await connecting.timeout(const Duration(seconds: 12));
    return _IoRaceSocket(socket);
  } on WebSocketException catch (error) {
    final status = error.httpStatusCode;
    throw RaceApiException(raceUpgradeRefusalCode(status), statusCode: status);
  } on TimeoutException {
    // The upgrade keeps going after the timeout. A socket that lands late
    // is closed at once, so it never lingers unread as one of this
    // player's sockets in the room.
    unawaited(
      connecting?.then(
        (straggler) =>
            straggler.close(1000, 'timeout').catchError((Object _) {}),
        onError: (Object _) {},
      ),
    );
    throw const RaceApiException('network');
  } catch (error) {
    debugPrint('[Race] socket connect failed: ${error.runtimeType}');
    throw const RaceApiException('network');
  }
}

/// What a refused upgrade's HTTP status means (README: "Upgrade refusals").
@visibleForTesting
String raceUpgradeRefusalCode(int? status) => switch (status) {
  401 => 'authentication_required',
  403 => 'forbidden',
  404 => 'room_not_found',
  409 => 'room_closed',
  410 => 'race_finished',
  429 => 'rate_limited',
  null => 'network',
  _ => 'http_$status',
};

class _IoRaceSocket implements RaceSocket {
  _IoRaceSocket(this._socket)
    : frames = _socket
          .where((event) => event is String)
          .cast<String>()
          .asBroadcastStream();

  final WebSocket _socket;

  @override
  final Stream<String> frames;

  @override
  void send(String frame) {
    if (_socket.readyState == WebSocket.open) _socket.add(frame);
  }

  @override
  Future<void> close([int code = 1000, String? reason]) =>
      _socket.close(code, reason);

  @override
  int? get closeCode => _socket.closeCode;

  @override
  String? get closeReason => _socket.closeReason;
}

/// How a [RaceConnection] is doing.
enum RaceLinkStatus { connecting, open, reconnecting, closed }

/// What a [RaceConnection] reports.
sealed class RaceLinkEvent {
  const RaceLinkEvent();
}

/// The socket is (again) open. [resumed] is true after a reconnect.
class RaceLinkOpened extends RaceLinkEvent {
  const RaceLinkOpened({required this.resumed});

  final bool resumed;
}

/// Lost the socket; trying again after a back-off.
class RaceLinkReconnecting extends RaceLinkEvent {
  const RaceLinkReconnecting(this.attempt);

  final int attempt;
}

class RaceLinkMessage extends RaceLinkEvent {
  const RaceLinkMessage(this.message);

  final RaceServerMessage message;
}

/// The link is over for good: [error] is null for a clean end (the race
/// finished, or the app closed it).
class RaceLinkClosed extends RaceLinkEvent {
  const RaceLinkClosed({this.error});

  final RaceApiException? error;
}

/// One room's socket for as long as the race needs it.
///
/// * Sends the bare heartbeat every [pingInterval] while open, and checks
///   that something comes back. A socket can go half-open (a Wi-Fi to
///   cellular handoff, a stalled NAT) and still read as open for many
///   minutes, until the OS gives up on the TCP connection. So a heartbeat
///   left without a single frame for a whole interval, or a frame sent with
///   `expectReply` left without one for [replyTimeout], drops the socket and
///   reconnects.
/// * Reconnects after an unexpected close or a network failure, with the
///   [backoff] steps (the last one repeats) for up to [maxAttempts] tries,
///   asking [headers] again each time so a refreshed token is used. The room
///   resumes the seat, so the caller only has to send `join` again on
///   [RaceLinkOpened].
/// * Does not reconnect when the room closed on purpose (1000: finished or
///   expired), when another connection replaced this one (4001), or when the
///   upgrade was refused for a reason that will not change (401, 403, 404,
///   409, 410). A 401 on a link that was already open is the exception: it
///   is tried again up to [maxAuthRetries] times, because there it means the
///   credential aged (see [_mayRetryAuth]), not that the player may not race.
class RaceConnection {
  RaceConnection({
    required this.uri,
    required this.headers,
    required this.connector,
    required this.onEvent,
    this.pingInterval = const Duration(seconds: 20),
    this.replyTimeout = defaultReplyTimeout,
    this.backoff = defaultBackoff,
    this.maxAttempts = 7,
    this.maxAuthRetries = 2,
  });

  static const List<Duration> defaultBackoff = [
    Duration(milliseconds: 400),
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
  ];

  /// How long a frame sent with `expectReply` (a move waiting for its
  /// verdict) may go without any frame back. The room answers a move at
  /// once, so this is a dead socket, not a slow judge.
  static const Duration defaultReplyTimeout = Duration(seconds: 5);

  /// The close code for a socket let go because it went silent. Any code in
  /// 4000-4999 may be sent; the room reads none of them.
  static const int silentCloseCode = 4000;

  final Uri uri;
  final Future<Map<String, String>> Function() headers;
  final RaceSocketConnector connector;
  final void Function(RaceLinkEvent event) onEvent;
  final Duration pingInterval;
  final Duration replyTimeout;
  final List<Duration> backoff;
  final int maxAttempts;
  final int maxAuthRetries;

  RaceSocket? _socket;
  StreamSubscription<String>? _frames;
  Timer? _ping;
  Timer? _replyDue;
  Timer? _retry;
  int _attempt = 0;
  int _authRetries = 0;
  bool _everOpened = false;
  bool _disposed = false;

  /// A heartbeat went out and no frame has come in since.
  bool _heartbeatUnanswered = false;
  RaceLinkStatus _status = RaceLinkStatus.connecting;

  RaceLinkStatus get status => _status;
  bool get isOpen => _status == RaceLinkStatus.open;

  /// Connects. Failures arrive as events, never as an error here.
  Future<void> open() => _connect();

  /// Sends [frame] when the socket is open; returns whether it went out.
  ///
  /// [expectReply] marks a frame the room always answers (a move, a stop):
  /// when no frame at all arrives within [replyTimeout], the socket is
  /// treated as dead and the link reconnects.
  bool send(String frame, {bool expectReply = false}) {
    final socket = _socket;
    if (socket == null || !isOpen) return false;
    try {
      socket.send(frame);
    } catch (error) {
      debugPrint('[Race] send failed: ${error.runtimeType}');
      return false;
    }
    if (expectReply) {
      // An earlier unanswered frame keeps its own, earlier deadline.
      _replyDue ??= Timer(replyTimeout, () {
        _replyDue = null;
        _dropSilent(socket);
      });
    }
    return true;
  }

  /// Closes for good; no event follows.
  Future<void> close() async {
    if (_disposed) return;
    _disposed = true;
    _status = RaceLinkStatus.closed;
    _retry?.cancel();
    _stopWatching();
    await _frames?.cancel();
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      try {
        await socket.close(1000, 'bye');
      } catch (_) {
        // Already closed.
      }
    }
  }

  Future<void> _connect() async {
    if (_disposed) return;
    _status = _everOpened
        ? RaceLinkStatus.reconnecting
        : RaceLinkStatus.connecting;
    final RaceSocket socket;
    try {
      socket = await connector(uri, await headers());
    } on RaceApiException catch (error) {
      if (_disposed) return;
      if (_mayRetryAuth(error)) {
        _authRetries += 1;
        _scheduleRetry(error);
      } else if (_isFinal(error)) {
        _end(error);
      } else {
        _scheduleRetry(error);
      }
      return;
    } catch (error) {
      if (_disposed) return;
      _scheduleRetry(const RaceApiException('network'));
      return;
    }
    if (_disposed) {
      unawaited(socket.close(1000, 'bye').catchError((Object _) {}));
      return;
    }
    _socket = socket;
    _attempt = 0;
    _authRetries = 0;
    final resumed = _everOpened;
    _everOpened = true;
    _status = RaceLinkStatus.open;
    _stopWatching();
    _frames = socket.frames.listen(
      _onFrame,
      onDone: () => _onClosed(socket),
      onError: (Object _) {},
      cancelOnError: false,
    );
    _ping = Timer.periodic(pingInterval, (_) => _heartbeat(socket));
    onEvent(RaceLinkOpened(resumed: resumed));
  }

  void _onFrame(String frame) {
    if (_disposed) return;
    // Any frame proves the socket alive, the runtime's bare `pong` included.
    _heartbeatUnanswered = false;
    _replyDue?.cancel();
    _replyDue = null;
    final message = RaceServerMessage.decode(frame);
    if (message == null) return;
    onEvent(RaceLinkMessage(message));
  }

  /// Every [pingInterval]: the heartbeat, unless the last one is still
  /// unanswered. The runtime answers a heartbeat in a round trip, so a whole
  /// interval without any frame means the socket is gone.
  void _heartbeat(RaceSocket socket) {
    if (_disposed || !identical(socket, _socket)) return;
    if (_heartbeatUnanswered) {
      _dropSilent(socket);
      return;
    }
    _heartbeatUnanswered = send(RaceClientMessage.heartbeat);
  }

  /// [socket] still reads open but nothing comes back through it. Lets it go
  /// without waiting for a close handshake that cannot arrive, then
  /// reconnects; the room resumes the seat.
  void _dropSilent(RaceSocket socket) {
    if (_disposed || !identical(socket, _socket)) return;
    debugPrint('[Race] link went silent; reconnecting');
    _stopWatching();
    // Cancelled first, so the socket's late end is not read as a close.
    unawaited(_frames?.cancel());
    _frames = null;
    _socket = null;
    try {
      unawaited(
        socket.close(silentCloseCode, 'silent').catchError((Object _) {}),
      );
    } catch (_) {
      // Already closed.
    }
    _scheduleRetry(const RaceApiException('connection_lost'));
  }

  void _stopWatching() {
    _ping?.cancel();
    _ping = null;
    _replyDue?.cancel();
    _replyDue = null;
    _heartbeatUnanswered = false;
  }

  void _onClosed(RaceSocket socket) {
    if (_disposed || !identical(socket, _socket)) return;
    _stopWatching();
    _socket = null;
    final code = socket.closeCode;
    if (code == 1000) {
      _end(null);
    } else if (code == 4001) {
      _end(const RaceApiException('replaced'));
    } else {
      _scheduleRetry(const RaceApiException('connection_lost'));
    }
  }

  bool _isFinal(RaceApiException error) => switch (error.statusCode) {
    401 || 403 || 404 || 409 || 410 => true,
    _ => false,
  };

  /// A 401 on a link that was open a moment ago says the credential aged,
  /// not that this player may not race: an access token that expired during
  /// a long run (Infinite can outlast its hour), one read before the auth
  /// SDK finished refreshing after a resume, or the verifier failing once to
  /// fetch its keys. [headers] reads the token again, so it is worth a retry.
  /// The first upgrade's 401 stays final: nothing was ever accepted there.
  bool _mayRetryAuth(RaceApiException error) =>
      error.statusCode == 401 && _everOpened && _authRetries < maxAuthRetries;

  void _scheduleRetry(RaceApiException cause) {
    if (_attempt >= maxAttempts) {
      _end(
        cause.code == 'network' || cause.code == 'connection_lost'
            ? const RaceApiException('connection_lost')
            : cause,
      );
      return;
    }
    final step = backoff.isEmpty
        ? Duration.zero
        : backoff[_attempt < backoff.length ? _attempt : backoff.length - 1];
    _attempt += 1;
    _status = RaceLinkStatus.reconnecting;
    onEvent(RaceLinkReconnecting(_attempt));
    _retry?.cancel();
    final wait = cause.retryAfter != null && cause.retryAfter! > step
        ? cause.retryAfter!
        : step;
    _retry = Timer(wait, () => unawaited(_connect()));
  }

  void _end(RaceApiException? error) {
    if (_disposed) return;
    _status = RaceLinkStatus.closed;
    _retry?.cancel();
    _stopWatching();
    unawaited(_frames?.cancel());
    _frames = null;
    _socket = null;
    onEvent(RaceLinkClosed(error: error));
  }
}
