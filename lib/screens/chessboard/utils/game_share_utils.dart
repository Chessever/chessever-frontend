import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/notation/notation_tree.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new_worker.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/pgn_link_rebrand.dart';
import 'package:dartchess/dartchess.dart';

typedef SharePgnFetcher = Future<String?> Function(String gameId);
typedef SharePgnExporter = String Function(ChessGame game);
typedef SharePgnParser = PgnParseResult Function(String pgn);

const _defaultStartingFen =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final _lichessShortIdPattern = RegExp(r'^[A-Za-z0-9]{8}$');

/// Broadcast game URLs keep the game id as the last segment:
/// `lichess.org/broadcast/{tourSlug}/{roundSlug}/{roundId}/{gameId}`.
/// Also match `chessever.com` — [rebrandPgnLinks] swaps only the host and
/// keeps the Lichess path structure intact.
final _broadcastGameUrlPattern = RegExp(
  r'(?:lichess\.(?:org|dev)|chessever\.com)/broadcast/[^/\s"]+/[^/\s"]+/[A-Za-z0-9]{8}/([A-Za-z0-9]{8})',
  caseSensitive: false,
);

/// Direct game URLs: `lichess.org/{gameId}` (optionally `/white`, `?...`).
final _directGameUrlPattern = RegExp(
  r'(?:lichess\.(?:org|dev)|chessever\.com)/([A-Za-z0-9]{8})(?=[/?#\s"]|$)',
  caseSensitive: false,
);

class GameShareSnapshot {
  final String positionFen;
  final Move? lastMove;
  final List<String> moveSans;
  final List<String> moveTimes;
  final int currentMoveIndex;
  final String? startingFen;

  const GameShareSnapshot({
    required this.positionFen,
    required this.lastMove,
    required this.moveSans,
    required this.moveTimes,
    required this.currentMoveIndex,
    this.startingFen,
  });
}

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

String? _trimmedOrNull(String? value) {
  if (!_hasText(value)) return null;
  return value!.trim();
}

String? _normalizedStartingFen(String? fen) {
  final trimmed = _trimmedValidFen(fen);
  if (trimmed == null || trimmed == _defaultStartingFen) {
    return null;
  }
  return trimmed;
}

String? _trimmedValidFen(String? fen) {
  final trimmed = _trimmedOrNull(fen);
  if (trimmed == null) return null;
  try {
    Setup.parseFen(trimmed);
    return trimmed;
  } catch (_) {
    return null;
  }
}

bool _isResolvableSharedGameId(String id) {
  final trimmed = id.trim();
  return _uuidPattern.hasMatch(trimmed) ||
      _lichessShortIdPattern.hasMatch(trimmed);
}

bool isGamebaseBackedSource(GameSource source) {
  return source == GameSource.gamebase || source == GameSource.twic;
}

/// Recover the Lichess game id from a PGN's link headers (`Site`,
/// `GameURL`, ...). Broadcast-imported gamebase/TWIC games keep their
/// original Lichess game URL there, and the shared-game deep link resolves
/// 8-char Lichess ids via `getGameByLichessId`.
String? lichessGameIdFromPgn(String? pgn) {
  if (!_hasText(pgn)) return null;
  final broadcastMatch = _broadcastGameUrlPattern.firstMatch(pgn!);
  if (broadcastMatch != null) return broadcastMatch.group(1);
  return _directGameUrlPattern.firstMatch(pgn)?.group(1);
}

String? buildGameShareUrl({
  required GamesTourModel game,
  SavedAnalysisData? savedAnalysisData,
}) {
  String? linkableId;
  var includeTourContext = false;
  switch (game.source) {
    case GameSource.supabase:
      linkableId = _trimmedOrNull(game.gameId);
      includeTourContext = true;
      break;
    case GameSource.savedAnalysis:
      linkableId = _trimmedOrNull(savedAnalysisData?.sourceGameId);
      includeTourContext = true;
      break;
    case GameSource.gamebase:
    case GameSource.twic:
      // Gamebase/TWIC ids are internal and not resolvable by the shared-game
      // deep link. Broadcast-imported games still carry their Lichess game
      // URL in the PGN Site header, so recover the linkable id from there.
      // Their tourSlug/roundSlug are display labels (event name, ECO), not
      // real slugs, so leave them out of the URL.
      linkableId = lichessGameIdFromPgn(game.pgn);
      break;
    case GameSource.openingExplorer:
    case GameSource.boardEditor:
    case GameSource.localAnalysis:
      linkableId = null;
      break;
  }

  if (linkableId == null || !_isResolvableSharedGameId(linkableId)) {
    return null;
  }

  final uri = Uri.parse('https://chessever.com/games/$linkableId');
  final queryParams = <String, String>{};
  if (includeTourContext) {
    if (_hasText(game.tourSlug)) queryParams['tour'] = game.tourSlug!;
    if (_hasText(game.roundSlug)) queryParams['round'] = game.roundSlug!;
  }

  if (queryParams.isEmpty) {
    return uri.toString();
  }

  return uri.replace(queryParameters: queryParams).toString();
}

