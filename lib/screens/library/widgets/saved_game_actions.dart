import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/chessboard/utils/game_share_utils.dart';
import 'package:chessever2/screens/chessboard/widgets/share_game_screen.dart';
import 'package:chessever2/screens/library/utils/load_saved_analysis.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/library/widgets/move_game_to_database_sheet.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/logger/logger.dart';
import 'package:chessever2/utils/pgn_export_utils.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Long-press menu for a saved game in the library.
///
/// Mirrors the desktop app's board/library right-click menu on touch: the same
/// actions the board exposes behind its 3-dot and save buttons (share, copy
/// PGN, edit & annotate) plus the library-only ones (move, delete), so a game
/// can be managed without opening it first.
///
/// Pass the *card's own* [context] — the menu anchors to that render box.
/// [onDelete] is the host's existing remove handler (it owns the undo snack and
/// list refresh); omit it to hide the destructive row. [readOnly] is for games
/// inside a subscribed database, which the user does not own. [locked] is a
/// paywalled My Likes card: the game's content stays behind the paywall, so
/// only opening (which raises it) and removing are offered.
Future<void> showSavedGameActions({
  required BuildContext context,
  required SavedAnalysis analysis,
  required VoidCallback onOpen,
  WidgetBuilder? previewBuilder,
  Future<void> Function()? onDelete,
  String deleteLabel = 'Delete game',
  IconData deleteIcon = Icons.delete_outline_rounded,
  VoidCallback? onChanged,
  bool readOnly = false,
  bool locked = false,
}) {
  final actions = <LibraryMenuAction>[
    LibraryMenuAction(
      icon: Icons.open_in_new_rounded,
      label: 'Open game',
      onSelected: onOpen,
    ),
    if (!readOnly && !locked)
      LibraryMenuAction(
        icon: Icons.edit_note_rounded,
        label: 'Edit & annotate',
        onSelected: () => _editAndAnnotate(context, analysis, onChanged),
      ),
    if (!locked) ...[
      LibraryMenuAction(
        icon: Icons.ios_share_rounded,
        label: 'Share game',
        onSelected: () => _shareGame(context, analysis),
      ),
      LibraryMenuAction(
        icon: Icons.copy_rounded,
        label: 'Copy PGN',
        onSelected: () => _copyPgn(context, analysis),
      ),
      LibraryMenuAction(
        icon: Icons.content_paste_go_rounded,
        label: 'Copy FEN',
        onSelected: () => _copyFen(context, analysis),
      ),
    ],
    if (!readOnly && !locked)
      LibraryMenuAction(
        icon: Icons.drive_file_move_rounded,
        label: 'Move to database',
        onSelected:
            () => showMoveGameToDatabaseSheet(
              context: context,
              analysis: analysis,
              onMoved: onChanged,
            ),
      ),
    if (!readOnly && onDelete != null)
      LibraryMenuAction(
        icon: deleteIcon,
        label: deleteLabel,
        destructive: true,
        onSelected: onDelete,
      ),
  ];

  return showLibraryContextMenu(
    context: context,
    actions: actions,
    previewBuilder: previewBuilder,
    onPreviewTap: onOpen,
  );
}

/// Opens the game and raises the Save Analysis sheet as soon as the board is
/// ready — the same sheet the board's save button opens, which is where title,
/// database and tags are edited.
Future<void> _editAndAnnotate(
  BuildContext context,
  SavedAnalysis analysis,
  VoidCallback? onChanged,
) async {
  await loadSavedAnalysis(context, analysis, showSaveAnalysisOnLoad: true);
  onChanged?.call();
}

Future<String> _resolvePgn(SavedAnalysis analysis, GamesTourModel game) {
  return resolveGameSharePgn(
    game: game,
    analysisGame: analysis.chessGame,
    savedAnalysisData: null,
  );
}

Future<void> _copyPgn(BuildContext context, SavedAnalysis analysis) async {
  try {
    final game = convertSavedAnalysisToGame(analysis);
    final pgn = await _resolvePgn(analysis, game);
    if (pgn.trim().isEmpty) {
      if (!context.mounted) return;
      showAppSnack(context, 'No PGN available for this game');
      return;
    }
    await Clipboard.setData(ClipboardData(text: canonicalizePgnForExport(pgn)));
    HapticFeedback.lightImpact();
    if (!context.mounted) return;
    showAppSnack(context, 'PGN copied to clipboard');
  } catch (e, st) {
    talker.handle(e, st);
    if (!context.mounted) return;
    showAppSnack(context, 'Failed to copy PGN', tone: AppSnackTone.danger);
  }
}

/// Copies the FEN of the game's final position — the same position the card's
/// result refers to, and what a player pastes into an engine or a study.
Future<void> _copyFen(BuildContext context, SavedAnalysis analysis) async {
  try {
    final game = convertSavedAnalysisToGame(analysis);
    final pgn = await _resolvePgn(analysis, game);
    final fen = buildGameShareSnapshot(game: game, pgn: pgn).positionFen;
    await Clipboard.setData(ClipboardData(text: fen));
    HapticFeedback.lightImpact();
    if (!context.mounted) return;
    showAppSnack(context, 'FEN copied to clipboard');
  } catch (e, st) {
    talker.handle(e, st);
    if (!context.mounted) return;
    showAppSnack(context, 'Failed to copy FEN', tone: AppSnackTone.danger);
  }
}

Future<void> _shareGame(BuildContext context, SavedAnalysis analysis) async {
  try {
    final game = convertSavedAnalysisToGame(analysis);
    final pgn = await _resolvePgn(analysis, game);
    final snapshot = buildGameShareSnapshot(game: game, pgn: pgn);

    final isFinished =
        game.gameStatus != GameStatus.ongoing &&
        game.gameStatus != GameStatus.unknown;

    if (!context.mounted) return;
    await pushGameShareScreen(
      context: context,
      game: game,
      shareData: ResolvedGameShareData(
        pgn: pgn,
        shareUrl: buildGameShareUrl(
          game: game,
          savedAnalysisData: createSavedAnalysisData(analysis),
        ),
        snapshot: snapshot,
        evaluation: null,
        mate: 0,
        isFlipped: false,
        isAtGameEnd: isFinished,
      ),
    );
  } catch (e, st) {
    talker.handle(e, st);
    if (!context.mounted) return;
    showAppSnack(
      context,
      'Failed to prepare game share',
      tone: AppSnackTone.danger,
    );
  }
}
