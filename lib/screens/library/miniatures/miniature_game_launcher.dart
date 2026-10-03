import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_access.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/logger/logger.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/paywall/premium_game_access.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

bool _openingMiniature = false;

/// Opens a miniature on the board.
///
/// Miniature rows carry only a header-only PGN, so the real movetext has to be
/// fetched by game id before the board can replay anything. Every entry point
/// into the board from the Miniatures screen goes through here so the fetch,
/// the spinner and the error handling stay in one place.
///
/// Every game, including Today, requires paid or active rewarded Premium access.
/// Confirmation resumes the tapped game once, before fetching its movetext.
/// The list remains browsable and the unlocked board receives the whole list.
Future<void> openMiniatureGame({
  required BuildContext context,
  required WidgetRef ref,
  required List<GamesTourModel> games,
  required int index,
  String returnTo = kMiniaturesReturnTo,
}) async {
  if (index < 0 || index >= games.length) return;

  if (_openingMiniature || !context.mounted) return;
  _openingMiniature = true;
  try {
    final allowed = await ensurePremiumGameAccess(
      context,
      featureId: kMiniaturesArchiveFeatureId,
      returnTo: returnTo,
    );
    if (!allowed || !context.mounted) return;
    await _launchMiniatureGame(
      context: context,
      ref: ref,
      games: games,
      index: index,
    );
  } finally {
    _openingMiniature = false;
  }
}

Future<void> _launchMiniatureGame({
  required BuildContext context,
  required WidgetRef ref,
  required List<GamesTourModel> games,
  required int index,
}) async {
  if (!context.mounted) return;
  HapticFeedbackService.cardTap();

  // Board renders this as a tour-style game view.
  ref.read(chessboardViewFromProviderNew.notifier).state = ChessboardView.tour;

  showAlertModal<void>(
    context: context,
    barrierDismissible: false,
    child: Container(
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
    ),
  );

  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);

  try {
    final repo = ref.read(gamebaseRepositoryProvider);
    final gameWithPgn = await repo.getGameWithPgn(games[index].gameId);

    String? pgn;
    if (gameWithPgn != null) {
      final raw = gameWithPgn.pgn;
      if (raw != null && raw.trim().isNotEmpty && pgnHasMoves(raw)) {
        pgn = raw;
      }
      if (pgn == null && gameWithPgn.data != null) {
        final built = buildPgnFromGamebaseData(gameWithPgn.data);
        if (built != null && pgnHasMoves(built)) pgn = built;
      }
    }

    if (!context.mounted) return;
    navigator.pop(); // loading

    final boardGames = pgn == null
        ? games
        : [
            for (var i = 0; i < games.length; i++)
              i == index ? games[i].copyWith(pgn: pgn) : games[i],
          ];

    navigator.push(
      MaterialPageRoute(
        builder: (_) => ChessBoardScreenNew(
          games: boardGames,
          currentIndex: index,
          viewSource: ChessboardView.tour,
          playerProfileDataSource: PlayerProfileDataSource.twic,
          showGamebaseButton: false,
          disableGamebaseOverlayByDefault: true,
          showClock: false,
        ),
      ),
    );
  } catch (e, st) {
    talker.handle(e, st);
    if (!context.mounted) return;
    navigator.pop(); // loading
    showAppSnackOn(
      messenger,
      userFacingError(e, fallback: 'Could not open this game.'),
      tone: AppSnackTone.danger,
    );
  }
}
