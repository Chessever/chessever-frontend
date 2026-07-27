import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/chessboard/utils/game_share_utils.dart';
import 'package:chessever2/screens/chessboard/widgets/share_game_screen.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/logger/logger.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Share / copy actions for archive (gamebase, TWIC, broadcast) games that are
/// not saved analyses. Unlike a saved game, the moves usually still have to be
/// fetched, so each entry point resolves the PGN behind a short blocking
/// spinner before doing its work.

/// Resolves the fullest PGN available for [game]: the model's own moves first,
/// then Supabase, then the gamebase archive — the same ladder the board uses.
Future<String> _resolvePgn(WidgetRef ref, GamesTourModel game) {
  return resolveGameSharePgn(
    game: game,
    analysisGame: null,
    savedAnalysisData: null,
    fetchSupabasePgn: (gameId) async {
      try {
        return await ref.read(gameRepositoryProvider).getGamePgn(gameId);
      } catch (_) {
        return null;
      }
    },
    fetchGamebasePgn: (gameId) async {
      try {
        final full = await ref
            .read(gamebaseRepositoryProvider)
            .getGameWithPgn(gameId);
        if (full == null) return null;
        return selectGamebaseBoardPgn(rawPgn: full.pgn, data: full.data);
      } catch (_) {
        return null;
      }
    },
  );
}

/// Runs [action] with a resolved PGN, holding a spinner while the fetch is in
/// flight so a slow network never reads as a dead menu item.
Future<void> _withPgn(
  BuildContext context,
  WidgetRef ref,
  GamesTourModel game,
  Future<void> Function(String pgn) action, {
  required String failureMessage,
}) async {
  // Captured from inside the dialog so it is popped by its own route rather
  // than by whatever happens to be on top when the fetch settles.
  BuildContext? spinnerContext;
  _showSpinner(context, (ctx) => spinnerContext = ctx);

  String? pgn;
  try {
    pgn = await _resolvePgn(ref, game);
  } catch (e, st) {
    talker.handle(e, st);
  }

  // A cached PGN can resolve before the dialog route has built once, which
  // would leave the spinner stranded with no context to pop it by.
  if (spinnerContext == null) {
    await WidgetsBinding.instance.endOfFrame;
  }

  final spinner = spinnerContext;
  if (spinner != null && spinner.mounted) {
    Navigator.of(spinner).pop();
  }

  if (!context.mounted) return;

  if (pgn == null || pgn.trim().isEmpty) {
    showAppSnack(context, failureMessage, tone: AppSnackTone.danger);
    return;
  }

  await action(pgn);
}

/// Fire-and-forget spinner: the modal is popped by [_withPgn] once the fetch
/// settles, so its own future is intentionally not awaited here.
void _showSpinner(BuildContext context, ValueChanged<BuildContext> onContext) {
  showAlertModal<void>(
    context: context,
    barrierDismissible: false,
    child: Builder(
      builder: (dialogContext) {
        onContext(dialogContext);
        return Container(
          padding: EdgeInsets.all(20.sp),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(16.br),
            border: Border.all(
              color: context.colors.textPrimary.withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          child: CircularProgressIndicator(color: context.colors.textPrimary),
        );
      },
    ),
  );
}

Future<void> copyArchiveGamePgn({
  required BuildContext context,
  required WidgetRef ref,
  required GamesTourModel game,
}) {
  return _withPgn(
    context,
    ref,
    game,
    failureMessage: 'No PGN available for this game',
    (pgn) async {
      await Clipboard.setData(ClipboardData(text: pgn));
      HapticFeedback.lightImpact();
      if (!context.mounted) return;
      showAppSnack(context, 'PGN copied to clipboard');
    },
  );
}

Future<void> copyArchiveGameFen({
  required BuildContext context,
  required WidgetRef ref,
  required GamesTourModel game,
}) {
  return _withPgn(
    context,
    ref,
    game,
    failureMessage: 'No position available for this game',
    (pgn) async {
      final fen = buildGameShareSnapshot(game: game, pgn: pgn).positionFen;
      await Clipboard.setData(ClipboardData(text: fen));
      HapticFeedback.lightImpact();
      if (!context.mounted) return;
      showAppSnack(context, 'FEN copied to clipboard');
    },
  );
}

Future<void> shareArchiveGame({
  required BuildContext context,
  required WidgetRef ref,
  required GamesTourModel game,
}) {
  return _withPgn(
    context,
    ref,
    game,
    failureMessage: 'Failed to prepare game share',
    (pgn) async {
      final snapshot = buildGameShareSnapshot(game: game, pgn: pgn);
      final isFinished =
          game.gameStatus != GameStatus.ongoing &&
          game.gameStatus != GameStatus.unknown;

      if (!context.mounted) return;
      await pushGameShareScreen(
        context: context,
        game: game.copyWith(pgn: pgn),
        shareData: ResolvedGameShareData(
          pgn: pgn,
          shareUrl: buildGameShareUrl(game: game.copyWith(pgn: pgn)),
          snapshot: snapshot,
          evaluation: null,
          mate: 0,
          isFlipped: false,
          isAtGameEnd: isFinished,
        ),
      );
    },
  );
}
