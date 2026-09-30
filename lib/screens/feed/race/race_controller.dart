import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/config/puzzle_service_config.dart';
import 'package:chessever2/screens/feed/race/race_audio.dart';
import 'package:chessever2/screens/feed/race/puzzle_rating_range.dart';
import 'package:chessever2/screens/feed/race/race_client.dart';
import 'package:chessever2/screens/feed/race/race_flames.dart';
import 'package:chessever2/screens/feed/race/race_protocol.dart';
import 'package:chessever2/screens/feed/race/race_stats_store.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

export 'package:chessever2/screens/feed/race/race_client.dart'
    show RaceLinkStatus;
export 'package:chessever2/screens/feed/race/race_protocol.dart';

/// Solves per displayed level. The room's own `level` is the number of
/// solves (each one climbs ~40 rating points); the race shows a level every
/// [kRaceSolvesPerLevel] solves so a level-up is an event, not every move.
const int kRaceSolvesPerLevel = 3;

/// How soon after a complete verdict the room's `finished` counts as the
/// verdict's own (the room sends the two back to back).
const Duration kRaceVerdictFinishWindow = Duration(seconds: 1);

/// The level the race shows for [solves].
int raceDisplayLevel(int solves) =>
    1 + math.max(0, solves) ~/ kRaceSolvesPerLevel;

/// How tense the race feels, 0..1: it rises with the level and, in Survival,
/// with every life lost.
double raceTension({
  required int solves,
  required RaceMode mode,
  required int? livesLeft,
}) {
  final level = ((raceDisplayLevel(solves) - 1) / 12).clamp(0.0, 1.0);
  final lives = mode == RaceMode.survival && livesLeft != null
      ? switch (livesLeft) {
          >= 3 => 0.0,
          2 => 0.5,
          _ => 1.0,
        }
      : 0.0;
  final raw = level * 0.7 + lives * 0.3;
  // Coarse steps, so the sound only hears real changes.
  return ((raw * 20).round() / 20).clamp(0.0, 1.0);
}

/// Where the race flow is.
enum RacePhase {
  /// Choosing a mode.
  setup,

  /// Asking the service for a room.
  creating,

  /// Opening the room's socket.
  connecting,

  /// In a room that has not started (a solo room starts on its own).
  lobby,

  /// 3, 2, 1.
  countdown,
  running,
  finished,

  /// Could not get into (or back into) a race; [RaceState.errorCode] says why.
  failed,
}

/// The puzzle on the board. Holds no solution: the room keeps it.
@immutable
class RacePuzzle {
  const RacePuzzle({
    required this.index,
    required this.fen,
    required this.solver,
    required this.setupMove,
    required this.rating,
    required this.level,
    required this.ply,
    required this.progress,
    required this.revision,
  });

  factory RacePuzzle.fromMessage(RacePuzzleMessage m, {int revision = 0}) =>
      RacePuzzle(
        index: m.index,
        fen: m.fen,
        solver: m.sideToMove == 'black' ? Side.black : Side.white,
        setupMove: m.setupMove,
        rating: m.rating,
        level: m.level,
        ply: m.ply,
        progress: List.unmodifiable(m.progress),
        revision: revision,
      );

  final int index;

  /// Before the opponent's setup move.
  final String fen;
  final Side solver;
  final String setupMove;
  final int rating;
  final int level;

  /// The ply the room expects next when this message arrived.
  final int ply;

  /// Moves of this puzzle already on the board (a resume).
  final List<String> progress;

  /// Bumped when the room re-sends this puzzle in a different state (after
  /// a reconnect), so the board rebuilds from [ply] and [progress].
  final int revision;
}

/// One finished puzzle, for the stream and the results.
@immutable
class RacePuzzleRecord {
  const RacePuzzleRecord({
    required this.puzzle,
    required this.solved,
    required this.solution,
    required this.finalLine,
    required this.timeMs,
    this.puzzleId,
    this.themes = const [],
  });

  final RacePuzzle puzzle;
  final bool solved;

  /// Every move after the setup move, as the room revealed it.
  final List<String> solution;

  /// The moves after the setup move that ended on the board: the whole
  /// solution when solved, else the right moves then the wrong one.
  final List<String> finalLine;

  /// Server time spent on this puzzle.
  final int timeMs;
  final int? puzzleId;
  final List<String> themes;
}

/// The room's answer to one of the player's moves, for the board.
@immutable
class RaceMoveEvent {
  const RaceMoveEvent({
    required this.seq,
    required this.index,
    required this.uci,
    required this.correct,
    required this.complete,
    this.reply,
  });

  final int seq;
  final int index;

  /// The move the player sent (null if it was sent before a reconnect).
  final String? uci;
  final bool correct;
  final bool complete;

  /// The opponent's next move, when the line goes on.
  final String? reply;
}

/// A move the room refused without judging it (illegal, stale, too fast):
/// the board takes it back.
@immutable
class RaceRejectEvent {
  const RaceRejectEvent({required this.seq, required this.index});

  final int seq;
  final int index;
}

/// A calm, transient message for the player ([code] maps to copy).
@immutable
class RaceNotice {
  const RaceNotice(this.code, this.seq);

  final String code;
  final int seq;
}

@immutable
class _PendingMove {
  const _PendingMove({
    required this.index,
    required this.ply,
    required this.uci,
    this.epoch = 0,
  });

  final int index;
  final int ply;
  final String uci;

  /// Which opening of the link the move went out on. A move from an
  /// earlier socket may never have reached the room; one sent on the
  /// current socket is still on its way to a verdict.
  final int epoch;
}

@immutable
class RaceState {
  const RaceState({
    this.phase = RacePhase.setup,
    this.mode = RaceMode.survival,
    this.multiplayer = false,
    this.code,
    this.you,
    this.hostId,
    this.players = const [],
    this.startLives,
    this.score = 0,
    this.mistakes = 0,
    this.level = 0,
    this.streak = 0,
    this.bestStreak = 0,
    this.puzzle,
    this.ply = 1,
    this.awaitingVerdict = false,
    this.records = const [],
    this.lastMove,
    this.lastReject,
    this.startedAt,
    this.countdownEndsAt,
    this.clockOffsetMs = 0,
    this.lastElapsedMs,
    this.finalElapsedMs,
    this.finishReason,
    this.roomFinished = false,
    this.results = const [],
    this.link = RaceLinkStatus.connecting,
    this.errorCode,
    this.notice,
    this.newBest = false,
    this.previousBest,
    this.levelUpSeq = 0,
    this.autoStart = false,
    this.ready = false,
    this.unconfirmed = false,
    this.endedOnVerdict = false,
    this.startRating,
    this.maxRating,
    this.flamesEarned,
  });

  final RacePhase phase;
  final RaceMode mode;
  final bool multiplayer;
  final String? code;

  /// This player's public id in the room.
  final String? you;
  final String? hostId;
  final List<RacePlayer> players;

  /// Survival's lives at the start (3); null in Infinite.
  final int? startLives;
  final int score;
  final int mistakes;

  /// Solves so far (the room's ladder level).
  final int level;
  final int streak;
  final int bestStreak;
  final RacePuzzle? puzzle;