String buildShareFallbackPgn(GamesTourModel game) {
  final event =
      _trimmedOrNull(game.tourSlug) ??
      _trimmedOrNull(game.tourId) ??
      'ChessEver';

  return buildHeaderOnlyPgn(
    whiteName: game.whitePlayer.name,
    blackName: game.blackPlayer.name,
    result: game.gameStatus.displayText,
    event: event,
    eco: _trimmedOrNull(game.roundSlug),
    opening: _trimmedOrNull(game.openingName),
    date: game.lastMoveTime,
  );
}

Future<String> resolveGameSharePgn({
  required GamesTourModel game,
  required ChessGame? analysisGame,
  required SavedAnalysisData? savedAnalysisData,
  SharePgnFetcher? fetchSupabasePgn,
  SharePgnFetcher? fetchGamebasePgn,
  SharePgnExporter exportPgn = exportGameToPgn,
}) async {
  String? fallback;

  String? firstUsable(String? candidate) {
    final trimmed = _trimmedOrNull(candidate);
    if (trimmed == null) return null;
    // Strip Lichess host references before this PGN ever leaves the app.
    final branded = rebrandPgnLinks(trimmed);
    fallback ??= branded;
    return pgnHasMoves(branded) ? branded : null;
  }

  final analysisPgn =
      analysisGame == null ? null : firstUsable(exportPgn(analysisGame));
  if (analysisPgn != null) return analysisPgn;

  final modelPgn = firstUsable(game.pgn);
  if (modelPgn != null) return modelPgn;

  final savedAnalysisPgn =
      savedAnalysisData == null
          ? null
          : firstUsable(exportPgn(savedAnalysisData.chessGame));
  if (savedAnalysisPgn != null) return savedAnalysisPgn;

  if (game.source == GameSource.supabase && fetchSupabasePgn != null) {
    final supabasePgn = firstUsable(await fetchSupabasePgn(game.gameId));
    if (supabasePgn != null) return supabasePgn;
  }

  if (isGamebaseBackedSource(game.source) && fetchGamebasePgn != null) {
    final gamebasePgn = firstUsable(await fetchGamebasePgn(game.gameId));
    if (gamebasePgn != null) return gamebasePgn;
  }

  return fallback ?? buildShareFallbackPgn(game).trim();
}

GameShareSnapshot buildGameShareSnapshot({
  required GamesTourModel game,
  required String pgn,
  ChessBoardStateNew? state,
  SharePgnParser parsePgn = parsePgnWorker,
}) {
  final stateAnalysis = state?.analysisState;
  final canUseBoardState =
      state != null &&
      !state.isLoadingMoves &&
      stateAnalysis != null &&
      (stateAnalysis.game != null ||
          stateAnalysis.moveSans.isNotEmpty ||
          state.moveSans.isNotEmpty);

  if (canUseBoardState) {
    return GameShareSnapshot(
      positionFen: stateAnalysis.position.fen,
      lastMove: stateAnalysis.lastMove,
      moveSans: List<String>.from(stateAnalysis.moveSans),
      moveTimes: List<String>.from(state.moveTimes),
      currentMoveIndex: stateAnalysis.currentMoveIndex,
      startingFen: _normalizedStartingFen(stateAnalysis.startingPosition?.fen),
    );
  }

  final gameFen = _trimmedValidFen(game.fen);
  final gameLastMove = _trimmedOrNull(game.lastMove);

  try {
    final parsed = parsePgn(pgn);
    return GameShareSnapshot(
      positionFen: gameFen ?? parsed.finalPos.fen,
      lastMove:
          gameLastMove == null
              ? parsed.lastMove
              : (Move.parse(gameLastMove) ?? parsed.lastMove),
      moveSans: List<String>.from(parsed.moveSans),
      moveTimes: List<String>.from(parsed.moveTimes),
      currentMoveIndex:
          parsed.moveSans.isEmpty ? -1 : parsed.moveSans.length - 1,
      startingFen: _normalizedStartingFen(parsed.startingPos.fen),
    );
  } catch (_) {
    return GameShareSnapshot(
      positionFen: gameFen ?? _defaultStartingFen,
      lastMove: gameLastMove == null ? null : Move.parse(gameLastMove),
      moveSans: const <String>[],
      moveTimes: const <String>[],
      currentMoveIndex: -1,
      startingFen: null,
    );
  }
}
