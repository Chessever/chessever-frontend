import 'dart:async';
import 'dart:convert';

import 'package:chessever2/screens/feed/race/race_audio.dart';
import 'package:chessever2/screens/feed/race/race_client.dart';
import 'package:chessever2/screens/feed/race/race_controller.dart';
import 'package:chessever2/screens/feed/race/race_flames.dart';
import 'package:chessever2/screens/feed/race/race_stats_store.dart';

/// Test doubles for Puzzle Race: a scripted room behind fake sockets, a fake
/// service, auth, stats and a sound recorder. Messages are built in the
/// Worker's exact shapes (`apps/race/src/protocol.ts`).

class FakeRaceSocket implements RaceSocket {
  final StreamController<String> _frames = StreamController<String>();
  final List<String> sent = [];
  bool closedByApp = false;

  @override
  int? closeCode;

  @override
  String? closeReason;

  @override
  Stream<String> get frames => _frames.stream;

  @override
  void send(String frame) => sent.add(frame);

  @override
  Future<void> close([int code = 1000, String? reason]) async {
    closedByApp = true;
    closeCode ??= code;
    if (!_frames.isClosed) await _frames.close();
  }

  /// The room sends [message].
  void push(Map<String, Object?> message) {
    if (!_frames.isClosed) _frames.add(jsonEncode(message));
  }

  /// The room (or the network) closes the socket with [code].
  Future<void> drop([int? code]) async {
    closeCode = code;
    if (!_frames.isClosed) await _frames.close();
  }

  List<Map<String, Object?>> get sentJson => [
    for (final frame in sent)
      (jsonDecode(frame) as Map).cast<String, Object?>(),
  ];

  List<String> get sentTypes => [
    for (final m in sentJson) m['type']! as String,
  ];
}

/// Hands out a [FakeRaceSocket] per connect, or throws the next queued
/// failure.
class FakeRaceServer {
  final List<FakeRaceSocket> sockets = [];
  final List<({Uri uri, Map<String, String> headers})> connects = [];
  final List<RaceApiException> failures = [];

  Future<RaceSocket> connect(Uri uri, Map<String, String> headers) async {
    connects.add((uri: uri, headers: headers));
    if (failures.isNotEmpty) throw failures.removeAt(0);
    final socket = FakeRaceSocket();
    sockets.add(socket);
    return socket;
  }

  FakeRaceSocket get last => sockets.last;
}

class FakeRaceApi implements RaceApi {
  FakeRaceApi({this.isConfigured = true});

  @override
  bool isConfigured;

  final List<
    ({
      RaceMode mode,
      bool multiplayer,
      String? token,
      int? minRating,
      int? maxRating,
    })
  >
  creates = [];
  final List<RaceApiException> failures = [];
  String code = '7KQ2MX';

  @override
  Future<RaceCreated> create({
    required RaceMode mode,
    required bool multiplayer,
    String? token,
    int? minRating,
    int? maxRating,
  }) async {
    creates.add((
      mode: mode,
      multiplayer: multiplayer,
      token: token,
      minRating: minRating,
      maxRating: maxRating,
    ));
    if (failures.isNotEmpty) throw failures.removeAt(0);
    return RaceCreated(
      code: code,
      mode: mode,
      multiplayer: multiplayer,
      wsUrl: socketUri(code),
      seat: token == null ? 'AAAAAAAAAAAAAAAAAAAAAA' : null,
    );
  }

  @override
  Uri socketUri(String code) => Uri.parse('wss://race.test/v1/races/$code/ws');

  /// What `GET /v1/races/{code}/results` answers; null answers 404.
  RaceRoomSummary? summary;
  final List<String> resultsRequests = [];

  @override
  Future<RaceRoomSummary> results(String code) async {
    resultsRequests.add(code);
    final answer = summary;
    if (answer == null) {
      throw const RaceApiException('room_not_found', statusCode: 404);
    }
    return answer;
  }

  /// What `GET /v1/me/stats` answers; null keeps nothing.
  RaceServerStats? stats;
  final List<String> statsTokens = [];

  @override
  Future<RaceServerStats?> myStats(String token) async {
    statsTokens.add(token);
    return stats;
  }
}

/// A fixed answer for the kept flames, and how often it was asked.
class FakeRaceServerStatsSource implements RaceServerStatsSource {
  FakeRaceServerStatsSource([this.stats]);

  RaceServerStats? stats;
  int reads = 0;

