/// Whole-game reports produced by the `chessever-analysis` Worker.
///
/// The *classifier* is identical: the service's `container/dart/lib/vendor/` is
/// a checksummed copy of this repo's own algorithm files, and it asks the same
/// gamebase the same question to find book moves.
///
/// The *search* is not identical, and is better. On a phone this app runs
/// `go movetime 500 depth 12`, so the 500 ms budget usually binds before depth
/// 12 is reached — reports come out shallow, and because the cap is time-based
/// they differ between devices and between runs of the same game.
///
/// The server reproduces the desktop app instead: `go depth 14`, no time cap,
/// one thread, Stockfish 17.1, and desktop's own hash configuration down to
/// never sending `ucinewgame` between positions. That is both deeper and
/// reproducible, so moving a review to the server makes mobile and desktop
/// agree where they previously did not.
///
/// The engine path stays in place and is what runs if this is unavailable. That
/// is deliberate: a review that cannot run offline is a worse app than one that
/// analyses locally, so the server is an accelerator, never a dependency.
library;

import 'dart:async';
import 'dart:convert';

import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/notation/notation_tree.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Where the analysis Worker lives.
///
/// Overridable so a build can point at a preview deployment without a code
/// change: `--dart-define=ANALYSIS_API_BASE=http://127.0.0.1:8787`.
const String kAnalysisApiBase = String.fromEnvironment(
  'ANALYSIS_API_BASE',
  defaultValue: 'https://chessever-analysis.young-sun-69a8.workers.dev',
);

/// A server report could not be produced.
///
/// Always carries a message fit to show a user, because every one of these ends
/// up either in the report panel or in a decision to fall back to the engine.
class ServerGameReportException implements Exception {
  const ServerGameReportException(this.message, {this.code});

  final String message;

  /// The Worker's machine-readable `error` / `errorCode`, when it sent one.
  final String? code;

  @override
  String toString() => 'ServerGameReportException($code): $message';
}

/// Runs a whole-game report on the server and reports progress as it goes.
class ServerGameReportClient {
  ServerGameReportClient({http.Client? httpClient, String? baseUrl})
    : _http = httpClient ?? http.Client(),
      _baseUrl = _trimSlash(baseUrl ?? kAnalysisApiBase);

  final http.Client _http;
  final String _baseUrl;

  /// How often the job is polled.
  ///
  /// A whole-game report is tens of seconds at least, so a tight poll buys
  /// nothing but requests. The Worker's own progress fraction is what moves the
  /// bar between polls.
  static const Duration pollInterval = Duration(seconds: 2);

  /// Ceiling on one report, matching the Workflow's own 30-minute step timeout.
  static const Duration overallTimeout = Duration(minutes: 30);

  static String _trimSlash(String value) =>
      value.endsWith('/') ? value.substring(0, value.length - 1) : value;

  static String? _accessToken() {
    try {
      final token = Supabase.instance.client.auth.currentSession?.accessToken;
      return (token == null || token.isEmpty) ? null : token;
    } catch (_) {
      // Supabase not initialised (tests, or a build without it).
      return null;
    }
  }

  Map<String, String> _headers(String token) => {
    'content-type': 'application/json',
    'accept': 'application/json',
    'authorization': 'Bearer $token',
  };

