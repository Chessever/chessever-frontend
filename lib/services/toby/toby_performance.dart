/// Toby's estimate of the level each side played at, for the Game Report.
///
/// Where it comes from, in order: the analysis Worker's report JSON
/// (`tobyPerformance`, kept in [tobyPerformanceMemory] when the report is
/// parsed), the report store (saved beside the report), and otherwise
/// Gamebase's `POST /api/toby-performance`, polled on 202 for up to
/// [tobyPerformanceBudget]. The values sent with that request come from the
/// report's own evaluations ([tobyPerformanceValues]), so Gamebase does not
/// have to search the game again.
///
/// An estimate depends on more than the moves: the ratings, cadence and
/// venue Gamebase derives from the game facts, and the values sent. So every
/// cached or stored estimate carries the [TobyPerformanceRequest.basis] it was
/// computed for, and is served only to a request with the same basis.
///
/// Nothing here blocks the report: the row simply shows a placeholder until
/// an estimate arrives, and a settled placeholder when none can be had.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report_store.dart';
import 'package:chessever2/services/toby/toby_prediction.dart';

/// The row's label in the report's player summary.
const String kTobyPerformanceLabel = 'Toby Rating';

/// What the row means, for its tooltip and screen readers.
const String kTobyPerformanceDescription =
    "Toby's estimate of the level each side played at, from how human the "
    'moves were.';

/// Credit owed whenever a Toby result is shown.
const String kTobyPerformanceAttribution = kTobyAttribution;

/// The model this build expects. A stored estimate from another model is
/// read again from Gamebase.
const String kTobyPerformanceModel = 'toby2-level-v1';

/// How long the report waits for an estimate, polls and retries included,
/// before it gives up and settles the row on its placeholder.
const Duration tobyPerformanceBudget = Duration(seconds: 120);

/// A mate in the values sent to Gamebase, in the mover's terms. Every score
/// is clamped to it.
const int tobyPerformanceMateCp = 10000;

/// Estimates kept for instant revisits in this window.
const int tobyPerformanceMemoryCapacity = 64;

const List<Duration> _failureBackoff = <Duration>[
  Duration(seconds: 1),
  Duration(seconds: 2),
  Duration(seconds: 4),
];
const Duration _pendingFallbackWait = Duration(seconds: 2);
const Duration _maxPendingWait = Duration(seconds: 30);
const int _maxJitterMs = 250;
final math.Random _jitter = math.Random();

/// How Gamebase arrived at a side's estimate.
enum TobyPerformanceMethod {
  /// From the player's known rating and the moves (an over-the-board game).
  rated('rated'),

  /// From the moves alone.
  moves('moves');

  const TobyPerformanceMethod(this.wire);

  final String wire;

  static TobyPerformanceMethod? fromWire(Object? value) {
    for (final method in values) {
      if (method.wire == value) return method;
    }
    return null;
  }
}

/// One side's estimate.
@immutable
class TobyPerformanceSide {
  const TobyPerformanceSide({
    required this.rating,
    required this.display,
    required this.method,
    required this.moves,
    required this.sd,
  });

  final int rating;

  /// What the report shows: "2480", "2500+", "under 1600".
  final String display;
  final TobyPerformanceMethod method;

  /// Moves the estimate counted.
  final int moves;

  /// Its standard deviation, in rating points.
  final double sd;

