import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report_store.dart';
import 'package:chessever2/screens/chessboard/notation/notation_tree.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new_worker.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/pgn_link_rebrand.dart';
import 'package:chessever2/utils/time_control_bonus.dart';
import 'package:dartchess/dartchess.dart';

typedef SharePgnFetcher = Future<String?> Function(String gameId);
typedef SharePgnExporter = String Function(ChessGame game);
typedef SharePgnParser = PgnParseResult Function(String pgn);

const _defaultStartingFen =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

/// PGN quality-verdict NAGs ($1–$6) that answer "how good was this move".
/// A completed Game Analysis report owns that question and replaces them.
const _moveVerdictNags = <int>{1, 2, 3, 4, 5, 6};

/// ChessEver product slug for a report classification (Cloudflare GIF asset key).
///
/// The cloud renderer expects `[%chessever_annotation brilliant]` /
/// `good_move` / … and maps those 1:1 onto badge PNGs. When **we** generated
/// the report, hydrate with these product names — not classic glyphs.
String? chesseverClassificationName(GameMoveClassification? classification) =>
    switch (classification) {
      GameMoveClassification.brilliant => 'brilliant',
      GameMoveClassification.goodMove => 'good_move',
      GameMoveClassification.bestMove => 'best_move',
      GameMoveClassification.missedWin => 'missed_win',
      GameMoveClassification.inaccuracy => 'inaccuracy',
      GameMoveClassification.mistake => 'mistake',
      GameMoveClassification.blunder => 'blunder',
      GameMoveClassification.bookMove => 'book_move',
      null => null,
    };

/// Adds completed Game Analysis scores and classifications onto a [ChessGame]
/// before export (Copy PGN, Share PGN, and GIF).
///
/// A matching completed report is authoritative for every evaluated ply, so
/// freshly generated Game Analysis values replace older/default PGN values.
///
/// When **we** generated the report, hydrate with ChessEver product-name
/// directives Cloudflare and the apps expect:
/// `[%chessever_annotation brilliant]` / `good_move` / `best_move` / …
/// plus quality NAGs `$1`–`$6` as a portable best-effort companion.
/// Classic glyph tokens (`!!`, `?!`) are for import/best-effort only — never
/// the report-export format.
ChessGame mergeGameReportAnnotationsForExport(
  ChessGame game,
  GameAnalysisReport? report,
) {
  if (report == null ||
      report.moves.isEmpty ||
      report.fingerprint != gameReportFingerprint(game)) {
    return game;
  }

  final byPly = <int, GameReportMove>{
    for (final move in report.moves) move.ply: move,
  };
  var changed = false;
  final mainline = <ChessMove>[
    for (var index = 0; index < game.mainline.length; index++)
      (() {
        final move = game.mainline[index];
        final reportMove = byPly[index + 1];
        if (reportMove == null) return move;

        final reportLine = reportMove.evaluation;
        final evaluation =
            reportLine.mate != null
                ? '#${reportLine.mate}'
                : reportLine.centipawns != null
                ? (reportLine.centipawns! / 100).toStringAsFixed(2)
                : move.eval;
        final product = chesseverClassificationName(
          reportMove.classification,
        );
        final directive =
            product == null ? null : '[%chessever_annotation $product]';
        final existingComments = move.comments ?? const <String>[];
        // Replace any prior chessever directive so export always carries
        // product names for this report (Cloudflare asset keys).
        final withoutChessever =
            existingComments
                .where((c) => !c.contains('[%chessever_annotation '))
                .toList(growable: true);
        final comments =
            directive == null
                ? withoutChessever
                : <String>[...withoutChessever, directive];

        final classic = classicGlyphForClassification(
          reportMove.classification,
        );
        final reportNag = nagForClassicGlyph(classic);
        final existingNags = move.nags ?? const <int>[];
        final nonVerdictNags =
            existingNags
                .where((nag) => !_moveVerdictNags.contains(nag))
                .toList(growable: true);
        if (reportNag != null && !nonVerdictNags.contains(reportNag)) {
          nonVerdictNags.add(reportNag);
        }
        final nags = nonVerdictNags;

        final evalChanged = evaluation != null && evaluation != move.eval;
        final commentsChanged =
            comments.length != existingComments.length ||
            !comments.every(existingComments.contains);
        final nagsChanged =
            nags.length != existingNags.length ||
            !nags.every(existingNags.contains);
        if (!evalChanged && !commentsChanged && !nagsChanged) return move;
        changed = true;
        return move.copyWith(eval: evaluation, comments: comments, nags: nags);
      })(),
  ];

  return changed ? game.copyWith(mainline: mainline) : game;
}