  /// Analyses [game] on the server and returns the finished report.
  ///
  /// [onProgress] receives the Worker's own fraction and message. [isCancelled]
  /// is polled between requests so a user who leaves the tab stops the wait
  /// immediately — the job itself keeps running server-side and its result stays
  /// cached, so coming back is free rather than a second analysis.
  Future<GameAnalysisReport> analyze(
    ChessGame game, {
    int? whiteRating,
    int? blackRating,
    void Function(double progress, String message)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final token = _accessToken();
    if (token == null) {
      throw const ServerGameReportException(
        'Sign in to run Game Analysis on the server.',
        code: 'unauthenticated',
      );
    }

    final job = await _createJob(
      token,
      game: game,
      whiteRating: whiteRating,
      blackRating: blackRating,
    );

    final deadline = DateTime.now().add(overallTimeout);
    var status = job.status;
    var progress = job.progress;
    var message = job.message;

    while (status != 'succeeded') {
      if (isCancelled?.call() ?? false) {
        throw const ServerGameReportException(
          'Analysis cancelled.',
          code: 'cancelled',
        );
      }
      if (status == 'failed') {
        throw ServerGameReportException(
          _failureMessage(job.errorCode ?? 'analysis_failed'),
          code: job.errorCode,
        );
      }
      if (DateTime.now().isAfter(deadline)) {
        throw const ServerGameReportException(
          'The server took too long to analyse this game.',
          code: 'timeout',
        );
      }

      onProgress?.call(progress, message ?? _statusMessage(status));
      await Future<void>.delayed(pollInterval);

      final polled = await _pollJob(token, job.id);
      status = polled.status;
      progress = polled.progress;
      message = polled.message;
      if (status == 'failed') {
        throw ServerGameReportException(
          _failureMessage(polled.errorCode ?? 'analysis_failed'),
          code: polled.errorCode,
        );
      }
    }

    onProgress?.call(0.99, 'Fetching report…');
    final payload = await _fetchResult(token, job.id);
    return gameAnalysisReportFromServerJson(payload, game: game);
  }

  Future<_ReportJob> _createJob(
    String token, {
    required ChessGame game,
    int? whiteRating,
    int? blackRating,
  }) async {
    final response = await _http.post(
      Uri.parse('$_baseUrl/v1/reports'),
      headers: _headers(token),
      body: jsonEncode({
        // The report travels in the PGN in both directions, and this is the
        // same writer Copy PGN uses, so the server parses exactly the game the
        // user is looking at.
        'pgn': exportGameToPgn(game),
        if (whiteRating != null) 'whiteRating': whiteRating,
        if (blackRating != null) 'blackRating': blackRating,
      }),
    );

    if (response.statusCode != 200 && response.statusCode != 202) {
      throw _errorFor(response);
    }
    return _ReportJob.fromJson(_decode(response));
  }

  Future<_ReportJob> _pollJob(String token, String id) async {
    final response = await _http.get(
      Uri.parse('$_baseUrl/v1/reports/$id'),
      headers: _headers(token),
    );
    if (response.statusCode != 200) throw _errorFor(response);
    return _ReportJob.fromJson(_decode(response));
  }

  Future<Map<String, dynamic>> _fetchResult(String token, String id) async {
    final response = await _http.get(
      Uri.parse('$_baseUrl/v1/reports/$id/result'),
      headers: _headers(token),
    );
    if (response.statusCode != 200) throw _errorFor(response);
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Fall through to the shared error below.
    }
    throw const ServerGameReportException(
      'The analysis service returned something unreadable.',
      code: 'invalid_response',
    );
  }

  ServerGameReportException _errorFor(http.Response response) {
    String? code;
    String? detail;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map) {
        code = decoded['error'] as String?;
        detail = decoded['message'] as String?;
      }
    } catch (_) {
      // A non-JSON body is still a failure; the status code carries it.
    }
    return ServerGameReportException(
      detail ?? _failureMessage(code ?? 'http_${response.statusCode}'),
      code: code,
    );
  }

  String _statusMessage(String status) => switch (status) {
    'queued' => 'Waiting for an analysis slot…',
    'analyzing' => 'Analyzing on the server…',
    'storing' => 'Finishing up…',
    _ => 'Analyzing…',
  };

  String _failureMessage(String code) => switch (code) {
    'active_job_limit' =>
      'A report is already running. Wait for it to finish before starting '
          'another.',
    'daily_job_limit' => 'Daily report limit reached. Try again tomorrow.',
    'invalid_token' ||
    'unauthenticated' => 'Sign in to run Game Analysis on the server.',
    'invalid_pgn' => 'This game could not be read by the analysis service.',
    'result_expired' => 'That report has expired. Run it again.',
    _ => 'Server analysis failed.',
  };

  void close() => _http.close();
}

/// The controller-facing form of [ServerGameReportClient].
///
/// Returns null when no analysis service is configured, which leaves the
/// controller on its local engine path with nothing to fall back from.
GameReportRemoteRunner? serverGameReportRunner({
  ServerGameReportClient Function()? clientFactory,
}) {
  if (kAnalysisApiBase.isEmpty) return null;
  final create = clientFactory ?? ServerGameReportClient.new;
  return (
    ChessGame game, {
    int? whiteRating,
    int? blackRating,
    required void Function(double progress, String message) onProgress,
    required bool Function() isCancelled,
  }) async {
    // One client per report, closed when that report ends. A report is a
    // minutes-long operation, so a per-run connection pool costs nothing — and
    // it means no widget or provider has to own an HTTP client's lifetime just
    // to avoid leaking one.
    final client = create();
    try {
      return await client.analyze(
        game,
        whiteRating: whiteRating,
        blackRating: blackRating,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
    } finally {
      client.close();
    }
  };
}

class _ReportJob {
  const _ReportJob({
    required this.id,
    required this.status,
    required this.progress,
    this.message,
    this.errorCode,
  });

  factory _ReportJob.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const ServerGameReportException(
        'The analysis service did not return a job.',
        code: 'invalid_response',
      );
    }
    return _ReportJob(
      id: id,
      status: json['status'] as String? ?? 'queued',
      progress: (json['progress'] as num?)?.toDouble() ?? 0,
      message: json['message'] as String?,
      errorCode: json['errorCode'] as String?,
    );
  }

  final String id;
  final String status;
  final double progress;
  final String? message;
  final String? errorCode;
}

