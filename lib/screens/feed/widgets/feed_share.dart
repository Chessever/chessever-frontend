import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/chessboard/utils/game_share_utils.dart';
import 'package:chessever2/screens/chessboard/widgets/share_game_screen.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/providers/feed_eval_provider.dart';
import 'package:chessever2/screens/feed/widgets/feed_format.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/utils/share_card.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Share for a Feed post: the board screen's own "Share Game" flow
/// (`shareGameBtnClicked` in the chess board screen), not a lookalike. The
/// same PGN ladder, the same snapshot, the same [pushGameShareScreen] overlay
/// with its image, GIF, PGN and link options, pinned to the position the
/// post shows.
///
/// [boardBoundary] is the post board's [RepaintBoundary]: like the board
/// screen, the card reuses those exact pixels (theme, piece set, badges)
/// instead of rebuilding a board. Null (or a boundary not yet painted) falls
/// back to the rebuilt board.
///
/// [eval] is the number on the post's eval bar for [shownPly], if any.
Future<void> shareFeedGame(
  BuildContext context,
  WidgetRef ref, {
  required FeedItem item,
  required int shownPly,
  GlobalKey? boardBoundary,
  FeedEval? eval,
}) async {
  // Read before any await: the post may be paged away mid-share.
  final games = ref.read(gameRepositoryProvider);
  final gamebase = ref.read(gamebaseRepositoryProvider);
  try {
    final game = item.game;
    final pgn = await resolveGameSharePgn(
      game: game,
      analysisGame: null,
      savedAnalysisData: null,
      fetchSupabasePgn: (gameId) async {
        try {
          return await games.getGamePgn(gameId);
        } catch (_) {
          return null;
        }
      },
      fetchGamebasePgn: (gameId) async {
        try {
          final full = await gamebase.getGameWithPgn(gameId);
          if (full == null) return null;
          for (final candidate in [
            buildPgnFromGamebaseData(full.data),
            full.pgn,
          ]) {
            final trimmed = candidate?.trim();
            if (trimmed != null && trimmed.isNotEmpty) return trimmed;
          }
          return null;
        } catch (_) {
          return null;
        }
      },
    );

    final base = buildGameShareSnapshot(game: game, pgn: pgn);
    final shown = shownPly.clamp(0, item.plies.length - 1);
    final snapshot = GameShareSnapshot(
      positionFen: item.plies[shown].fen,
      lastMove: _moveOf(item.plies[shown].uci),
      moveSans: base.moveSans,
      moveTimes: base.moveTimes,
      currentMoveIndex: shown - 1,
      startingFen: base.startingFen,
    );
    final boardImageBytes = boardBoundary == null || !context.mounted
        ? null
        : await captureBoundaryPng(boardBoundary, pixelRatio: 3);
    final pawns = eval?.pawns;
    final mate = eval?.mate;

    if (!context.mounted) return;
    await pushGameShareScreen(
      context: context,
      game: game.copyWith(pgn: pgn),
      shareData: ResolvedGameShareData(
        pgn: pgn,
        shareUrl: buildGameShareUrl(game: game.copyWith(pgn: pgn)),
        snapshot: snapshot,
        evaluation: mate != null && mate != 0
            ? (mate > 0 ? 10.0 : -10.0)
            : pawns,
        mate: mate ?? 0,
        isFlipped: false,
        isAtGameEnd:
            shown == item.plyCount && feedResultStatus(item).isFinished,
        boardImageBytes: boardImageBytes,
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    showAppSnack(
      context,
      'Failed to prepare game share',
      tone: AppSnackTone.danger,
    );
  }
}

Move? _moveOf(String? uci) {
  if (uci == null || uci.isEmpty) return null;
  try {
    return Move.parse(uci);
  } catch (_) {
    return null;
  }
}