  /// Null for anything that is not a well-formed side.
  static TobyPerformanceSide? fromJson(Object? json) {
    if (json is! Map) return null;
    final rating = _whole(json['rating']);
    final display = json['display'];
    final method = TobyPerformanceMethod.fromWire(json['method']);
    final moves = _whole(json['moves']);
    final sd = json['sd'];
    if (rating == null ||
        display is! String ||
        display.trim().isEmpty ||
        method == null ||
        moves == null ||
        moves < 0 ||
        sd is! num ||
        !sd.isFinite) {
      return null;
    }
    return TobyPerformanceSide(
      rating: rating,
      display: display.trim(),
      method: method,
      moves: moves,
      sd: sd.toDouble(),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'rating': rating,
    'display': display,
    'method': method.wire,
    'moves': moves,
    'sd': sd,
  };

  @override
  bool operator ==(Object other) =>
      other is TobyPerformanceSide &&
      other.rating == rating &&
      other.display == display &&
      other.method == method &&
      other.moves == moves &&
      other.sd == sd;

  @override
  int get hashCode => Object.hash(rating, display, method, moves, sd);
}

/// The estimate for a whole game: Gamebase's 200 body, and the report's
/// `tobyPerformance` field.
@immutable
class TobyPerformance {
  const TobyPerformance({
    required this.model,
    required this.cadence,
    this.white,
    this.black,
  });

  final String model;
  final TobyCadence cadence;

  /// Null when that side played too few counted moves.
  final TobyPerformanceSide? white;
  final TobyPerformanceSide? black;

  /// Whether there is anything to show.
  bool get hasEstimate => white != null || black != null;