/// Rebuilds a [GameAnalysisReport] from the Worker's JSON.
///
/// [game] is the local game the report was requested for. Its fingerprint is
/// checked against the one the server computed: everything downstream — the
/// badges, the graph, the export — is keyed on that fingerprint, so a mismatch
/// would silently paint one game's verdicts onto another.
GameAnalysisReport gameAnalysisReportFromServerJson(
  Map<String, dynamic> json, {
  required ChessGame game,
}) {
  final expected = gameReportFingerprint(game);
  final fingerprint = json['fingerprint'] as String?;
  if (fingerprint != expected) {
    throw const ServerGameReportException(
      'The server analysed a different game.',
      code: 'fingerprint_mismatch',
    );
  }

  final rawMoves = json['moves'];
  final rawPositions = json['positions'];
  if (rawMoves is! List || rawPositions is! List) {
    throw const ServerGameReportException(
      'The analysis service returned an incomplete report.',
      code: 'invalid_response',
    );
  }
  if (rawMoves.length != game.mainline.length ||
      rawPositions.length != game.mainline.length + 1) {
    throw const ServerGameReportException(
      'The analysis service returned a report of the wrong length.',
      code: 'invalid_response',
    );
  }

  final positions = <GameReportPosition>[
    for (final raw in rawPositions.cast<Map<String, dynamic>>())
      GameReportPosition(
        fen: raw['fen'] as String,
        // The wire format carries one line per position — the principal
        // variation — because that is all the graph and the labels need. The
        // alternatives that MultiPV found are already resolved server-side into
        // each move's `bestAlternative`.
        lines: [_lineFromJson(raw['evaluation'])],
      ),
  ];

  final moves = <GameReportMove>[
    for (final raw in rawMoves.cast<Map<String, dynamic>>())
      GameReportMove(
        ply: (raw['ply'] as num).toInt(),
        san: raw['san'] as String,
        uci: raw['uci'] as String,
        isWhite: raw['isWhite'] as bool,
        classification: _classificationFromName(raw['classification']),
        evaluation: _lineFromJson(raw['evaluation']),
        bestAlternative: raw['bestAlternative'] as String?,
      ),
  ];

  final accuracy = json['accuracy'] as Map<String, dynamic>? ?? const {};
  final ratings = json['estimatedRating'] as Map<String, dynamic>? ?? const {};
  final generatedAt = DateTime.tryParse(json['generatedAt'] as String? ?? '');

  return GameAnalysisReport(
    fingerprint: expected,
    positions: List.unmodifiable(positions),
    moves: List.unmodifiable(moves),
    whiteAccuracy: (accuracy['white'] as num?)?.toDouble() ?? 0,
    blackAccuracy: (accuracy['black'] as num?)?.toDouble() ?? 0,
    whiteEstimatedRating: (ratings['white'] as num?)?.toInt(),
    blackEstimatedRating: (ratings['black'] as num?)?.toInt(),
    generatedAt: generatedAt ?? DateTime.now(),
  );
}

GameReportLine _lineFromJson(Object? raw) {
  if (raw is! Map) {
    // A position with no evaluation is only possible on the hydrate path, which
    // this client never requests. Keep it representable rather than throwing:
    // a zero-depth empty line reads as "no information", which is true.
    return const GameReportLine(moves: <String>[], depth: 0);
  }
  return GameReportLine(
    moves: List<String>.unmodifiable(
      (raw['moves'] as List?)?.whereType<String>() ?? const <String>[],
    ),
    depth: (raw['depth'] as num?)?.toInt() ?? 0,
    centipawns: (raw['centipawns'] as num?)?.toInt(),
    mate: (raw['mate'] as num?)?.toInt(),
  );
}

/// Maps the wire name back onto the enum.
///
/// Null is a real value — the algorithm returns it for an ordinary move — so an
/// absent classification is not an error. An *unknown* name is: it means the
/// server is running a classifier with a category this build has never heard
/// of, and silently dropping it would show the move as unremarkable.
GameMoveClassification? _classificationFromName(Object? raw) {
  if (raw == null) return null;
  final name = raw as String;
  for (final value in GameMoveClassification.values) {
    if (value.name == name) return value;
  }
  if (kDebugMode) {
    debugPrint('[ServerGameReport] unknown classification "$name"');
  }
  return null;
}
