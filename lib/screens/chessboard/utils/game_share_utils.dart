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

/// ChessEver's classification NAG block: `$240`–`$247`, one code per report
/// class, written **beside** the standard quality NAG rather than instead of it.
///
/// Why a NAG and not a comment directive: a NAG is the PGN standard's own slot
/// for "how good was this move", so `$3` reaches every reader in the world as
/// `!!` while `$240` rides along to say *which* ChessEver class produced it.
/// `$1`–`$6` alone cannot: good and best both collapse to `!`, missed win and
/// blunder both to `??`, and book has no glyph at all. The block restores those
/// three distinctions losslessly for ChessEver mobile, ChessEver desktop and the
/// Cloudflare GIF renderer, with no `[%…]` directive to strip.
///
/// Codes sit far above the PGN spec's assigned range ($0–$139) and above the
/// ChessBase extensions ($140–$190ish), so nothing else claims them. A reader
/// that does not know them ignores them and still sees the standard glyph.
const kChesseverClassificationNags = <GameMoveClassification, int>{
  GameMoveClassification.brilliant: 240,
  GameMoveClassification.goodMove: 241,
  GameMoveClassification.bestMove: 242,
  GameMoveClassification.missedWin: 243,
  GameMoveClassification.inaccuracy: 244,
  GameMoveClassification.mistake: 245,
  GameMoveClassification.blunder: 246,
  GameMoveClassification.bookMove: 247,
};

final Map<int, GameMoveClassification> _classificationByNag = {
  for (final entry in kChesseverClassificationNags.entries)
    entry.value: entry.key,
};

/// The `$240`–`$247` code carrying [classification], or null when unclassified.
int? chesseverClassificationNag(GameMoveClassification? classification) =>
    classification == null ? null : kChesseverClassificationNags[classification];

/// Inverse of [chesseverClassificationNag].
GameMoveClassification? classificationForChesseverNag(int nag) =>
    _classificationByNag[nag];

/// Whether [nag] belongs to the ChessEver classification block.
bool isChesseverClassificationNag(int nag) =>
    _classificationByNag.containsKey(nag);

/// The ChessEver classification a move's NAGs carry, if any.
///
/// Presence of a block code also means "a ChessEver report judged this move",
/// which is what lets a reader show the badge instead of the imported glyph.
GameMoveClassification? classificationFromNags(Iterable<int>? nags) {
  if (nags == null) return null;
  for (final nag in nags) {
    final classification = _classificationByNag[nag];
    if (classification != null) return classification;
  }
  return null;
}

/// Legacy `[%chessever_annotation …]` comment directive.
///
/// No longer written — the `$240`–`$247` block replaced it. Still matched so
/// PGNs saved by shipped builds keep resolving, and so a re-export drops the
/// directive instead of carrying two competing sources of the same verdict.
final _legacyChesseverDirective = RegExp(
  r'\[%\s*chessever_annotation\s+[^\]]*\]',
  caseSensitive: false,
);

/// Legacy product slug for a report classification.
///
/// Kept for the Cloudflare renderer's own legacy path and for reading PGNs
/// written before the NAG block. Never emitted on export any more.
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

/// Classification carried by a legacy `[%chessever_annotation …]` directive.
GameMoveClassification? legacyClassificationFromComments(
  Iterable<String>? comments,
) {
  if (comments == null) return null;
  final pattern = RegExp(
    r'\[%\s*chessever_annotation\s+([^\]]+?)\s*\]',
    caseSensitive: false,
  );
  for (final comment in comments) {
    final token = pattern.firstMatch(comment)?.group(1)?.trim().toLowerCase();
    if (token == null || token.isEmpty) continue;
    final normalized = token.replaceAll(RegExp(r'[\s-]+'), '_');
    final classification = switch (normalized) {
      'brilliant' || '!!' => GameMoveClassification.brilliant,
      'good' || 'good_move' || 'great' => GameMoveClassification.goodMove,
      'best' || 'best_move' || 'top_move' => GameMoveClassification.bestMove,
      'missed_win' || 'missedwin' => GameMoveClassification.missedWin,
      'inaccuracy' || '?!' => GameMoveClassification.inaccuracy,
      'mistake' || '?' => GameMoveClassification.mistake,
      'blunder' || '??' => GameMoveClassification.blunder,
      'book' || 'book_move' => GameMoveClassification.bookMove,
      '!' => GameMoveClassification.goodMove,
      _ => null,
    };
    if (classification != null) return classification;
  }
  return null;
}

/// Mainline-index → classification for a game whose PGN carries ChessEver
/// annotations, so a device with no local report (a synced saved analysis, a
/// pasted share PGN) still renders the badges the report produced.
///
/// NAG block first, legacy directive second.
Map<int, GameMoveClassification> chesseverClassificationsFromMainline(
  ChessGame game,
) {
  final out = <int, GameMoveClassification>{};
  for (var index = 0; index < game.mainline.length; index++) {
    final move = game.mainline[index];
    final classification =
        classificationFromNags(move.nags) ??
        legacyClassificationFromComments(move.comments);
    if (classification != null) out[index] = classification;
  }
  return out;
}

/// Adds completed Game Analysis scores and classifications onto a [ChessGame]
/// before export (Copy PGN, Share PGN, and GIF).
///
/// A matching completed report is authoritative for every evaluated ply, so
/// freshly generated Game Analysis values replace older/default PGN values.
///
/// Every classified move gets two NAGs: the standard quality verdict
/// (`$1`/`$2`/`$3`/`$4`/`$6`) that any PGN reader understands, and the
/// ChessEver code (`$240`–`$247`, see [kChesseverClassificationNags]) that
/// names the exact class for our own apps and the GIF renderer. The report
/// owns the verdict, so imported `$1`–`$6` are dropped first — including on
/// moves it deliberately left unlabelled.
///
/// Legacy `[%chessever_annotation …]` comments are stripped, never written.
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
        final existingComments = move.comments ?? const <String>[];
        // Drop the legacy directive: this report's verdict now travels in the
        // NAGs, and a stale comment beside it would contradict them.
        final comments = <String>[
          for (final comment in existingComments)
            if (!_legacyChesseverDirective.hasMatch(comment))
              comment
            else if (comment
                .replaceAll(_legacyChesseverDirective, '')
                .trim()
                .isNotEmpty)
              comment.replaceAll(_legacyChesseverDirective, '').trim(),
        ];

        final classic = classicGlyphForClassification(
          reportMove.classification,
        );
        final reportNag = nagForClassicGlyph(classic);
        final chesseverNag = chesseverClassificationNag(
          reportMove.classification,
        );
        final existingNags = move.nags ?? const <int>[];
        // Strip both what the report displaces (imported $1–$6) and any earlier
        // ChessEver code, so a re-run never stacks two classifications.
        final nags =
            existingNags
                .where(
                  (nag) =>
                      !_moveVerdictNags.contains(nag) &&
                      !_classificationByNag.containsKey(nag),
                )
                .toList(growable: true);
        if (reportNag != null && !nags.contains(reportNag)) {
          nags.add(reportNag);
        }
        if (chesseverNag != null && !nags.contains(chesseverNag)) {
          nags.add(chesseverNag);
        }

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

/// Alias — GIF was the first consumer; identical hydrate to export, so the
/// PGN we render a GIF from is byte-for-byte the PGN the user copies.
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
