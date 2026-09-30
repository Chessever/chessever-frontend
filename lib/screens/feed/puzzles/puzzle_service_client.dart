import 'dart:async';
import 'dart:convert';

import 'package:chessever2/screens/feed/puzzles/feed_puzzle_model.dart';
import 'package:chessever2/screens/feed/puzzles/puzzle_session.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// A puzzle-service request that did not produce puzzles.
class PuzzleServiceException implements Exception {
  const PuzzleServiceException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'PuzzleServiceException(${statusCode ?? '-'}): $message';
}

/// The service answered 429; nothing is sent to it again before [until].
class PuzzleServiceRateLimitedException extends PuzzleServiceException {
  const PuzzleServiceRateLimitedException(this.until)
    : super('Rate limited', statusCode: 429);

  final DateTime until;
}

/// Prefix of every [FeedPuzzle.id] this service hands out, so its numeric
/// ids never collide with the Lichess ids earlier versions cached and
/// recorded as finished.
const String kPuzzleServiceIdPrefix = 'ce:';

/// Client for ChessEver's own puzzle service (the `race` Worker):
/// `GET <base>/v1/puzzles/feed?min=&max=&limit=[&seed=]`.
///
/// Anonymous: the feed needs no account, and no token is sent. With an empty
/// base URL ([isConfigured] false) it sends nothing at all. After a 429 it
/// stays quiet until the service's `Retry-After` has passed.
class PuzzleServiceClient {
  PuzzleServiceClient({
    required String baseUrl,
    http.Client? httpClient,
    DateTime Function()? clock,
    this._timeout = requestTimeout,
  }) : _base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), ''),
       _http = httpClient ?? http.Client(),
       _ownsHttp = httpClient == null,
       _clock = clock ?? DateTime.now;

  static const String feedPath = '/v1/puzzles/feed';

  /// How long one request may run before it is aborted.
  static const Duration requestTimeout = Duration(seconds: 10);

  /// Back-off after a 429 that names no `Retry-After`, and the most any
  /// `Retry-After` is honoured for.
  static const Duration rateLimitBackoff = Duration(seconds: 60);
  static const Duration maxRateLimitBackoff = Duration(minutes: 10);

  /// Last resort for an [http.Client] that ignores `abortTrigger`.
  static const Duration _abortGrace = Duration(seconds: 5);

  final String _base;
  final http.Client _http;
  final bool _ownsHttp;
  final DateTime Function() _clock;
  final Duration _timeout;

  DateTime? _blockedUntil;

  /// False when no service URL is configured; the client then never sends.
  bool get isConfigured => _base.isNotEmpty;

  /// When the 429 back-off ends; null when requests may go out.
  DateTime? get blockedUntil {
    final until = _blockedUntil;
    if (until == null || !_clock().isBefore(until)) return null;
    return until;
  }

  /// Up to [limit] puzzles rated [minRating]..[maxRating]. Rows that do not
  /// replay into a playable puzzle are skipped. [seed] picks another page
  /// than the service's rotating default.
  Future<List<FeedPuzzle>> feed({
    required int minRating,
    required int maxRating,
    int limit = 20,
    int? seed,
  }) async {
    if (!isConfigured) {
      throw const PuzzleServiceException('No puzzle service configured');
    }
    final until = blockedUntil;
    if (until != null) throw PuzzleServiceRateLimitedException(until);

    final uri = Uri.parse('$_base$feedPath').replace(
      queryParameters: {
        'min': '$minRating',
        'max': '$maxRating',
        'limit': '$limit',
        if (seed != null) 'seed': '$seed',
      },
    );
    final http.Response response;
    try {
      response = await _send(uri).timeout(_timeout + _abortGrace);
    } on TimeoutException {
      throw const PuzzleServiceException('Timed out');
    } on http.RequestAbortedException {
      throw const PuzzleServiceException('Timed out');
    } on http.ClientException catch (error) {
      throw PuzzleServiceException('Network error: ${error.message}');
    }

    if (response.statusCode == 429) {
      final until = _clock().add(_retryAfter(response.headers['retry-after']));
      _blockedUntil = until;
      throw PuzzleServiceRateLimitedException(until);
    }
    if (response.statusCode != 200) {
      throw PuzzleServiceException(
        'Unexpected status',
        statusCode: response.statusCode,
      );
    }
    final Object? body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const PuzzleServiceException('Unreadable JSON');
    }
    return parsePuzzleFeed(body);
  }

  void close() {
    if (_ownsHttp) _http.close();
  }

  /// One GET whose connection is closed by an abort once [_timeout] passes,
  /// so when this completes, either way, the request is over on the wire.
  Future<http.Response> _send(Uri uri) async {
    final abort = Completer<void>();
    final timer = Timer(_timeout, abort.complete);
    try {
      final request = http.AbortableRequest(
        'GET',
        uri,
        abortTrigger: abort.future,
      )..headers['Accept'] = 'application/json';
      return await http.Response.fromStream(await _http.send(request));
    } finally {
      timer.cancel();
    }
  }

  static Duration _retryAfter(String? header) {
    final seconds = int.tryParse(header?.trim() ?? '');
    if (seconds == null || seconds <= 0) return rateLimitBackoff;
    final wait = Duration(seconds: seconds);
    return wait > maxRateLimitBackoff ? maxRateLimitBackoff : wait;
  }
}

