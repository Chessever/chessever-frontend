import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Puzzle Race wire protocol: the JSON text frames of the `race` Worker
/// (`chessever_cloudflare/apps/race`, `src/protocol.ts` and README.md).
///
/// Decoding never throws. A frame that is not JSON, or not an object, decodes
/// to null; an unknown `type` decodes to [RaceUnknownMessage]. Missing or
/// mistyped fields read as their neutral value (0, false, null, empty), so a
/// server that grows a field never breaks an older app.

/// `survival`: the third mistake ends the run. `infinite`: until you stop.
enum RaceMode {
  survival('survival'),
  infinite('infinite');

  const RaceMode(this.wire);

  final String wire;

  static RaceMode? fromWire(Object? value) {
    for (final mode in values) {
      if (mode.wire == value) return mode;
    }
    return null;
  }
}

/// The room's phase (`snapshot.state`).
enum RaceRoomState {
  lobby('lobby'),
  starting('starting'),
  countdown('countdown'),
  running('running'),
  finished('finished'),

  /// A state this app does not know yet.
  unknown('');

  const RaceRoomState(this.wire);

  final String wire;

  static RaceRoomState fromWire(Object? value) {
    for (final state in values) {
      if (state != unknown && state.wire == value) return state;
    }
    return unknown;
  }
}

/// Why a run ended (`finished.reason`, `results[].finishReason`).
enum RaceFinishReason {
  stopped('stopped'),
  lives('lives'),
  idle('idle'),
  timeLimit('time_limit'),
  exhausted('exhausted'),
  puzzleLimit('puzzle_limit'),

  /// A reason this app does not know yet.
  unknown('');

  const RaceFinishReason(this.wire);

  final String wire;

  /// Null for a JSON null (the room-wide `finished` carries no reason).
  static RaceFinishReason? fromWire(Object? value) {
    if (value == null) return null;
    for (final reason in values) {
      if (reason != unknown && reason.wire == value) return reason;
    }
    return unknown;
  }
}

/// Six Crockford base32 characters: `0-9 A-Z` without I, L, O and U.
const String kRaceCodeAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const int kRaceCodeLength = 6;

/// The longest name the room keeps; it trims anything longer.
const int kRaceMaxNameLength = 24;

/// [input] as a room code, the way the Worker reads one: case-insensitive,
/// hyphens and spaces ignored, O read as 0 and I/L as 1. Null when it is
/// still not six code characters.
String? normalizeRaceCode(String input) {
  final code = input
      .toUpperCase()
      .replaceAll(RegExp(r'[\s-]'), '')
      .replaceAll('O', '0')
      .replaceAll(RegExp('[IL]'), '1');
  if (code.length != kRaceCodeLength) return null;
  for (final unit in code.split('')) {
    if (!kRaceCodeAlphabet.contains(unit)) return null;
  }
  return code;
}

int _int(Object? value, [int fallback = 0]) => switch (value) {
  final int n => n,
  final double d when d.isFinite => d.round(),
  _ => fallback,
};

int? _intOrNull(Object? value) => switch (value) {
  final int n => n,
  final double d when d.isFinite => d.round(),
  _ => null,
};

bool _bool(Object? value) => value == true;