  /// The ply the room expects next on [puzzle].
  final int ply;

  /// A move is out and its verdict has not come back.
  final bool awaitingVerdict;
  final List<RacePuzzleRecord> records;
  final RaceMoveEvent? lastMove;
  final RaceRejectEvent? lastReject;

  /// Server time the clock started.
  final int? startedAt;

  /// Server time the countdown ends.
  final int? countdownEndsAt;

  /// Server clock minus this device's clock, estimated.
  final int clockOffsetMs;

  /// The room's race clock at the last verdict.
  final int? lastElapsedMs;

  /// This player's time, from the room, once their run ended.
  final int? finalElapsedMs;
  final RaceFinishReason? finishReason;
  final bool roomFinished;
  final List<RaceResult> results;
  final RaceLinkStatus link;
  final String? errorCode;
  final RaceNotice? notice;
  final bool newBest;

  /// This mode's best before this race, once it has been recorded.
  final int? previousBest;

  /// Bumped on every level-up (the frame's accent listens).
  final int levelUpSeq;

  /// Solo: start the countdown as soon as the room has the player.
  final bool autoStart;

  /// Multiplayer lobby: this player said they are ready.
  final bool ready;

  /// The run's end is this device's own: the link ended before the room's
  /// `finished` arrived, and the room's standings could not confirm it.
  final bool unconfirmed;

  /// The run ended on the verdict just given (Survival's last miss, the
  /// puzzle limit), so the board holds that verdict a moment before the
  /// results replace it.
  final bool endedOnVerdict;

  /// Where the room's ladder starts, as the room said. Null until it has
  /// (or from a room that does not say).
  final int? startRating;

  /// The room's ladder ceiling; null without one.
  final int? maxRating;

  /// Flames this run earned, once it ended: the room's count, or this
  /// device's own when the room gave none.
  final int? flamesEarned;

  bool get isHost => you != null && you == hostId;

  int? get livesLeft =>
      startLives == null ? null : math.max(0, startLives! - mistakes);

  int get displayLevel => raceDisplayLevel(level);

  RacePlayer? get me {
    for (final p in players) {
      if (p.id == you) return p;
    }
    return null;
  }

  /// Everyone else in the room.
  List<RacePlayer> get opponents => [
    for (final p in players)
      if (p.id != you) p,
  ];

  RaceResult? get myResult {
    for (final r in results) {
      if (r.id == you) return r;
    }
    return null;
  }

  int get attempted => records.length;

  /// Solved share of the finished puzzles, 0..1; null before any.
  double? get accuracy {
    if (records.isEmpty) return null;
    final solved = records.where((r) => r.solved).length;
    return solved / records.length;
  }

  /// The race clock at this device's [localNowMs]: the room's start and the
  /// estimated offset, frozen at the room's own figure once the run ended.
  int elapsedAt(int localNowMs) {
    final done = finalElapsedMs;
    if (done != null) return done;
    final start = startedAt;
    if (start == null) return 0;
    final t = localNowMs + clockOffsetMs - start;
    return t < 0 ? 0 : t;
  }

  /// Milliseconds left in the countdown at [localNowMs]; null without one.
  int? countdownLeftAt(int localNowMs) {
    final ends = countdownEndsAt;
    if (ends == null) return null;
    return math.max(0, ends - (localNowMs + clockOffsetMs));
  }

  static const Object _keep = Object();

  RaceState copyWith({
    RacePhase? phase,
    RaceMode? mode,
    bool? multiplayer,
    Object? code = _keep,
    Object? you = _keep,
    Object? hostId = _keep,
    List<RacePlayer>? players,
    Object? startLives = _keep,
    int? score,
    int? mistakes,
    int? level,
    int? streak,
    int? bestStreak,
    Object? puzzle = _keep,
    int? ply,
    bool? awaitingVerdict,
    List<RacePuzzleRecord>? records,
    Object? lastMove = _keep,
    Object? lastReject = _keep,
    Object? startedAt = _keep,
    Object? countdownEndsAt = _keep,
    int? clockOffsetMs,
    Object? lastElapsedMs = _keep,
    Object? finalElapsedMs = _keep,
    Object? finishReason = _keep,
    bool? roomFinished,
    List<RaceResult>? results,
    RaceLinkStatus? link,
    Object? errorCode = _keep,
    Object? notice = _keep,
    bool? newBest,
    Object? previousBest = _keep,
    int? levelUpSeq,
    bool? autoStart,
    bool? ready,
    bool? unconfirmed,
    bool? endedOnVerdict,
    Object? startRating = _keep,
    Object? maxRating = _keep,
    Object? flamesEarned = _keep,
  }) {
    T pick<T>(Object? value, T current) =>
        identical(value, _keep) ? current : value as T;
    return RaceState(
      phase: phase ?? this.phase,
      mode: mode ?? this.mode,
      multiplayer: multiplayer ?? this.multiplayer,
      code: pick<String?>(code, this.code),
      you: pick<String?>(you, this.you),
      hostId: pick<String?>(hostId, this.hostId),
      players: players ?? this.players,
      startLives: pick<int?>(startLives, this.startLives),
      score: score ?? this.score,
      mistakes: mistakes ?? this.mistakes,
      level: level ?? this.level,
      streak: streak ?? this.streak,
      bestStreak: bestStreak ?? this.bestStreak,
      puzzle: pick<RacePuzzle?>(puzzle, this.puzzle),
      ply: ply ?? this.ply,
      awaitingVerdict: awaitingVerdict ?? this.awaitingVerdict,
      records: records ?? this.records,
      lastMove: pick<RaceMoveEvent?>(lastMove, this.lastMove),
      lastReject: pick<RaceRejectEvent?>(lastReject, this.lastReject),
      startedAt: pick<int?>(startedAt, this.startedAt),
      countdownEndsAt: pick<int?>(countdownEndsAt, this.countdownEndsAt),
      clockOffsetMs: clockOffsetMs ?? this.clockOffsetMs,
      lastElapsedMs: pick<int?>(lastElapsedMs, this.lastElapsedMs),
      finalElapsedMs: pick<int?>(finalElapsedMs, this.finalElapsedMs),
      finishReason: pick<RaceFinishReason?>(finishReason, this.finishReason),
      roomFinished: roomFinished ?? this.roomFinished,
      results: results ?? this.results,
      link: link ?? this.link,
      errorCode: pick<String?>(errorCode, this.errorCode),
      notice: pick<RaceNotice?>(notice, this.notice),
      newBest: newBest ?? this.newBest,
      previousBest: pick<int?>(previousBest, this.previousBest),
      levelUpSeq: levelUpSeq ?? this.levelUpSeq,
      autoStart: autoStart ?? this.autoStart,
      ready: ready ?? this.ready,
      unconfirmed: unconfirmed ?? this.unconfirmed,
      endedOnVerdict: endedOnVerdict ?? this.endedOnVerdict,
      startRating: pick<int?>(startRating, this.startRating),
      maxRating: pick<int?>(maxRating, this.maxRating),
      flamesEarned: pick<int?>(flamesEarned, this.flamesEarned),
    );
  }
}