/// The puzzles in a `/v1/puzzles/feed` body (`{"seed": …, "puzzles": [...]}`,
/// or a bare list). Unusable rows are skipped, never fatal.
List<FeedPuzzle> parsePuzzleFeed(Object? body) {
  final rows = switch (body) {
    List() => body,
    Map() when body['puzzles'] is List => body['puzzles'] as List,
    _ => throw const PuzzleServiceException('Response has no puzzles'),
  };
  final puzzles = <FeedPuzzle>[];
  var skipped = 0;
  for (final row in rows) {
    try {
      puzzles.add(parsePuzzleRow(row));
    } on FormatException catch (error) {
      skipped++;
      if (skipped == 1) debugPrint('[FeedPuzzles] skipped a row: $error');
    }
  }
  if (skipped > 1) debugPrint('[FeedPuzzles] skipped $skipped rows');
  return puzzles;
}

final RegExp _uci = RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$');

/// One service row into a [FeedPuzzle]:
/// `{id, source_id, fen, moves, rating, themes[], opening_tags[], game_url}`,
/// where [fen] is the position BEFORE the setup move and `moves` is
/// space-separated UCI whose first move is the opponent's setup move, then
/// solver and opponent alternating (Lichess's puzzle database layout).
///
/// Throws [FormatException] when the row is not a playable puzzle.
FeedPuzzle parsePuzzleRow(Object? row) {
  if (row is! Map) throw const FormatException('Row is not an object');
  final rawId = row['id'];
  final id = switch (rawId) {
    int() => '$rawId',
    String() when rawId.trim().isNotEmpty => rawId.trim(),
    _ => throw const FormatException('Row has no id'),
  };
  final fen = row['fen'];
  if (fen is! String || fen.trim().isEmpty) {
    throw FormatException('Puzzle $id: no FEN');
  }
  final moves = _moveList(row['moves']);
  if (moves.length < 2) {
    throw FormatException('Puzzle $id: needs a setup move and a solution');
  }
  if (!moves.every(_uci.hasMatch)) {
    throw FormatException('Puzzle $id: moves are not UCI');
  }

  final puzzle = FeedPuzzle(
    id: '$kPuzzleServiceIdPrefix$id',
    fen: fen.trim(),
    initialMoveUci: moves.first,
    solution: moves.sublist(1),
    rating: _int(row['rating']),
    themes: _words(row['themes']),
    gameUrl: _lichessLink(row['game_url']),
    sourceId: switch (row['source_id']) {
      final int n => '$n',
      final String s when s.trim().isNotEmpty => s.trim(),
      _ => null,
    },
    openingTags: _words(row['opening_tags']),
  );

  // Replays the whole line once: a row whose moves do not follow from the
  // position is rejected here, not on the viewer's board.
  PuzzleSession(puzzle);
  return puzzle;
}

List<String> _moveList(Object? value) {
  final List<String> moves = switch (value) {
    String() => value.trim().split(RegExp(r'\s+')),
    List() when value.every((m) => m is String) => [
      for (final m in value) (m as String).trim(),
    ],
    _ => const [],
  };
  return moves.where((m) => m.isNotEmpty).toList(growable: false);
}

List<String> _words(Object? value) => switch (value) {
  List() =>
    value
        .whereType<String>()
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList(growable: false),
  String() =>
    value.trim().isEmpty
        ? const []
        : value.trim().split(RegExp(r'\s+')).toList(growable: false),
  _ => const [],
};

int? _int(Object? value) => switch (value) {
  int() => value,
  double() when value.isFinite => value.round(),
  String() => int.tryParse(value.trim()),
  _ => null,
};

/// Only an https link to Lichess is kept. It is data only: the puzzle page
/// neither shows nor opens it, and the app never requests it.
String? _lichessLink(Object? value) {
  if (value is! String) return null;
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.scheme != 'https') return null;
  final host = uri.host.toLowerCase();
  if (host != 'lichess.org' && !host.endsWith('.lichess.org')) return null;
  return uri.toString();
}