String _string(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;

String? _stringOrNull(Object? value) => value is String ? value : null;

List<String> _strings(Object? value) => value is List
    ? [
        for (final item in value)
          if (item is String) item,
      ]
    : const [];

List<Map<String, Object?>> _objects(Object? value) => value is List
    ? [
        for (final item in value)
          if (item is Map) item.cast<String, Object?>(),
      ]
    : const [];

/// One player as every other player sees them (`snapshot.players[]`).
@immutable
class RacePlayer {
  const RacePlayer({
    required this.id,
    required this.name,
    this.score = 0,
    this.mistakes = 0,
    this.level = 0,
    this.finished = false,
    this.ready = false,
    this.connected = false,
  });

  factory RacePlayer.fromJson(Map<String, Object?> json) => RacePlayer(
    id: _string(json['id']),
    name: _string(json['name'], 'Player'),
    score: _int(json['score']),
    mistakes: _int(json['mistakes']),
    level: _int(json['level']),
    finished: _bool(json['finished']),
    ready: _bool(json['ready']),
    connected: _bool(json['connected']),
  );

  /// Per-room pseudonymous id; never a user id.
  final String id;
  final String name;
  final int score;
  final int mistakes;

  /// Solves so far: the room's ladder level.
  final int level;
  final bool finished;
  final bool ready;
  final bool connected;

  @override
  bool operator ==(Object other) =>
      other is RacePlayer &&
      other.id == id &&
      other.name == name &&
      other.score == score &&
      other.mistakes == mistakes &&
      other.level == level &&
      other.finished == finished &&
      other.ready == ready &&
      other.connected == connected;

  @override
  int get hashCode =>
      Object.hash(id, name, score, mistakes, level, finished, ready, connected);
}

/// One line of the standings (`finished.results[]`).
@immutable
class RaceResult {
  const RaceResult({
    required this.rank,
    required this.id,
    required this.name,
    this.score = 0,
    this.mistakes = 0,
    this.level = 0,
    this.bestRating = 0,
    this.elapsedMs = 0,
    this.finished = false,
    this.finishReason,
    this.flames,
  });

  factory RaceResult.fromJson(Map<String, Object?> json) => RaceResult(
    rank: _int(json['rank']),
    id: _string(json['id']),
    name: _string(json['name'], 'Player'),
    score: _int(json['score']),
    mistakes: _int(json['mistakes']),
    level: _int(json['level']),
    bestRating: _int(json['bestRating']),
    elapsedMs: _int(json['elapsedMs']),
    finished: _bool(json['finished']),
    finishReason: RaceFinishReason.fromWire(json['finishReason']),
    flames: _intOrNull(json['flames']),
  );

  final int rank;
  final String id;
  final String name;
  final int score;
  final int mistakes;
  final int level;
  final int bestRating;

  /// Server time from the start to this player's finish (or to now).
  final int elapsedMs;
  final bool finished;
  final RaceFinishReason? finishReason;

  /// Flames this run earned, by the room's count. Null from a room that
  /// predates flames: the app then counts its own.
  final int? flames;
}

/// `GET /v1/races/{code}/results`: the room's standings, while it runs and
/// for a day after it finished. No credential: the code is the capability.
@immutable
class RaceRoomSummary {
  const RaceRoomSummary({
    required this.code,
    required this.state,
    required this.results,
    this.mode,
    this.multiplayer = false,
    this.startedAt,
    this.finishedAt,
  });

  factory RaceRoomSummary.fromJson(Map<String, Object?> json) =>
      RaceRoomSummary(
        code: _string(json['code']),
        mode: RaceMode.fromWire(json['mode']),
        multiplayer: _bool(json['multiplayer']),
        state: RaceRoomState.fromWire(json['state']),
        startedAt: _intOrNull(json['startedAt']),
        finishedAt: _intOrNull(json['finishedAt']),
        results: [
          for (final r in _objects(json['results'])) RaceResult.fromJson(r),
        ],
      );

  final String code;
  final RaceMode? mode;
  final bool multiplayer;
  final RaceRoomState state;
  final int? startedAt;
  final int? finishedAt;
  final List<RaceResult> results;

  /// The row of the player whose room id is [id]; null without one.
  RaceResult? resultFor(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final r in results) {
      if (r.id == id) return r;
    }
    return null;
  }
}

/// A message from the room.
sealed class RaceServerMessage {
  const RaceServerMessage();

  /// Decodes one text frame; null when it is not a JSON object.
  static RaceServerMessage? decode(String frame) {
    Object? data;
    try {
      data = jsonDecode(frame);
    } catch (_) {
      return null;
    }
    if (data is! Map) return null;
    return fromJson(data.cast<String, Object?>());
  }

  static RaceServerMessage fromJson(Map<String, Object?> json) {
    final type = json['type'];
    return switch (type) {
      'snapshot' => RaceSnapshot.fromJson(json),
      'puzzle' => RacePuzzleMessage.fromJson(json),
      'verdict' => RaceVerdict.fromJson(json),
      'finished' => RaceFinished.fromJson(json),
      'pong' => RacePong(
        serverNow: _intOrNull(json['serverNow']),
        t: _intOrNull(json['t']),
      ),
      'error' => RaceError(
        code: _string(json['code'], 'unknown'),
        expectedIndex: _intOrNull(json['expectedIndex']),
        expectedPly: _intOrNull(json['expectedPly']),
        retryAfterMs: _intOrNull(json['retryAfterMs']),
      ),
      _ => RaceUnknownMessage(_string(type)),
    };
  }
}

/// The room as it stands; sent on connect and whenever it changes. Carries
/// no puzzle data.
class RaceSnapshot extends RaceServerMessage {
  const RaceSnapshot({
    required this.serverNow,
    required this.code,
    required this.mode,
    required this.multiplayer,
    required this.state,
    required this.you,
    required this.hostId,
    required this.lives,
    required this.countdownEndsAt,
    required this.startedAt,
    required this.players,
    this.startRating,
    this.maxRating,
  });