  @override
  Future<RaceServerStats?> read() async {
    reads += 1;
    return stats;
  }
}

class FakeRaceAuth implements RaceAuth {
  FakeRaceAuth({this.accessToken, this.displayName});

  @override
  String? accessToken;

  @override
  String? displayName;

  @override
  bool get signedIn => accessToken != null;
}

/// A [RaceAuth] whose SDK hands out a refreshed token when asked for a fresh
/// one; [fresh] lists what each ask returns, then the last one repeats.
class FakeRefreshingRaceAuth extends FakeRaceAuth
    implements RaceRefreshingAuth {
  FakeRefreshingRaceAuth({
    super.accessToken,
    super.displayName,
    required this.fresh,
  });

  final List<String?> fresh;
  int asks = 0;

  @override
  Future<String?> freshAccessToken() async {
    final i = asks++;
    return fresh[i < fresh.length ? i : fresh.length - 1];
  }
}

class MemoryRaceStats implements RaceStatsStore {
  RaceBests bests = RaceBests.empty;
  final List<({RaceMode mode, int score, int bestStreak, int flames})>
  recorded = [];

  @override
  Future<RaceBests> read() async => bests;

  @override
  Future<RaceRecordOutcome> record({
    required RaceMode mode,
    required int score,
    required int bestStreak,
    int flames = 0,
  }) async {
    recorded.add((
      mode: mode,
      score: score,
      bestStreak: bestStreak,
      flames: flames,
    ));
    final before = bests;
    bests = before.withRace(
      mode: mode,
      score: score,
      streak: bestStreak,
      flames: flames,
    );
    return RaceRecordOutcome(
      before: before,
      after: bests,
      newBest: score > 0 && score > before.bestFor(mode),
    );
  }
}

class RecordingRaceAudio implements RaceAudio {
  final List<String> calls = [];

  @override
  void warmUp() => calls.add('warmUp');

  @override
  void countdownBeat(int n) => calls.add('beat$n');

  @override
  void go() => calls.add('go');

  @override
  void correct({int streak = 0}) => calls.add('correct$streak');

  @override
  void wrong() => calls.add('wrong');

  @override
  void levelUp() => calls.add('levelUp');

  @override
  void setTension(double intensity) =>
      calls.add('tension${intensity.toStringAsFixed(2)}');

  @override
  void lastLife() => calls.add('lastLife');

  @override
  void finish({bool newBest = false}) =>
      calls.add(newBest ? 'finishBest' : 'finish');

  @override
  void stopAll() => calls.add('stopAll');

  @override
  void move(String san) => calls.add('move:$san');
}

/// Everything a test needs, wired into [RaceDeps].
class RaceHarness {
  RaceHarness({
    bool configured = true,
    String? token,
    String? name = 'Magnus',
    FakeRaceAuth? auth,
  }) : api = FakeRaceApi(isConfigured: configured),
       auth = auth ?? FakeRaceAuth(accessToken: token, displayName: name);

  final FakeRaceApi api;
  final FakeRaceAuth auth;
  final FakeRaceServer server = FakeRaceServer();
  final MemoryRaceStats stats = MemoryRaceStats();
  final RecordingRaceAudio audio = RecordingRaceAudio();

  /// This device's clock; tests move it by hand.
  int clock = 1790000000000;

  /// [RaceDeps] over the fakes; [audio] replaces the recorder (a test that
  /// drives the real `raceAudioProvider`).
  RaceDeps deps({
    Duration soloCountdown = Duration.zero,
    List<Duration> backoff = const [Duration.zero],
    int maxReconnectAttempts = 3,
    RaceAudio? audio,
    Duration replyTimeout = RaceConnection.defaultReplyTimeout,
  }) => RaceDeps(
    api: api,
    connector: server.connect,
    auth: auth,
    stats: stats,
    audio: audio ?? this.audio,
    now: () => clock,
    pingInterval: const Duration(hours: 1),
    replyTimeout: replyTimeout,
    backoff: backoff,
    maxReconnectAttempts: maxReconnectAttempts,
    soloCountdown: soloCountdown,
    sourceRetryDelay: Duration.zero,
  );
}

// ------------------------------------------------------------- messages

const String kYou = '3f9c01ab22de';
const String kRival = '77aa01bc99ef';

/// A back-rank mate in one, before the setup move: Black plays Kh8 (g8h8),
/// then White mates with Ra8# (a1a8; Rb8# mates too).
const String kBackRankFen = '6k1/6pp/8/8/8/8/8/RR4K1 b - - 0 1';