/// Alias — GIF was the first consumer; same product-name hydrate as export.
ChessGame mergeGameReportAnnotationsForGif(
  ChessGame game,
  GameAnalysisReport? report,
) => mergeGameReportAnnotationsForExport(game, report);

/// Merge + [exportGameToPgn] in one step (Copy PGN / Share PGN / tests).
String exportGamePgnWithReport(ChessGame game, GameAnalysisReport? report) {
  return exportGameToPgn(mergeGameReportAnnotationsForExport(game, report));
}

/// Prefer the live completed report, then session cache, then durable store.
Future<GameAnalysisReport?> resolveCompletedGameAnalysisReport({
  required ChessGame? analysisGame,
  GameAnalysisReport? liveReport,
  GameAnalysisReportStore? store,
}) async {
  if (analysisGame == null) return null;
  final fingerprint = gameReportFingerprint(analysisGame);
  if (liveReport != null &&
      liveReport.fingerprint == fingerprint &&
      liveReport.moves.isNotEmpty) {
    return liveReport;
  }
  final cached = GameAnalysisReportController.cachedReportFor(fingerprint);
  if (cached != null && cached.moves.isNotEmpty) return cached;
  final disk = await (store ?? GameAnalysisReportStore.instance).load(
    fingerprint,
  );
  if (disk != null && disk.moves.isNotEmpty) return disk;
  return null;
}

/// Classic portable glyph for a report classification (best-effort for other apps).
///
/// ChessEver’s richer labels collapse onto the five standard quality marks
/// every PGN consumer already knows. Book has no classic glyph.
String? classicGlyphForClassification(GameMoveClassification? classification) =>
    switch (classification) {
      GameMoveClassification.brilliant => '!!',
      GameMoveClassification.goodMove => '!',
      GameMoveClassification.bestMove => '!',
      GameMoveClassification.missedWin => '??',
      GameMoveClassification.inaccuracy => '?!',
      GameMoveClassification.mistake => '?',
      GameMoveClassification.blunder => '??',
      GameMoveClassification.bookMove => null,
      null => null,
    };

/// Standard PGN quality NAG ($1–$6) for a classic glyph.
int? nagForClassicGlyph(String? glyph) => switch (glyph) {
  '!' => 1,
  '?' => 2,
  '!!' => 3,
  '??' => 4,
  '!?' => 5,
  '?!' => 6,
  _ => null,
};

/// Query param marking a `/games/<uuid>` share link whose id lives in the
/// gamebase (TWIC archive) rather than the app's Supabase games table. The
/// deep link resolves these through the gamebase API.
const kGamebaseShareSourceParam = 'src';
const kGamebaseShareSourceValue = 'gamebase';

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
  var isGamebaseDeepLink = false;
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
      // Broadcast-imported games carry their Lichess game URL in the PGN
      // Site header, and that id resolves against the app's own games table —
      // prefer it. Everything else in the TWIC/gamebase archive (chess.com
      // imports, OTB events) only has the gamebase uuid, which the deep link
      // resolves through the gamebase API when tagged with `src=gamebase`.
      // Their tourSlug/roundSlug are display labels (event name, ECO), not
      // real slugs, so leave them out of the URL.
      linkableId = lichessGameIdFromPgn(game.pgn);
      if (linkableId == null) {
        final gamebaseId = _trimmedOrNull(game.gameId);
        if (gamebaseId != null && _uuidPattern.hasMatch(gamebaseId)) {
          linkableId = gamebaseId;
          isGamebaseDeepLink = true;
        }
      }
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
  if (isGamebaseDeepLink) {
    queryParams[kGamebaseShareSourceParam] = kGamebaseShareSourceValue;
  }
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
      // Trello #1005: raw PGN clocks lack the move-40 block of time until the
      // relay credits it. The board-state branch above is already corrected.
      moveTimes: applySecondaryBonusToMoveClocks(
        List<String>.from(parsed.moveTimes),
        game.secondaryTimePeriod,
      ),
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