  factory RaceSnapshot.fromJson(Map<String, Object?> json) => RaceSnapshot(
    serverNow: _int(json['serverNow']),
    code: _string(json['code']),
    mode: RaceMode.fromWire(json['mode']),
    multiplayer: _bool(json['multiplayer']),
    state: RaceRoomState.fromWire(json['state']),
    you: _stringOrNull(json['you']),
    hostId: _string(json['hostId']),
    lives: _intOrNull(json['lives']),
    countdownEndsAt: _intOrNull(json['countdownEndsAt']),
    startedAt: _intOrNull(json['startedAt']),
    players: [
      for (final p in _objects(json['players'])) RacePlayer.fromJson(p),
    ],
    startRating: _intOrNull(json['startRating']),
    maxRating: _intOrNull(json['maxRating']),
  );

  final int serverNow;
  final String code;
  final RaceMode? mode;
  final bool multiplayer;
  final RaceRoomState state;

  /// This socket's public player id.
  final String? you;
  final String hostId;

  /// Lives a Survival run starts with; null in Infinite.
  final int? lives;
  final int? countdownEndsAt;
  final int? startedAt;
  final List<RacePlayer> players;

  /// Where the room's ladder starts. Null from a room that predates it.
  final int? startRating;

  /// The ladder's ceiling; null without one (or from an older room).
  final int? maxRating;
}

/// The player's next (or, after a reconnect, current) puzzle. Carries no
/// solution.
class RacePuzzleMessage extends RaceServerMessage {
  const RacePuzzleMessage({
    required this.index,
    required this.fen,
    required this.sideToMove,
    required this.setupMove,
    required this.rating,
    required this.level,
    required this.ply,
    required this.progress,
  });

  factory RacePuzzleMessage.fromJson(Map<String, Object?> json) =>
      RacePuzzleMessage(
        index: _int(json['index']),
        fen: _string(json['fen']),
        sideToMove: _string(json['sideToMove'], 'white'),
        setupMove: _string(json['setupMove']),
        rating: _int(json['rating']),
        level: _int(json['level']),
        ply: _int(json['ply'], 1),
        progress: _strings(json['progress']),
      );

  final int index;

  /// The position BEFORE the opponent's setup move.
  final String fen;

  /// The solver's colour: `white` or `black`.
  final String sideToMove;
  final String setupMove;
  final int rating;
  final int level;

  /// Where in the line the player is: 1 is their first move, then 3, 5, ...
  final int ply;

  /// Moves of this puzzle already played or shown (for a resume).
  final List<String> progress;
}

/// The room's judgement of a move.
class RaceVerdict extends RaceServerMessage {
  const RaceVerdict({
    required this.index,
    required this.correct,
    required this.complete,
    this.expectedReply,
    this.nextPly,
    this.solutionRevealed = const [],
    this.puzzleId,
    this.themes = const [],
    required this.score,
    required this.mistakes,
    required this.level,
    required this.elapsedMs,
    required this.serverNow,
  });

  factory RaceVerdict.fromJson(Map<String, Object?> json) => RaceVerdict(
    index: _int(json['index']),
    correct: _bool(json['correct']),
    complete: _bool(json['complete']),
    expectedReply: _stringOrNull(json['expectedReply']),
    nextPly: _intOrNull(json['nextPly']),
    solutionRevealed: _strings(json['solutionRevealed']),
    puzzleId: _intOrNull(json['puzzleId']),
    themes: _strings(json['themes']),
    score: _int(json['score']),
    mistakes: _int(json['mistakes']),
    level: _int(json['level']),
    elapsedMs: _int(json['elapsedMs']),
    serverNow: _int(json['serverNow']),
  );

  final int index;
  final bool correct;

  /// The puzzle is over (solved or failed); the next one follows.
  final bool complete;

  /// Mid-line only: the opponent's next move, to play before the player's.
  final String? expectedReply;
  final int? nextPly;

  /// When complete: every move after the setup move.
  final List<String> solutionRevealed;
  final int? puzzleId;
  final List<String> themes;
  final int score;
  final int mistakes;
  final int level;

  /// The authoritative race clock: server time since the start.
  final int elapsedMs;
  final int serverNow;
}

/// A run ended: this player's ([roomFinished] false) or the whole room's.
class RaceFinished extends RaceServerMessage {
  const RaceFinished({
    required this.playerId,
    required this.reason,
    required this.roomFinished,
    required this.results,
    required this.serverNow,
  });

  factory RaceFinished.fromJson(Map<String, Object?> json) => RaceFinished(
    playerId: _stringOrNull(json['playerId']),
    reason: RaceFinishReason.fromWire(json['reason']),
    roomFinished: _bool(json['roomFinished']),
    results: [
      for (final r in _objects(json['results'])) RaceResult.fromJson(r),
    ],
    serverNow: _int(json['serverNow']),
  );