/// Who is racing, as far as the room is concerned.
abstract interface class RaceAuth {
  /// Signed in with a real (not anonymous) account.
  bool get signedIn;

  /// The current Supabase access token of that account; null otherwise.
  String? get accessToken;

  /// A name to show other players; null lets the room pick one.
  String? get displayName;
}

/// A [RaceAuth] that can hold a request back while the auth SDK refreshes a
/// token about to expire, so a room never sees one that dies mid-race.
abstract interface class RaceRefreshingAuth implements RaceAuth {
  /// [accessToken] while it has more than 30s left; closer to expiry, the
  /// one the SDK refreshes to, waited for briefly (see [raceFreshToken]).
  /// Null when signed out.
  Future<String?> freshAccessToken();
}

/// [RaceAuth] from the Supabase session. A guest (anonymous) session counts
/// as signed out: multiplayer needs an account, and a solo guest races on a
/// seat instead of a token.
class SupabaseRaceAuth implements RaceRefreshingAuth {
  const SupabaseRaceAuth();

  User? get _user {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      return user == null || user.isAnonymous ? null : user;
    } catch (_) {
      // Supabase not initialised (tests).
      return null;
    }
  }

  @override
  bool get signedIn => _user != null && accessToken != null;

  @override
  String? get accessToken {
    if (_user == null) return null;
    try {
      final token = Supabase.instance.client.auth.currentSession?.accessToken;
      return token == null || token.isEmpty ? null : token;
    } catch (_) {
      return null;
    }
  }

  /// Waits out the SDK's own refresh rather than calling `refreshSession`:
  /// a competing refresh trips refresh-token reuse detection (main.dart).
  @override
  Future<String?> freshAccessToken() async {
    if (_user == null) return null;
    final GoTrueClient auth;
    try {
      auth = Supabase.instance.client.auth;
    } catch (_) {
      return null;
    }
    final token = await raceFreshToken(
      read: () {
        final session = auth.currentSession;
        if (session == null || session.accessToken.isEmpty) return null;
        return (token: session.accessToken, expiresAt: session.expiresAt);
      },
      changes: auth.onAuthStateChange,
    );
    // Signed out, or down to a guest, while it waited.
    return _user == null ? null : token;
  }

  /// The account's own name, or a linked chess-site username. Never the
  /// email: other players see this.
  @override
  String? get displayName {
    final meta = _user?.userMetadata;
    if (meta == null) return null;
    for (final key in const [
      'full_name',
      'name',
      'lichess_username',
      'chesscom_username',
    ]) {
      final value = meta[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }
}

/// What the race talks to. Overridden in tests.
@immutable
class RaceDeps {
  const RaceDeps({
    required this.api,
    required this.connector,
    required this.auth,
    required this.stats,
    required this.audio,
    this.now = _systemNowMs,
    this.pingInterval = const Duration(seconds: 20),
    this.replyTimeout = RaceConnection.defaultReplyTimeout,
    this.backoff = RaceConnection.defaultBackoff,
    this.maxReconnectAttempts = 7,
    this.soloCountdown = const Duration(seconds: 3),
    this.sourceRetryDelay = const Duration(milliseconds: 1500),
    this.sourceRetryMaxDelay = const Duration(seconds: 12),
    this.sourceRetryLimit = 6,
  });

  final RaceApi api;
  final RaceSocketConnector connector;
  final RaceAuth auth;
  final RaceStatsStore stats;
  final RaceAudio audio;

  /// This device's clock in milliseconds.
  final int Function() now;
  final Duration pingInterval;

  /// How long a move (or a running stop) may wait without any frame back
  /// before the socket counts as dead and the link reconnects.
  final Duration replyTimeout;
  final List<Duration> backoff;
  final int maxReconnectAttempts;

  /// The local 3-2-1 before a solo race's `start`.
  final Duration soloCountdown;

  /// Wait before asking again when the room's puzzle source hiccuped. It
  /// doubles with every failure in a row, up to [sourceRetryMaxDelay].
  final Duration sourceRetryDelay;
  final Duration sourceRetryMaxDelay;

  /// Failures in a row after which the run ends instead of asking again.
  final int sourceRetryLimit;
}

int _systemNowMs() => DateTime.now().millisecondsSinceEpoch;

final raceDepsProvider = Provider<RaceDeps>((ref) {
  final api = RaceHttpApi(baseUrl: kRaceApiUrl);
  ref.onDispose(api.close);
  return RaceDeps(
    api: api,
    connector: connectRaceSocket,
    auth: const SupabaseRaceAuth(),
    stats: PrefsRaceStatsStore(),
    audio: ref.read(raceAudioProvider),
  );
});

/// The personal bests, for the lobby. Re-read on every visit.
final raceBestsProvider = FutureProvider.autoDispose<RaceBests>(
  (ref) => ref.read(raceDepsProvider).stats.read(),
);

/// One race, from choosing a mode to the results. Disposed with the race
/// screen, which closes the socket.
final raceControllerProvider =
    NotifierProvider.autoDispose<RaceController, RaceState>(RaceController.new);

/// Runs a race off the room's messages. The room is the authority for
/// everything that counts (clock, verdicts, score, lives, the end); this only
/// keeps what the screen needs and plays the race's sounds.
class RaceController extends AutoDisposeNotifier<RaceState> {
  late RaceDeps _deps;
  RaceConnection? _link;
  String? _seat;

  /// Bumped per race, so a stale await from an earlier one changes nothing.
  int _generation = 0;
  bool _disposed = false;
  int _seq = 0;

  _PendingMove? _pending;
  final List<Timer> _beats = [];
  Timer? _soloStart;
  Timer? _sourceRetry;
  int? _beatsFor;

  /// Bumped on every open of the link (see [_PendingMove.epoch]).
  int _linkEpoch = 0;

  /// The player ended their run and the room has not answered with
  /// `finished` yet. The `stop` goes out again on every reopen of the link
  /// (a first one may have died with a socket), instead of `join`.
  bool _stopQueued = false;

  /// Links handed off by a race that is over on this device while the room
  /// still waits for its `stop`: each delivers it on its next open, then
  /// closes (or gives up on its own after its reconnect attempts).
  final Set<RaceConnection> _stopCarriers = {};

  /// The puzzle source's failures in a row, while running.
  int _sourceFailures = 0;

  /// This device's clock when the last complete verdict arrived, while no
  /// puzzle has followed it.
  int? _verdictAt;

  bool _goPlayed = false;
  bool _lastLifePlayed = false;
  bool _statsRecorded = false;
  double _tension = -1;
  int _completedElapsedMs = 0;

  /// Clock-offset estimates: the best ping (smallest round trip) and the
  /// largest lower bound from one-way stamps.
  int? _bestRttMs;
  int? _pingOffsetMs;
  int? _lowerBoundMs;

  RaceAudio get _audio => _deps.audio;

  @override
  RaceState build() {
    _disposed = false;
    _deps = ref.watch(raceDepsProvider);
    ref.onDispose(_teardown);
    return const RaceState();
  }

  bool get isConfigured => _deps.api.isConfigured;
  bool get signedIn => _deps.auth.signedIn;

  // ------------------------------------------------------------ choosing

  /// Choosing again after a failure starts over from the setup.
  void selectMode(RaceMode mode) {
    if (state.phase == RacePhase.failed) backToSetup();
    if (state.phase != RacePhase.setup) return;
    state = state.copyWith(mode: mode);
  }

  void selectMultiplayer(bool multiplayer) {
    if (state.phase == RacePhase.failed) backToSetup();
    if (state.phase != RacePhase.setup) return;
    state = state.copyWith(multiplayer: multiplayer);
  }

  /// Solo: a room of one, started as soon as it is ready.
  Future<void> startSolo() => _create(multiplayer: false);

  /// Multiplayer: a room others join with its code.
  Future<void> createRoom() => _create(multiplayer: true);

  Future<void> _create({required bool multiplayer}) async {
    if (!isConfigured) {
      _fail('not_configured');
      return;
    }
    if (multiplayer && _deps.auth.accessToken == null) {
      _notice('authentication_required');
      return;
    }
    final generation = _reset(
      phase: RacePhase.creating,
      multiplayer: multiplayer,
      autoStart: !multiplayer,
    );
    _audio.warmUp();
    // A token about to expire would be a 401 (`invalid_token`) here.
    final token = _deps.auth.accessToken == null ? null : await _freshToken();
    if (!_current(generation)) return;
    if (multiplayer && token == null) {
      // Signed out while the refresh was awaited.
      _fail('authentication_required');
      return;
    }
    // Where the player chose to start. A race climbs from there with no
    // ceiling: the band's top is the Feed's casual puzzles' alone, so it is
    // never sent. A room never trusts the start beyond clamping it.
    final start = ref.read(puzzleRatingRangeProvider).min;
    RaceCreated created;
    try {
      created = await _deps.api.create(
        mode: state.mode,
        multiplayer: multiplayer,
        token: token,
        minRating: start,
      );
    } on RaceApiException catch (error) {
      if (!_current(generation)) return;
      // A stale token must not keep a guest from a solo race.
      if (!multiplayer && token != null && error.statusCode == 401) {
        try {
          created = await _deps.api.create(
            mode: state.mode,
            multiplayer: false,
            minRating: start,
          );
        } on RaceApiException catch (retry) {
          if (_current(generation)) _fail(retry.code);
          return;
        }
      } else {
        _fail(error.code);
        return;
      }
    }
    if (!_current(generation)) return;
    _seat = created.seat;
    state = state.copyWith(
      phase: RacePhase.connecting,
      code: created.code,
      mode: created.mode,
    );
    await _connect(created.wsUrl, generation);
  }

  /// Joins someone's room by its code.
  Future<void> joinRoom(String input) async {
    if (!isConfigured) {
      _fail('not_configured');
      return;
    }
    final code = normalizeRaceCode(input);
    if (code == null) {
      _notice('invalid_code');
      return;
    }
    if (_deps.auth.accessToken == null) {
      _notice('authentication_required');
      return;
    }
    final generation = _reset(
      phase: RacePhase.connecting,
      multiplayer: true,
      autoStart: false,
    );
    _audio.warmUp();
    _seat = null;
    state = state.copyWith(code: code);
    await _connect(_deps.api.socketUri(code), generation);
  }

  Future<void> _connect(Uri uri, int generation) async {
    final seat = _seat;
    late final RaceConnection link;
    link = RaceConnection(
      uri: uri,
      connector: _deps.connector,
      pingInterval: _deps.pingInterval,
      replyTimeout: _deps.replyTimeout,
      backoff: _deps.backoff,
      maxAttempts: _deps.maxReconnectAttempts,
      headers: () async {
        if (seat != null) return {'X-Race-Seat': seat};
        // Read per attempt: a run can outlast the token's hour, and a
        // reconnect after a resume can come before the SDK's refresh.
        final token = await _freshToken();
        return token == null ? const {} : {'Authorization': 'Bearer $token'};
      },
      onEvent: (event) {
        if (_stopCarriers.contains(link)) {
          _carryStop(link, event);
        } else if (_current(generation)) {
          _onLink(event);
        }
      },
    );
    _link = link;
    await link.open();
  }

  /// A handed-off [link] (see [_stopCarriers]): on its next open it sends
  /// the owed `stop` and closes. The room seats the socket itself on the
  /// upgrade, so the `stop` needs no `join` first.
  void _carryStop(RaceConnection link, RaceLinkEvent event) {
    switch (event) {
      case RaceLinkOpened():
        _stopCarriers.remove(link);
        link.send(RaceClientMessage.stop());
        unawaited(link.close());
      case RaceLinkClosed():
        _stopCarriers.remove(link);
      case RaceLinkReconnecting() || RaceLinkMessage():
        break;
    }
  }

  // ------------------------------------------------------------- actions

  /// Host, multiplayer: starts the room's countdown.
  void startRace() {
    if (state.phase != RacePhase.lobby) return;
    if (!state.multiplayer) {
      _beginSoloCountdown();
      return;
    }
    if (!state.isHost) return;
    if (!_send(RaceClientMessage.start())) _notice('connection_lost');
  }

  void setReady(bool ready) {
    if (state.phase != RacePhase.lobby || !state.multiplayer) return;
    if (_send(RaceClientMessage.ready(ready))) {
      state = state.copyWith(ready: ready);
    }
  }

  /// Sends the player's move. False when it cannot go now (no puzzle, a
  /// verdict still out, or no socket); the board then keeps its position.
  bool submitMove(String uci) {
    final puzzle = state.puzzle;
    if (state.phase != RacePhase.running ||
        puzzle == null ||
        _pending != null ||
        _stopQueued) {
      return false;
    }
    final pending = _PendingMove(
      index: puzzle.index,
      ply: state.ply,
      uci: uci,
      epoch: _linkEpoch,
    );
    final sent = _send(
      RaceClientMessage.move(
        puzzleIndex: pending.index,
        uci: pending.uci,
        ply: pending.ply,
      ),
      // The board is locked until the verdict; a socket that went quiet
      // is dropped and resumed rather than left holding it.
      expectReply: true,
    );
    if (!sent) return false;
    _pending = pending;
    state = state.copyWith(awaitingVerdict: true);
    return true;
  }

  /// Ends the run (running), or leaves the room (before it started).
  void stop() {
    switch (state.phase) {
      case RacePhase.running:
        _stopRun();
      case RacePhase.countdown when !state.multiplayer:
        leave();
      case RacePhase.countdown:
        // The room's countdown cannot be cancelled; the run ends at once.
        if (!_send(RaceClientMessage.stop())) leave();
      case RacePhase.lobby ||
          RacePhase.connecting ||
          RacePhase.creating ||
          RacePhase.failed:
        leave();
      case RacePhase.setup || RacePhase.finished:
        break;
    }
  }

  /// Ends this player's run in the room, which answers with `finished`.
  /// Between sockets the `stop` waits for the next open rather than being
  /// dropped; only a link that is gone for good ends the run here.
  void _stopRun() {
    if (_stopQueued) return;
    final sent = _send(RaceClientMessage.stop(), expectReply: true);
    if (sent || _link?.status == RaceLinkStatus.reconnecting) {
      _stopQueued = true;
      if (!sent) _notice('stop_queued');
      return;
    }
    _finishLocally();
  }

  /// Sends `stop` on the way out of a room. Between sockets it is queued,
  /// and [_closeLink] hands the link off to deliver it.
  void _sendStop() {
    if (_send(RaceClientMessage.stop())) return;
    if (_link?.status == RaceLinkStatus.reconnecting) _stopQueued = true;
  }

  /// Leaves whatever room this is and goes back to choosing a mode.
  void leave() {
    if (state.phase == RacePhase.lobby || state.phase == RacePhase.countdown) {
      // Frees the seat; a departing host hands the room on.
      _sendStop();
    }
    _closeRace();
    state = RaceState(mode: state.mode, multiplayer: state.multiplayer);
  }

  /// After a failure: the same kind of race again.
  Future<void> retry() async {
    final link = _link;
    if (state.phase == RacePhase.failed &&
        link != null &&
        link.isOpen &&
        state.startedAt == null &&
        state.code != null) {
      // Still in the room: ask again.
      state = state.copyWith(phase: RacePhase.lobby, errorCode: null);
      if (!state.multiplayer) {
        _beginSoloCountdown();
      } else if (state.me == null) {
        // Never seated: ask for the seat again.
        _send(RaceClientMessage.join(_deps.auth.displayName));
      }
      return;
    }
    final multiplayer = state.multiplayer;
    final code = state.code;
    final wasHost = state.isHost;
    // A room that has not started keeps every seat, the host's included,
    // and a host's friends are waiting in it with its code: go back in.
    final rejoin =
        multiplayer && code != null && (!wasHost || state.startedAt == null);
    backToSetup();
    if (rejoin) {
      await joinRoom(code);
      final gone =
          state.phase == RacePhase.failed &&
          (state.errorCode == 'room_not_found' ||
              state.errorCode == 'race_finished');
      if (wasHost && gone) {
        backToSetup();
        await createRoom();
      }
    } else if (multiplayer) {
      await createRoom();
    } else {
      await startSolo();
    }
  }

  /// From the results: a new solo race in the same mode, or back to the
  /// setup for multiplayer (a new room needs a new code).
  Future<void> playAgain() async {
    final multiplayer = state.multiplayer;
    backToSetup();
    if (!multiplayer) await startSolo();
  }

  void backToSetup() {
    _closeRace();
    state = RaceState(mode: state.mode, multiplayer: state.multiplayer);
  }

  // ------------------------------------------------------------- the link

  void _onLink(RaceLinkEvent event) {
    switch (event) {
      case RaceLinkOpened():
        _linkEpoch += 1;
        state = state.copyWith(link: RaceLinkStatus.open);
        if (_stopQueued && state.phase == RacePhase.running) {
          // The player ended their run while the link was down. The room
          // seats this socket on the upgrade, so `stop` goes first and
          // `join` (which would re-send the puzzle) not at all.
          _send(RaceClientMessage.stop(), expectReply: true);
        } else {
          _send(RaceClientMessage.join(_deps.auth.displayName));
        }
        _send(RaceClientMessage.clockPing(_deps.now()));
      case RaceLinkReconnecting():
        // A move in flight may never be answered; the resume re-sends the
        // puzzle where the room has it.
        state = state.copyWith(link: RaceLinkStatus.reconnecting);
      case RaceLinkMessage(:final message):
        _onMessage(message);
      case RaceLinkClosed(:final error):
        _link = null;
        state = state.copyWith(link: RaceLinkStatus.closed);
        if (state.phase == RacePhase.finished) return;
        if (error == null || error.code == 'race_finished') {
          // The room closed on its own (finished or expired) before this
          // player heard their result.
          if (state.startedAt != null) {
            _finishLocally();
          } else {
            _fail(error?.code ?? 'room_closed');
          }
          return;
        }
        if (state.phase == RacePhase.running && error.code != 'replaced') {
          _finishLocally();
          _notice(error.code);
          return;
        }
        _fail(error.code);
    }
  }

  void _onMessage(RaceServerMessage message) {
    switch (message) {
      case RaceSnapshot():
        _onSnapshot(message);
      case RacePuzzleMessage():
        _onPuzzle(message);
      case RaceVerdict():
        _onVerdict(message);
      case RaceFinished():
        _onFinished(message);
      case RacePong(:final serverNow, :final t):
        if (serverNow != null && t != null) _samplePing(serverNow, t);
      case RaceError():
        _onError(message);
      case RaceUnknownMessage():
        break;
    }
  }

  void _onSnapshot(RaceSnapshot s) {
    // A room that refused this player (or a failure awaiting "Try again")
    // must not carry them into its countdown and race.
    if (state.phase == RacePhase.failed) return;
    _sampleStamp(s.serverNow);
    RacePlayer? me;
    for (final p in s.players) {
      if (p.id == s.you) me = p;
    }
    var next = state.copyWith(
      code: s.code.isEmpty ? state.code : s.code,
      mode: s.mode ?? state.mode,
      multiplayer: s.multiplayer,
      you: s.you,
      hostId: s.hostId,
      players: s.players,
      startLives: s.lives,
      startedAt: s.startedAt ?? state.startedAt,
      countdownEndsAt: s.state == RaceRoomState.countdown
          ? s.countdownEndsAt
          : state.phase == RacePhase.countdown && !s.multiplayer
          ? state.countdownEndsAt
          : null,
      clockOffsetMs: _offset,
      startRating: s.startRating ?? state.startRating,
      maxRating: s.startRating != null ? s.maxRating : state.maxRating,
    );
    if (me != null && state.phase != RacePhase.finished) {
      next = next.copyWith(
        score: me.score,
        mistakes: me.mistakes,
        level: me.level,
        ready: me.ready,
      );
    }
    final phase = state.phase;
    switch (s.state) {
      case RaceRoomState.lobby:
        if (phase == RacePhase.countdown && !s.multiplayer) {
          break; // our own 3-2-1 is running
        }
        if (phase == RacePhase.connecting ||
            phase == RacePhase.creating ||
            phase == RacePhase.countdown) {
          next = next.copyWith(phase: RacePhase.lobby);
          _cancelBeats();
        }
      case RaceRoomState.countdown:
        if (phase != RacePhase.finished) {
          next = next.copyWith(phase: RacePhase.countdown);
          final ends = s.countdownEndsAt;
          if (ends != null && ends != _beatsFor) _scheduleBeats(ends);
        }
      case RaceRoomState.starting:
        if (phase == RacePhase.lobby ||
            phase == RacePhase.connecting ||
            phase == RacePhase.creating) {
          next = next.copyWith(phase: RacePhase.countdown);
        }
      case RaceRoomState.running:
        if (phase != RacePhase.finished && me?.finished != true) {
          next = next.copyWith(phase: RacePhase.running, countdownEndsAt: null);
        }
      case RaceRoomState.finished:
        if (phase == RacePhase.connecting || phase == RacePhase.creating) {
          next = next.copyWith(
            phase: RacePhase.failed,
            errorCode: 'race_finished',
          );
        }
      case RaceRoomState.unknown:
        break;
    }
    state = next;

    if (state.phase == RacePhase.running && !_goPlayed) {
      _goPlayed = true;
      _cancelBeats();
      _audio.go();
      _updateTension();
    }
    if (state.phase == RacePhase.lobby &&
        state.autoStart &&
        !state.multiplayer &&
        me != null &&
        _soloStart == null) {
      _beginSoloCountdown();
    }
  }

  void _onPuzzle(RacePuzzleMessage m) {
    if (state.phase == RacePhase.finished || state.phase == RacePhase.failed) {
      return;
    }
    // The source answered: the outage, if any, is over.
    _sourceFailures = 0;
    _sourceRetry?.cancel();
    _sourceRetry = null;
    _verdictAt = null;
    final current = state.puzzle;
    final pending = _pending;
    RacePuzzle puzzle;
    if (current != null && current.index == m.index) {
      // A resume, or `join` re-sending the puzzle (after a reconnect the
      // room sends it twice: on the upgrade and for `join`). Only a change
      // in where the line stands rebuilds the board; a move made on this
      // socket, between the two copies, is still on its way to a verdict.
      final moved =
          m.ply != state.ply ||
          (pending != null && pending.epoch != _linkEpoch);
      if (!moved) {
        if (state.phase != RacePhase.running) {
          state = state.copyWith(phase: RacePhase.running);
        }
        return;
      }
      puzzle = RacePuzzle.fromMessage(m, revision: current.revision + 1);
    } else {
      puzzle = RacePuzzle.fromMessage(m);
    }
    _pending = null;
    state = state.copyWith(
      phase: RacePhase.running,
      puzzle: puzzle,
      ply: m.ply,
      awaitingVerdict: false,
      countdownEndsAt: null,
    );
    if (!_goPlayed) {
      _goPlayed = true;
      _cancelBeats();
      _audio.go();
      _updateTension();
    }
  }

  void _onVerdict(RaceVerdict v) {
    _sampleStamp(v.serverNow);
    final pending = _pending;
    _pending = null;
    final puzzle = state.puzzle;
    final seq = ++_seq;
    final uci = pending != null && pending.index == v.index
        ? pending.uci
        : null;

    if (!v.complete) {
      state = state.copyWith(
        ply: v.nextPly ?? state.ply + 2,
        awaitingVerdict: false,
        score: v.score,
        mistakes: v.mistakes,
        level: v.level,
        lastElapsedMs: v.elapsedMs,
        clockOffsetMs: _offset,
        lastMove: RaceMoveEvent(
          seq: seq,
          index: v.index,
          uci: uci,
          correct: true,
          complete: false,
          reply: v.expectedReply,
        ),
      );
      return;
    }

    _verdictAt = _deps.now();
    final solved = v.correct;
    final streak = solved ? state.streak + 1 : 0;
    final timeMs = math.max(0, v.elapsedMs - _completedElapsedMs);
    _completedElapsedMs = v.elapsedMs;
    final records = [...state.records];
    if (puzzle != null && puzzle.index == v.index) {
      final solverPlies = math.max(0, state.ply - 1);
      final finalLine = solved
          ? v.solutionRevealed
          : [
              ...v.solutionRevealed.take(
                math.min(solverPlies, v.solutionRevealed.length),
              ),
              ?uci,
            ];
      records.removeWhere((r) => r.puzzle.index == v.index);
      records.add(
        RacePuzzleRecord(
          puzzle: puzzle,
          solved: solved,
          solution: List.unmodifiable(v.solutionRevealed),
          finalLine: List.unmodifiable(finalLine),
          timeMs: timeMs,
          puzzleId: v.puzzleId,
          themes: List.unmodifiable(v.themes),
        ),
      );
    }
    final levelUp = raceDisplayLevel(v.level) > raceDisplayLevel(state.level);
    state = state.copyWith(
      awaitingVerdict: false,
      score: v.score,
      mistakes: v.mistakes,
      level: v.level,
      streak: streak,
      bestStreak: math.max(state.bestStreak, streak),
      records: records,
      lastElapsedMs: v.elapsedMs,
      clockOffsetMs: _offset,
      levelUpSeq: levelUp ? state.levelUpSeq + 1 : state.levelUpSeq,
      lastMove: RaceMoveEvent(
        seq: seq,
        index: v.index,
        uci: uci,
        correct: solved,
        complete: true,
      ),
    );

    if (solved) {
      _audio.correct(streak: streak);
      if (levelUp) _audio.levelUp();
    } else {
      _audio.wrong();
      final left = state.livesLeft;
      if (left == 1 && !_lastLifePlayed) {
        _lastLifePlayed = true;
        _audio.lastLife();
      }
    }
    _updateTension();
  }

  void _onFinished(RaceFinished f) {
    _sampleStamp(f.serverNow);
    final mine = f.playerId == null || f.playerId == state.you;
    if (!mine && !f.roomFinished) return;
    RaceResult? my;
    for (final r in f.results) {
      if (r.id == state.you) my = r;
    }
    final first = state.phase != RacePhase.finished;
    if (!first) {
      state = state.copyWith(
        results: f.results,
        roomFinished: state.roomFinished || f.roomFinished,
      );
      return;
    }
    _pending = null;
    _stopQueued = false;
    _cancelBeats();
    _soloStart?.cancel();
    _soloStart = null;
    _sourceRetry?.cancel();
    _sourceRetry = null;
    // Survival's last miss comes with its `finished` right behind it: that
    // verdict is still to be seen.
    final verdictAt = _verdictAt;
    final endedOnVerdict =
        verdictAt != null &&
        _deps.now() - verdictAt < kRaceVerdictFinishWindow.inMilliseconds;
    state = state.copyWith(
      phase: RacePhase.finished,
      results: f.results,
      roomFinished: f.roomFinished,
      finishReason: f.reason ?? my?.finishReason,
      finalElapsedMs: my?.elapsedMs ?? state.lastElapsedMs ?? 0,
      score: my?.score ?? state.score,
      mistakes: my?.mistakes ?? state.mistakes,
      level: my?.level ?? state.level,
      awaitingVerdict: false,
      clockOffsetMs: _offset,
      endedOnVerdict: endedOnVerdict,
      flamesEarned: my?.flames ?? raceLocalFlames(state.records),
    );
    _finishSound();
    if (!_statsRecorded && state.startedAt != null) {
      _statsRecorded = true;
      unawaited(
        _recordStats(
          generation: _generation,
          mode: state.mode,
          score: state.score,
          bestStreak: state.bestStreak,
          flames: state.flamesEarned ?? 0,
        ),
      );
    }
  }

  void _onError(RaceError e) {
    switch (e.code) {
      case 'stale':
      case 'illegal_move':
      case 'rate_limited':
      case 'not_joined':
        final pending = _pending;
        _pending = null;
        if (pending != null) {
          state = state.copyWith(
            awaitingVerdict: false,
            lastReject: RaceRejectEvent(seq: ++_seq, index: pending.index),
          );
        }
        if (e.code == 'stale' || e.code == 'not_joined') {
          // Out of step with the room: `join` re-sends where it stands.
          _send(RaceClientMessage.join(_deps.auth.displayName));
        }
        if (e.code == 'rate_limited') _notice('rate_limited');
      case 'puzzle_source_unavailable':
        if (state.phase == RacePhase.running) {
          _onSourceDown();
        } else if (!state.multiplayer) {
          _soloStart?.cancel();
          _soloStart = null;
          _cancelBeats();
          state = state.copyWith(
            phase: RacePhase.failed,
            errorCode: 'puzzle_source_unavailable',
            countdownEndsAt: null,
          );
        } else {
          _cancelBeats();
          _notice('puzzle_source_unavailable');
        }
      case 'room_full':
      case 'already_started':
      case 'forbidden':
      case 'authentication_required':
        // The room stamps `you` on the very first snapshot, before `join`
        // seats anyone, so "not in the room" means not among its players.
        if (state.phase == RacePhase.connecting ||
            state.phase == RacePhase.lobby && state.me == null) {
          // Refused a seat: this socket has no business in the room, and
          // its next snapshot would otherwise count it into the race.
          _closeLink();
          state = state.copyWith(link: RaceLinkStatus.closed);
          _fail(e.code);
        } else {
          _notice(e.code);
        }
      case 'not_host':
      case 'join_first':
      case 'invalid_json':
      case 'invalid_message':
      case 'invalid_move_message':
      case 'unknown_type':
      case 'message_too_large':
      case 'binary_not_supported':
      case 'not_running':
      case 'finished':
      case 'internal_error':
      case 'puzzle_unavailable':
        debugPrint('[Race] room said ${e.code}');
        final pending = _pending;
        if (pending != null) {
          _pending = null;
          state = state.copyWith(
            awaitingVerdict: false,
            lastReject: RaceRejectEvent(seq: ++_seq, index: pending.index),
          );
        }
      default:
        debugPrint('[Race] room said ${e.code}');
    }
  }

  /// The room's puzzle source failed mid-run. The room re-sends the puzzle
  /// on `join` once the source answers; each try waits twice as long as the
  /// last, the player hears about it once, and a source that stays down
  /// ends the run through the room.
  void _onSourceDown() {
    if (_stopQueued) return;
    _sourceFailures += 1;
    if (_sourceFailures == 1) _notice('puzzle_source_unavailable');
    _sourceRetry?.cancel();
    _sourceRetry = null;
    if (_sourceFailures >= _deps.sourceRetryLimit) {
      _notice('puzzle_source_gave_up');
      _stopRun();
      return;
    }
    final base = _deps.sourceRetryDelay.inMilliseconds;
    final cap = _deps.sourceRetryMaxDelay.inMilliseconds;
    final wait = math.min(cap, base << math.min(_sourceFailures - 1, 20));
    _sourceRetry = Timer(Duration(milliseconds: wait), () {
      _sourceRetry = null;
      if (_disposed || state.phase != RacePhase.running || _stopQueued) return;
      _send(RaceClientMessage.join(_deps.auth.displayName));
    });
  }

  // ------------------------------------------------------------ the clock

  int get _offset => _pingOffsetMs == null
      ? (_lowerBoundMs ?? 0)
      : math.max(_pingOffsetMs!, _lowerBoundMs ?? _pingOffsetMs!);

  /// A one-way stamp: the room's clock when it sent a message is at most
  /// this device's clock on arrival plus the offset, so each stamp is a
  /// lower bound on the offset.
  void _sampleStamp(int serverNow) {
    if (serverNow <= 0) return;
    final bound = serverNow - _deps.now();
    if (_lowerBoundMs == null || bound > _lowerBoundMs!) {
      _lowerBoundMs = bound;
    }
  }

  /// A ping's answer: the room stamped it about halfway through the round
  /// trip. The shortest round trip is the most precise.
  void _samplePing(int serverNow, int sentAt) {
    final now = _deps.now();
    final rtt = now - sentAt;
    if (rtt < 0 || rtt > 30000) return;
    if (_bestRttMs == null || rtt <= _bestRttMs!) {
      _bestRttMs = rtt;
      _pingOffsetMs = serverNow - (sentAt + rtt ~/ 2);
    }
    _sampleStamp(serverNow);
    state = state.copyWith(clockOffsetMs: _offset);
  }

  // ---------------------------------------------------------- countdowns

  void _beginSoloCountdown() {
    if (_soloStart != null) return;
    final length = _deps.soloCountdown;
    final ends = _deps.now() + _offset + length.inMilliseconds;
    state = state.copyWith(
      phase: RacePhase.countdown,
      countdownEndsAt: ends,
      clockOffsetMs: _offset,
      errorCode: null,
    );
    _scheduleBeats(ends);
    _soloStart = Timer(length, () {
      _soloStart = null;
      if (_disposed || state.phase != RacePhase.countdown) return;
      if (!_send(RaceClientMessage.start())) {
        _fail('connection_lost');
      }
    });
  }

  void _scheduleBeats(int endsAtServerMs) {
    _cancelBeats();
    _beatsFor = endsAtServerMs;
    final serverNow = _deps.now() + _offset;
    for (final n in const [3, 2, 1]) {
      final at = endsAtServerMs - n * 1000;
      final wait = at - serverNow;
      if (wait < -300) continue; // that beat is long gone
      _beats.add(
        Timer(Duration(milliseconds: math.max(0, wait)), () {
          if (!_disposed) _audio.countdownBeat(n);
        }),
      );
    }
  }

  void _cancelBeats() {
    for (final t in _beats) {
      t.cancel();
    }
    _beats.clear();
  }

  // -------------------------------------------------------------- the end

  /// The socket is gone for good and the room's `finished` never came. The
  /// results show at once on the last figures this device had, marked
  /// [RaceState.unconfirmed]; then the room's own standings replace them
  /// ([_confirmFromRoom]).
  void _finishLocally() {
    if (state.phase == RacePhase.finished) return;
    final stopped = _stopQueued;
    _pending = null;
    _stopQueued = false;
    _cancelBeats();
    _sourceRetry?.cancel();
    _sourceRetry = null;
    final elapsed = state.lastElapsedMs ?? state.elapsedAt(_deps.now());
    // "You ended the run" only when the player did.
    final reason =
        state.finishReason ?? (stopped ? RaceFinishReason.stopped : null);
    state = state.copyWith(
      phase: RacePhase.finished,
      finishReason: reason,
      finalElapsedMs: elapsed,
      awaitingVerdict: false,
      unconfirmed: true,
      flamesEarned: raceLocalFlames(state.records),
      results: state.results.isNotEmpty
          ? state.results
          : [
              RaceResult(
                rank: 1,
                id: state.you ?? '',
                name: state.me?.name ?? 'You',
                score: state.score,
                mistakes: state.mistakes,
                level: state.level,
                elapsedMs: elapsed,
                finished: true,
                finishReason: reason,
              ),
            ],
    );
    _closeLink();
    _finishSound();
    unawaited(_confirmFromRoom(_generation));
  }

  /// Reads the room's standings for a run that ended without its
  /// `finished` (`GET /v1/races/{code}/results`), takes this player's own
  /// row from them, and records the bests from the room's score. Without
  /// an answer the local figures stand, still unconfirmed.
  Future<void> _confirmFromRoom(int generation) async {
    // Read now: the player may leave (disposing this) while the room is
    // asked, and the bests are recorded either way.
    final code = state.code;
    final you = state.you;
    final mode = state.mode;
    final bestStreak = state.bestStreak;
    final record = !_statsRecorded && state.startedAt != null;
    if (record) _statsRecorded = true;
    var score = state.score;
    var flames = state.flamesEarned ?? raceLocalFlames(state.records);
    final askedAt = _deps.now();
    RaceRoomSummary? summary;
    if (code != null) {
      try {
        summary = await _deps.api.results(code);
      } on RaceApiException catch (error) {
        debugPrint('[Race] could not read the results: ${error.code}');
      } catch (error) {
        debugPrint('[Race] could not read the results: ${error.runtimeType}');
      }
    }
    final mine = summary?.resultFor(you);
    if (mine != null) score = mine.score;
    if (mine?.flames != null) flames = mine!.flames!;
    if (summary != null && mine != null && _current(generation)) {
      _applyRoomResults(summary, mine);
    }
    if (!record) return;
    await _recordStats(
      generation: generation,
      mode: mode,
      score: score,
      bestStreak: bestStreak,
      flames: flames,
      // A flourish long after the finish hit would land out of nowhere.
      flourish: _deps.now() - askedAt < 1500,
    );
  }

  /// The room's standings over a locally ended run. A row the room has
  /// finished is the whole truth; a run the room still counts as going
  /// (it ends there when the room goes quiet) gives its real score, while
  /// the end stays this device's.
  void _applyRoomResults(RaceRoomSummary summary, RaceResult mine) {
    if (state.phase != RacePhase.finished || !state.unconfirmed) return;
    if (mine.finished) {
      state = state.copyWith(
        results: summary.results,
        roomFinished: summary.state == RaceRoomState.finished,
        finishReason: mine.finishReason ?? state.finishReason,
        finalElapsedMs: mine.elapsedMs,
        score: mine.score,
        mistakes: mine.mistakes,
        level: mine.level,
        unconfirmed: false,
        flamesEarned: mine.flames ?? state.flamesEarned,
      );
      return;
    }
    final elapsed = state.finalElapsedMs ?? mine.elapsedMs;
    state = state.copyWith(
      results: [
        for (final r in summary.results)
          if (r.id == mine.id)
            RaceResult(
              rank: r.rank,
              id: r.id,
              name: r.name,
              score: r.score,
              mistakes: r.mistakes,
              level: r.level,
              bestRating: r.bestRating,
              elapsedMs: elapsed,
              finished: true,
              finishReason: state.finishReason,
              flames: r.flames,
            )
          else
            r,
      ],
      score: mine.score,
      mistakes: mine.mistakes,
      level: mine.level,
      flamesEarned: mine.flames ?? state.flamesEarned,
    );
  }

  /// The finish hit lands now, and the tension bed goes quiet.
  void _finishSound() {
    _setTension(0);
    _audio.finish();
  }

  /// Records this race's bests (and its flames, on this device) once; a new
  /// best adds its flourish.
  Future<void> _recordStats({
    required int generation,
    required RaceMode mode,
    required int score,
    required int bestStreak,
    required int flames,
    bool flourish = true,
  }) async {
    RaceRecordOutcome? outcome;
    try {
      outcome = await _deps.stats.record(
        mode: mode,
        score: score,
        bestStreak: bestStreak,
        flames: flames,
      );
    } catch (error) {
      debugPrint('[Race] could not save bests: ${error.runtimeType}');
    }
    if (!_current(generation) || outcome == null) return;
    if (outcome.newBest && flourish) _audio.finish(newBest: true);
    state = state.copyWith(
      newBest: outcome.newBest,
      previousBest: outcome.before.bestFor(mode),
    );
  }

  // ------------------------------------------------------------- helpers

  void _updateTension() {
    if (state.phase != RacePhase.running) return;
    _setTension(
      raceTension(
        solves: state.level,
        mode: state.mode,
        livesLeft: state.livesLeft,
      ),
    );
  }

  void _setTension(double value) {
    if ((value - _tension).abs() < 0.001) return;
    _tension = value;
    _audio.setTension(value);
  }

  bool _send(String frame, {bool expectReply = false}) =>
      _link?.send(frame, expectReply: expectReply) ?? false;

  /// The token for the next request or upgrade: waits out a refresh the SDK
  /// is about to make instead of sending one that is about to expire.
  Future<String?> _freshToken() async {
    final auth = _deps.auth;
    if (auth is! RaceRefreshingAuth) return auth.accessToken;
    try {
      return await auth.freshAccessToken();
    } catch (_) {
      return auth.accessToken;
    }
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  void _notice(String code) {
    state = state.copyWith(notice: RaceNotice(code, ++_seq));
  }

  void _fail(String code) {
    _soloStart?.cancel();
    _soloStart = null;
    _cancelBeats();
    // A run that dies here (another device took it over) must not leave its
    // heartbeat bed or a pending stinger playing over the setup.
    if (_tension > 0) _setTension(0);
    _audio.stopAll();
    state = state.copyWith(
      phase: RacePhase.failed,
      errorCode: code,
      countdownEndsAt: null,
    );
  }

  /// Starts a fresh race state; returns its generation.
  int _reset({
    required RacePhase phase,
    required bool multiplayer,
    required bool autoStart,
  }) {
    _closeRace();
    state = RaceState(
      phase: phase,
      mode: state.mode,
      multiplayer: multiplayer,
      autoStart: autoStart,
    );
    return _generation;
  }

  void _closeLink() {
    final link = _link;
    _link = null;
    if (link == null) return;
    if (_stopQueued && link.status == RaceLinkStatus.reconnecting) {
      // The room has not heard this player's `stop`: the link lives on just
      // long enough to deliver it.
      _stopCarriers.add(link);
      return;
    }
    unawaited(link.close());
  }

  void _closeRace() {
    _generation += 1;
    _closeLink();
    _stopQueued = false;
    _sourceFailures = 0;
    _verdictAt = null;
    _seat = null;
    _pending = null;
    _soloStart?.cancel();
    _soloStart = null;
    _sourceRetry?.cancel();
    _sourceRetry = null;
    _cancelBeats();
    _beatsFor = null;
    _goPlayed = false;
    _lastLifePlayed = false;
    _statsRecorded = false;
    _completedElapsedMs = 0;
    _bestRttMs = null;
    _pingOffsetMs = null;
    _lowerBoundMs = null;
    if (_tension > 0) _setTension(0);
    _tension = -1;
  }

  void _teardown() {
    RacePhase? phase;
    try {
      phase = state.phase;
    } catch (_) {
      phase = null;
    }
    if (phase == RacePhase.lobby ||
        phase == RacePhase.countdown ||
        phase == RacePhase.running) {
      // Leaving a lobby frees the seat for someone else; leaving a race
      // mid-run ends that run in the room rather than leaving it to idle out.
      // Between sockets, the link is handed off to deliver it.
      _sendStop();
    }
    _disposed = true;
    _closeRace();
    _audio.stopAll();
  }
}