Map<String, Object?> snapshot({
  String state = 'lobby',
  String mode = 'survival',
  bool multiplayer = false,
  String? you = kYou,
  String hostId = kYou,
  List<Map<String, Object?>>? players,
  int? countdownEndsAt,
  int? startedAt,
  int serverNow = 1790000000000,
  int? startRating,
  int? maxRating,
}) => {
  'type': 'snapshot',
  'serverNow': serverNow,
  'code': '7KQ2MX',
  'mode': mode,
  'multiplayer': multiplayer,
  'state': state,
  'you': you,
  'hostId': hostId,
  'lives': mode == 'survival' ? 3 : null,
  'countdownEndsAt': countdownEndsAt,
  'startedAt': startedAt,
  'players': players ?? [player()],
  'startRating': ?startRating,
  'maxRating': ?maxRating,
};

Map<String, Object?> player({
  String id = kYou,
  String name = 'Magnus',
  int score = 0,
  int mistakes = 0,
  int level = 0,
  bool finished = false,
  bool ready = false,
  bool connected = true,
}) => {
  'id': id,
  'name': name,
  'score': score,
  'mistakes': mistakes,
  'level': level,
  'finished': finished,
  'ready': ready,
  'connected': connected,
};

Map<String, Object?> puzzle({
  int index = 0,
  String fen = kBackRankFen,
  String sideToMove = 'white',
  String setupMove = 'g8h8',
  int rating = 812,
  int level = 0,
  int ply = 1,
  List<String> progress = const [],
}) => {
  'type': 'puzzle',
  'index': index,
  'fen': fen,
  'sideToMove': sideToMove,
  'setupMove': setupMove,
  'rating': rating,
  'level': level,
  'ply': ply,
  'progress': progress,
};

Map<String, Object?> verdict({
  int index = 0,
  bool correct = true,
  bool complete = true,
  String? expectedReply,
  int? nextPly,
  List<String>? solutionRevealed,
  int score = 1,
  int mistakes = 0,
  int level = 1,
  int elapsedMs = 5000,
  int serverNow = 1790000005000,
}) => {
  'type': 'verdict',
  'index': index,
  'correct': correct,
  'complete': complete,
  'expectedReply': ?expectedReply,
  'nextPly': ?nextPly,
  if (complete) 'solutionRevealed': solutionRevealed ?? ['a1a8'],
  if (complete) 'puzzleId': 4211 + index,
  if (complete) 'themes': ['mateIn1', 'backRankMate'],
  'score': score,
  'mistakes': mistakes,
  'level': level,
  'elapsedMs': elapsedMs,
  'serverNow': serverNow,
};

Map<String, Object?> finished({
  String? playerId,
  String? reason,
  bool roomFinished = true,
  List<Map<String, Object?>>? results,
  int serverNow = 1790000060000,
}) => {
  'type': 'finished',
  'playerId': playerId,
  'reason': reason,
  'roomFinished': roomFinished,
  'results':
      results ??
      [result(score: 1, mistakes: 3, finishReason: 'lives', elapsedMs: 60000)],
  'serverNow': serverNow,
};

/// `GET /v1/races/{code}/results`, as the Worker's `RoomSummary`.
Map<String, Object?> roomSummary({
  String state = 'finished',
  String mode = 'survival',
  bool multiplayer = false,
  int? startedAt = 1790000000000,
  int? finishedAt,
  List<Map<String, Object?>>? results,
}) => {
  'code': '7KQ2MX',
  'mode': mode,
  'multiplayer': multiplayer,
  'state': state,
  'createdAt': 1789999990000,
  'startedAt': startedAt,
  'finishedAt': finishedAt,
  'results': results ?? [result()],
};

Map<String, Object?> result({
  int rank = 1,
  String id = kYou,
  String name = 'Magnus',
  int score = 0,
  int mistakes = 0,
  int level = 0,
  int bestRating = 0,
  int elapsedMs = 0,
  bool finished = true,
  String? finishReason,
  int? flames,
}) => {
  'rank': rank,
  'id': id,
  'name': name,
  'score': score,
  'mistakes': mistakes,
  'level': level,
  'bestRating': bestRating,
  'elapsedMs': elapsedMs,
  'finished': finished,
  'finishReason': finishReason,
  'flames': ?flames,
};