  final String? playerId;
  final RaceFinishReason? reason;
  final bool roomFinished;
  final List<RaceResult> results;
  final int serverNow;
}

/// The answer to a ping. The runtime's own answer to a bare heartbeat has
/// neither field.
class RacePong extends RaceServerMessage {
  const RacePong({this.serverNow, this.t});

  final int? serverNow;

  /// The client clock the ping carried.
  final int? t;
}

class RaceError extends RaceServerMessage {
  const RaceError({
    required this.code,
    this.expectedIndex,
    this.expectedPly,
    this.retryAfterMs,
  });

  final String code;
  final int? expectedIndex;
  final int? expectedPly;
  final int? retryAfterMs;
}

class RaceUnknownMessage extends RaceServerMessage {
  const RaceUnknownMessage(this.type);

  final String type;
}

/// Frames the app sends. Each is one JSON object under the room's 512
/// character limit.
abstract final class RaceClientMessage {
  /// The heartbeat the runtime answers without waking the room. Exactly
  /// these bytes: any other spelling is billed as a room request.
  static const String heartbeat = '{"type":"ping"}';

  static String join(String? name) {
    final trimmed = name?.trim() ?? '';
    final runes = trimmed.runes.take(kRaceMaxNameLength).toList();
    return jsonEncode({
      'type': 'join',
      'name': runes.isEmpty ? null : String.fromCharCodes(runes),
    });
  }

  static String ready(bool ready) =>
      jsonEncode({'type': 'ready', 'ready': ready});

  static String start() => jsonEncode({'type': 'start'});

  static String move({
    required int puzzleIndex,
    required String uci,
    required int ply,
  }) => jsonEncode({
    'type': 'move',
    'puzzleIndex': puzzleIndex,
    'uci': uci,
    'ply': ply,
  });

  static String stop() => jsonEncode({'type': 'stop'});

  /// A ping the room itself answers with its clock: `pong.serverNow` and
  /// this [t] back, for the clock offset.
  static String clockPing(int t) => jsonEncode({'type': 'ping', 't': t});
}

/// `POST /v1/races` answer.
@immutable
class RaceCreated {
  const RaceCreated({
    required this.code,
    required this.mode,
    required this.multiplayer,
    required this.wsUrl,
    this.seat,
  });

  /// Null when the body is not a room.
  static RaceCreated? fromJson(Map<String, Object?> json) {
    final code = normalizeRaceCode(_string(json['code']));
    final mode = RaceMode.fromWire(json['mode']);
    final wsUrl = _string(json['wsUrl']);
    final uri = Uri.tryParse(wsUrl);
    if (code == null ||
        mode == null ||
        uri == null ||
        (uri.scheme != 'ws' && uri.scheme != 'wss')) {
      return null;
    }
    final seat = _stringOrNull(json['seat']);
    return RaceCreated(
      code: code,
      mode: mode,
      multiplayer: _bool(json['multiplayer']),
      wsUrl: uri,
      seat: seat == null || seat.isEmpty ? null : seat,
    );
  }

  final String code;
  final RaceMode mode;
  final bool multiplayer;
  final Uri wsUrl;

  /// A guest's one credential for this room (single-player only).
  final String? seat;
}

/// `GET /v1/me/stats`: a signed-in player's kept Puzzle Race record, as the
/// rooms credited it (every device, every room).
@immutable
class RaceServerStats {
  const RaceServerStats({
    this.flames = 0,
    this.racesPlayed = 0,
    this.solved = 0,
    this.survivalBest = 0,
    this.infiniteBest = 0,
    this.bestStreak = 0,
  });

  factory RaceServerStats.fromJson(Map<String, Object?> json) {
    int count(String key) => math.max(0, _int(json[key]));
    return RaceServerStats(
      flames: count('flames'),
      racesPlayed: count('racesPlayed'),
      solved: count('solved'),
      survivalBest: count('survivalBest'),
      infiniteBest: count('infiniteBest'),
      bestStreak: count('bestStreak'),
    );
  }

  final int flames;
  final int racesPlayed;
  final int solved;
  final int survivalBest;
  final int infiniteBest;
  final int bestStreak;

  @override
  bool operator ==(Object other) =>
      other is RaceServerStats &&
      other.flames == flames &&
      other.racesPlayed == racesPlayed &&
      other.solved == solved &&
      other.survivalBest == survivalBest &&
      other.infiniteBest == infiniteBest &&
      other.bestStreak == bestStreak;

  @override
  int get hashCode => Object.hash(
    flames,
    racesPlayed,
    solved,
    survivalBest,
    infiniteBest,
    bestStreak,
  );
}