  /// Null unless [json] names a model and a known cadence. A malformed side
  /// reads as a side without an estimate.
  static TobyPerformance? fromJson(Object? json) {
    if (json is! Map) return null;
    final model = json['model'];
    final cadence = TobyCadence.fromWire(json['cadence']);
    if (model is! String || model.isEmpty || cadence == null) return null;
    return TobyPerformance(
      model: model,
      cadence: cadence,
      white: TobyPerformanceSide.fromJson(json['white']),
      black: TobyPerformanceSide.fromJson(json['black']),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'model': model,
    'cadence': cadence.wire,
    'white': white?.toJson(),
    'black': black?.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is TobyPerformance &&
      other.model == model &&
      other.cadence == cadence &&
      other.white == white &&
      other.black == black;

  @override
  int get hashCode => Object.hash(model, cadence, white, black);
}

/// The two scores Gamebase reads one move with, in the mover's terms.
typedef TobyMoveValues = ({int best, int played});

/// The values for every move of [moves] (the game's main line in UCI) from
/// [report]'s evaluations, null where an evaluation is missing.
///
/// Move i is played from position i. With sign +1 when White moved and -1
/// when Black did: best = sign × score(position i), played = sign ×
/// score(position i + 1), except that the played move's own MultiPV line at
/// position i is preferred when the report has it (it was searched from the
/// same root as the best line). A mate is ±[tobyPerformanceMateCp]; every
/// score is clamped to it.
List<TobyMoveValues?> tobyPerformanceValues(
  GameAnalysisReport report,
  List<String> moves,
) {
  final positions = report.positions;
  return <TobyMoveValues?>[
    for (var i = 0; i < moves.length; i++)
      if (i + 1 >= positions.length)
        null
      else
        _valuesAt(
          positions[i],
          positions[i + 1],
          moves[i],
          whiteMoved:
              _whiteToMove(positions[i].fen) ??
              (i < report.moves.length ? report.moves[i].isWhite : i.isEven),
        ),
  ];
}

TobyMoveValues? _valuesAt(
  GameReportPosition before,
  GameReportPosition after,
  String uci, {
  required bool whiteMoved,
}) {
  if (before.lines.isEmpty) return null;
  final best = _whiteScore(before.bestLine, whiteToMove: whiteMoved);
  final playedLine = _lineStartingWith(before, uci);
  final played = playedLine != null
      ? _whiteScore(playedLine, whiteToMove: whiteMoved)
      : after.lines.isEmpty
      ? null
      : _whiteScore(after.bestLine, whiteToMove: !whiteMoved);
  if (best == null || played == null) return null;
  final sign = whiteMoved ? 1 : -1;
  return (best: _clampCp(sign * best), played: _clampCp(sign * played));
}

GameReportLine? _lineStartingWith(GameReportPosition position, String uci) {
  final alternate = GamebaseRepository.alternateCastlingUci(uci);
  for (final line in position.lines) {
    if (line.moves.isEmpty) continue;
    final first = line.moves.first;
    if (first == uci || (alternate != null && first == alternate)) {
      return line;
    }
  }
  return null;
}

/// A line's score in White's terms (the report's convention), or null when
/// the line carries none. A mate is ±[tobyPerformanceMateCp]; mate 0 means
/// the side to move is mated.
int? _whiteScore(GameReportLine line, {required bool whiteToMove}) {
  final mate = line.mate;
  if (mate != null) {
    if (mate > 0) return tobyPerformanceMateCp;
    if (mate < 0) return -tobyPerformanceMateCp;
    return whiteToMove ? -tobyPerformanceMateCp : tobyPerformanceMateCp;
  }
  return line.centipawns;
}

int _clampCp(int value) =>
    value.clamp(-tobyPerformanceMateCp, tobyPerformanceMateCp);

bool? _whiteToMove(String fen) {
  final fields = fen.trim().split(RegExp(r'\s+'));
  if (fields.length < 2) return null;
  return switch (fields[1]) {
    'w' => true,
    'b' => false,
    _ => null,
  };
}

/// The game facts a Toby reading takes from the board's source game rather
/// than from the PGN headers: the players' ratings (already falling back to
/// `WhiteElo` / `BlackElo`) and the source's speed category. The Game Report
/// sends the same, so its estimate reads the game as the Toby bar does.
typedef TobyGameFacts = ({
  int? whiteRating,
  int? blackRating,
  String? category,
});

/// One game to estimate, with the raw game facts Gamebase derives the
/// cadence, rating pool and venue from (the same facts as a Toby reading).
///
/// Compared by value ([cacheKey]), so it can key a provider family.
@immutable
class TobyPerformanceRequest {
  TobyPerformanceRequest({
    String? startFen,
    required List<String> moves,
    List<TobyMoveValues?>? values,
    int? whiteRating,
    int? blackRating,
    String? timeControl,
    String? category,
    String? site,
    String? event,
  }) : _facts = TobyRequest(
         startFen: startFen,
         moves: moves,
         whiteRating: whiteRating,
         blackRating: blackRating,
         timeControl: timeControl,
         category: category,
         site: site,
         event: event,
       ),
       values =
           values == null ||
               values.length != moves.length ||
               values.every((value) => value == null)
           ? null
           : List<TobyMoveValues?>.unmodifiable(values);

  /// The request for [report] of the game whose main line is [moves].
  factory TobyPerformanceRequest.forReport(
    GameAnalysisReport report, {
    String? startFen,
    required List<String> moves,
    int? whiteRating,
    int? blackRating,
    String? timeControl,
    String? category,
    String? site,
    String? event,
  }) => TobyPerformanceRequest(
    startFen: startFen,
    moves: moves,
    values: report.positions.length == moves.length + 1
        ? tobyPerformanceValues(report, moves)
        : null,
    whiteRating: whiteRating,
    blackRating: blackRating,
    timeControl: timeControl,
    category: category,
    site: site,
    event: event,
  );

  /// Normalises the game facts exactly as a Toby reading does.
  final TobyRequest _facts;

  /// The values sent with the game; null when the report had none to give,
  /// so Gamebase searches the game itself.
  final List<TobyMoveValues?>? values;

  String? get startFen => _facts.startFen;
  List<String> get moves => _facts.moves;

  /// Whether Gamebase accepts this request at all.
  bool get isSupported => moves.isNotEmpty && _facts.isSupported;

  Map<String, Object?> toBody() => <String, Object?>{
    'version': 1,
    if (startFen != null) 'fen': startFen,
    'moves': moves,
    if (values case final values?)
      'values': <Object?>[
        for (final value in values)
          value == null
              ? null
              : <String, int>{'best': value.best, 'played': value.played},
      ],
    'game': <String, Object?>{
      'whiteRating': _facts.whiteRating,
      'blackRating': _facts.blackRating,
      'timeControl': _facts.timeControl,
      'category': _facts.category,
      'site': _facts.site,
      'event': _facts.event,
    },
  };

  late final String cacheKey = jsonEncode(toBody());

  /// What an estimate for this request was computed from: the start, the
  /// moves, the values and the game facts. Cached and stored estimates are
  /// keyed by it, so another game with the same moves, edited headers or a
  /// re-analysed report never inherits an estimate made for something else.
  late final String basis = sha256.convert(utf8.encode(cacheKey)).toString();

  /// The ratings Gamebase would read, as normalised for a Toby reading.
  int? get whiteRating => _facts.whiteRating;
  int? get blackRating => _facts.blackRating;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TobyPerformanceRequest && other.cacheKey == cacheKey;

  @override
  int get hashCode => cacheKey.hashCode;
}

/// What one poll's answer means for the loop.
sealed class TobyPerformanceReply {
  const TobyPerformanceReply();
}

final class TobyPerformanceReady extends TobyPerformanceReply {
  const TobyPerformanceReady(this.performance);

  final TobyPerformance performance;
}

/// Still being computed: poll again after [wait].
final class TobyPerformancePending extends TobyPerformanceReply {
  const TobyPerformancePending(this.wait, {this.done, this.total});

  final Duration wait;
  final int? done;
  final int? total;
}

/// 401 or 403: Gamebase's access setting refused the reader.
final class TobyPerformanceDenied extends TobyPerformanceReply {
  const TobyPerformanceDenied({required this.signIn});

  final bool signIn;
}

final class TobyPerformanceFailed extends TobyPerformanceReply {
  const TobyPerformanceFailed({required this.retryable});

  final bool retryable;
}

/// Reads one poll's answer. Pure, so the protocol can be tested apart from
/// the loop.
TobyPerformanceReply interpretTobyPerformanceReply(GamebaseTobyReply reply) {
  final status = reply.statusCode;
  if (status == null) return const TobyPerformanceFailed(retryable: true);
  if (status == 401 || status == 403) {
    return TobyPerformanceDenied(
      signIn: status == 401 || reply.data?['error'] == 'unauthorized',
    );
  }
  if (status == 200) {
    final performance = TobyPerformance.fromJson(reply.data);
    return performance == null
        ? const TobyPerformanceFailed(retryable: false)
        : TobyPerformanceReady(performance);
  }
  if (status == 202) {
    final progress = reply.data?['progress'];
    final wait = reply.retryAfter ?? _pendingFallbackWait;
    return TobyPerformancePending(
      wait > _maxPendingWait ? _maxPendingWait : wait,
      done: progress is Map ? _whole(progress['done']) : null,
      total: progress is Map ? _whole(progress['total']) : null,
    );
  }
  if (status == 429 || status >= 500) {
    return const TobyPerformanceFailed(retryable: true);
  }
  return const TobyPerformanceFailed(retryable: false);
}

/// Estimates kept for this window, least recently used first.
///
/// An estimate Gamebase returned is kept under the report's fingerprint and
/// the request's [TobyPerformanceRequest.basis], so other game facts or
/// values never see it. The analysis Worker's estimate ([storeFromReport]) is
/// kept under the fingerprint and the ratings the Worker was sent: it is
/// served only to a request with the same ratings. Reports on this device are
/// not kept per account ([GameAnalysisReportStore]), so neither is this.
class TobyPerformanceMemory {
  TobyPerformanceMemory(this.capacity);

  final int capacity;
  final LinkedHashMap<String, TobyPerformance> _entries =
      LinkedHashMap<String, TobyPerformance>();

  static String _queryKey(TobyPerformanceQuery query) =>
      'q::${query.fingerprint}::${query.request.basis}';

  static String _reportKey(
    String fingerprint,
    int? whiteRating,
    int? blackRating,
  ) =>
      'r::$fingerprint::${tobyRating(whiteRating)}::${tobyRating(blackRating)}';

  /// The estimate for [query], or null.
  TobyPerformance? lookup(TobyPerformanceQuery query) =>
      _touch(_queryKey(query)) ??
      _touch(
        _reportKey(
          query.fingerprint,
          query.request.whiteRating,
          query.request.blackRating,
        ),
      );

  /// Keeps what Gamebase returned for [query].
  void store(TobyPerformanceQuery query, TobyPerformance performance) =>
      _put(_queryKey(query), performance);

  /// Keeps the analysis Worker's estimate for the report [fingerprint], made
  /// with the ratings the Worker was sent.
  void storeFromReport(
    String fingerprint,
    TobyPerformance performance, {
    int? whiteRating,
    int? blackRating,
  }) => _put(_reportKey(fingerprint, whiteRating, blackRating), performance);

  TobyPerformance? _touch(String key) {
    final value = _entries.remove(key);
    if (value != null) _entries[key] = value;
    return value;
  }

  void _put(String key, TobyPerformance performance) {
    _entries.remove(key);
    _entries[key] = performance;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  void clear() => _entries.clear();
}

/// Shared by every report in this window.
final TobyPerformanceMemory tobyPerformanceMemory = TobyPerformanceMemory(
  tobyPerformanceMemoryCapacity,
);

/// The store estimates are saved beside. Overridden in tests.
final tobyPerformanceStoreProvider = Provider<GameAnalysisReportStore>(
  (ref) => GameAnalysisReportStore.instance,
);

/// One report asking for its estimate.
@immutable
class TobyPerformanceQuery {
  const TobyPerformanceQuery({
    required this.fingerprint,
    required this.request,
  });

  /// The report's fingerprint: what the estimate is saved under.
  final String fingerprint;
  final TobyPerformanceRequest request;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TobyPerformanceQuery &&
          other.fingerprint == fingerprint &&
          other.request == request;

  @override
  int get hashCode => Object.hash(fingerprint, request);
}

enum TobyPerformanceStatus {
  /// Looking in the store, or waiting for Gamebase.
  loading,

  /// [TobyPerformanceState.performance] holds the estimate.
  ready,

  /// No estimate for this report, known before anything was asked: not a
  /// game Gamebase reads, or one with no side to estimate. The row is
  /// hidden.
  unavailable,

  /// Asked, and no estimate came: refused, failed, out of budget, or no side
  /// to estimate. The row that showed its placeholder while loading keeps
  /// it, so the summary never shrinks under the reader.
  failed,
}

@immutable
class TobyPerformanceState {
  const TobyPerformanceState(this.status, {this.performance});

  const TobyPerformanceState.ready(TobyPerformance this.performance)
    : status = TobyPerformanceStatus.ready;

  static const TobyPerformanceState loading = TobyPerformanceState(
    TobyPerformanceStatus.loading,
  );
  static const TobyPerformanceState unavailable = TobyPerformanceState(
    TobyPerformanceStatus.unavailable,
  );
  static const TobyPerformanceState failed = TobyPerformanceState(
    TobyPerformanceStatus.failed,
  );

  final TobyPerformanceStatus status;
  final TobyPerformance? performance;

  @override
  bool operator ==(Object other) =>
      other is TobyPerformanceState &&
      other.status == status &&
      other.performance == performance;

  @override
  int get hashCode => Object.hash(status, performance);
}

/// The estimate for one report. Watched while the completed report is on
/// screen; auto-disposed, so leaving the report cancels the request.
final tobyPerformanceProvider = NotifierProvider.autoDispose
    .family<
      TobyPerformanceNotifier,
      TobyPerformanceState,
      TobyPerformanceQuery
    >(TobyPerformanceNotifier.new);

class TobyPerformanceNotifier
    extends
        AutoDisposeFamilyNotifier<TobyPerformanceState, TobyPerformanceQuery> {
  int _run = 0;
  CancelToken? _inFlight;
  Timer? _sleepTimer;
  Completer<void>? _sleepDone;
  Timer? _budget;

  @override
  TobyPerformanceState build(TobyPerformanceQuery query) {
    ref.onDispose(_halt);
    final known = tobyPerformanceMemory.lookup(query);
    if (known != null) {
      // The Worker's report carried it, or another view fetched it: keep it
      // with the stored report too.
      _persist(known);
      // Same state as when the estimate first came back, so a report with
      // no side to estimate looks the same on every view.
      return _settled(known);
    }
    if (!query.request.isSupported) return TobyPerformanceState.unavailable;
    unawaited(_load(++_run));
    return TobyPerformanceState.loading;
  }

  /// Settles a request that showed the loading placeholder.
  static TobyPerformanceState _settled(TobyPerformance performance) =>
      performance.hasEstimate
      ? TobyPerformanceState.ready(performance)
      : TobyPerformanceState.failed;

  Future<void> _load(int run) async {
    bool live() => run == _run;
    TobyPerformance? stored;
    try {
      stored = await ref
          .read(tobyPerformanceStoreProvider)
          .loadTobyPerformance(arg.fingerprint, basis: arg.request.basis);
    } catch (_) {
      stored = null;
    }
    if (!live()) return;
    if (stored != null) {
      tobyPerformanceMemory.store(arg, stored);
      _finish(_settled(stored));
      return;
    }
    await _poll(run);
  }

  Future<void> _poll(int run) async {
    bool live() => run == _run;
    final repository = ref.read(gamebaseRepositoryProvider);
    if (!repository.hasApiKey) {
      // No proxy key in this build: nothing can ever be sent, so settle now
      // instead of retrying for the whole budget.
      _finish(TobyPerformanceState.failed);
      return;
    }
    final body = arg.request.toBody();
    _budget = Timer(tobyPerformanceBudget, () => _giveUp(run));
    var failures = 0;
    var recheckAccess = false;
    var recheckedAccess = false;
    while (live()) {
      final cancelToken = CancelToken();
      _inFlight = cancelToken;
      final reply = await repository.getTobyPerformance(
        body,
        cancelToken,
        recheckAccess: recheckAccess,
      );
      if (!live()) return;
      _inFlight = null;
      recheckAccess = false;
      switch (interpretTobyPerformanceReply(reply)) {
        case TobyPerformanceReady(:final performance):
          tobyPerformanceMemory.store(arg, performance);
          _persist(performance);
          _finish(_settled(performance));
          return;
        case TobyPerformancePending(:final wait):
          failures = 0;
          await _sleep(
            wait + Duration(milliseconds: _jitter.nextInt(_maxJitterMs + 1)),
          );
        case TobyPerformanceDenied(signIn: false)
            when !recheckedAccess && ref.read(tobyReaderHasPremiumProvider):
          // Membership can lag behind a purchase on either side: one fresh
          // re-check, never a loop.
          recheckedAccess = true;
          recheckAccess = true;
        case TobyPerformanceDenied():
        case TobyPerformanceFailed(retryable: false):
          _finish(TobyPerformanceState.failed);
          return;
        case TobyPerformanceFailed():
          await _sleep(
            _failureBackoff[math.min(failures, _failureBackoff.length - 1)],
          );
          failures++;
      }
    }
  }

  void _persist(TobyPerformance performance) {
    final store = ref.read(tobyPerformanceStoreProvider);
    unawaited(
      store
          .saveTobyPerformance(
            arg.fingerprint,
            performance,
            basis: arg.request.basis,
          )
          .catchError((Object _) {}),
    );
  }

  void _finish(TobyPerformanceState next) {
    _budget?.cancel();
    _budget = null;
    state = next;
  }

  void _giveUp(int run) {
    if (run != _run) return;
    _halt();
    state = TobyPerformanceState.failed;
  }

  void _halt() {
    _run++;
    _budget?.cancel();
    _budget = null;
    _inFlight?.cancel();
    _inFlight = null;
    _wake();
  }

  void _wake() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    final sleeping = _sleepDone;
    _sleepDone = null;
    if (sleeping != null && !sleeping.isCompleted) sleeping.complete();
  }

  Future<void> _sleep(Duration duration) {
    final done = Completer<void>();
    _sleepDone = done;
    _sleepTimer = Timer(duration, () {
      _sleepTimer = null;
      _sleepDone = null;
      if (!done.isCompleted) done.complete();
    });
    return done.future;
  }
}

int? _whole(Object? value) {
  if (value is int) return value;
  if (value is double && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  return null;
}

/// The query for the completed [report] of [game] (the board's game, its
/// PGN headers in [ChessGame.metadata]), or null when Toby has nothing to
/// read: no moves, a report of another game, or a variant Toby does not read.
///
/// The game facts are the board's Toby reading's: [whiteRating] and
/// [blackRating] are the game's own ratings, falling back to `WhiteElo` /
/// `BlackElo`; [category] is the game's speed label; `TimeControl`, `Site`
/// and `Event` come from the headers.
TobyPerformanceQuery? tobyPerformanceQueryForReport(
  GameAnalysisReport report,
  ChessGame game, {
  int? whiteRating,
  int? blackRating,
  String? category,
}) {
  if (game.mainline.isEmpty) return null;
  if (report.fingerprint != gameReportFingerprint(game)) return null;
  String? header(String key) {
    final value = game.metadata[key];
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  if (!tobyReadsVariant(header('Variant'))) return null;
  int? rating(int? own, String? elo) =>
      tobyRating(own) ?? tobyRating(int.tryParse(elo ?? ''));
  return TobyPerformanceQuery(
    fingerprint: report.fingerprint,
    request: TobyPerformanceRequest.forReport(
      report,
      startFen: game.startingFen,
      moves: [for (final move in game.mainline) move.uci.trim().toLowerCase()],
      whiteRating: rating(whiteRating, header('WhiteElo')),
      blackRating: rating(blackRating, header('BlackElo')),
      timeControl: header('TimeControl'),
      category: category,
      site: header('Site'),
      event: header('Event'),
    ),
  );
}

/// The placeholder a Toby rating cell holds while there is no number.
const String kTobyRatingPlaceholder = '\u2014';

/// What the Toby rating row shows, or null when it is hidden: nothing asked,
/// or known up front to have no estimate. While Gamebase is still reading the
/// game both cells hold the placeholder. A request that then ends without an
/// estimate keeps the placeholder rather than removing the row, so the summary
/// never shrinks under the reader; a side with too few moves to estimate holds
/// it for good.
({String white, String black, bool loading})? tobyRatingCells(
  TobyPerformanceState? state,
) {
  const placeholder = kTobyRatingPlaceholder;
  if (state == null) return null;
  switch (state.status) {
    case TobyPerformanceStatus.loading:
      return (white: placeholder, black: placeholder, loading: true);
    case TobyPerformanceStatus.unavailable:
      return null;
    case TobyPerformanceStatus.failed:
      return (white: placeholder, black: placeholder, loading: false);
    case TobyPerformanceStatus.ready:
      final performance = state.performance;
      if (performance == null || !performance.hasEstimate) return null;
      return (
        white: performance.white?.display ?? placeholder,
        black: performance.black?.display ?? placeholder,
        loading: false,
      );
  }
}

/// The row as a screen reader hears it: the state in words, never the
/// placeholder glyph.
String tobyRatingSemanticsLabel(
  TobyPerformanceState? state, {
  required String white,
  required String black,
}) {
  const unavailable = 'not available';
  final String whiteValue;
  final String blackValue;
  switch (state?.status) {
    case TobyPerformanceStatus.loading:
      whiteValue = 'loading';
      blackValue = 'loading';
    case TobyPerformanceStatus.ready:
      whiteValue = state?.performance?.white?.display ?? unavailable;
      blackValue = state?.performance?.black?.display ?? unavailable;
    case TobyPerformanceStatus.unavailable:
    case TobyPerformanceStatus.failed:
    case null:
      whiteValue = unavailable;
      blackValue = unavailable;
  }
  return '$kTobyPerformanceLabel: $white $whiteValue, $black $blackValue. '
      '$kTobyPerformanceDescription $kTobyPerformanceAttribution';
}
