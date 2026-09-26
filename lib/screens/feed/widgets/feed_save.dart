import 'dart:async';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/chessboard/widgets/save_analysis_sheet.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Whether the viewer keeps the game [likeId] in one of their own
/// databases: a saved analysis of it in any folder but My Likes, since a
/// like alone is Like's state, not Save's. False for a signed-out viewer and
/// when the lookup fails: the button then offers Save, and the sheet it
/// opens reads the truth itself.
///
/// A copy is told from a like by the folder it sits in, read with it from
/// the database, never by the session's likes list: that list is loaded
/// once, so a like made on another device, an unlike still being deleted or
/// a like past its first page would pass for a save.
///
/// Kept for a few minutes after its post is paged away, so swiping back
/// shows it at once; Save refreshes it when its sheet closes.
final feedGameSavedProvider = FutureProvider.autoDispose.family<bool, String>((
  ref,
  likeId,
) async {
  if (ref.watch(currentUserProvider) == null) return false;
  final link = ref.keepAlive();
  final expiry = Timer(const Duration(minutes: 5), link.close);
  ref.onDispose(expiry.cancel);
  try {
    final copies = await ref
        .read(libraryRepositoryProvider)
        .getSavedAnalysesBySourceGame(sourceGameId: likeId);
    if (copies.isEmpty) return false;
    final likesFolder = await _likesFolderId(ref);
    if (likesFolder != null) {
      return copies.any((copy) => copy.folderId != likesFolder);
    }
    // No My Likes folder to go by: the likes the session holds are the best
    // word there is.
    final liked = ref.read(likedGamesProvider).valueOrNull ?? const [];
    final likeRows = {for (final row in liked) row.id};
    return copies.any((copy) => !likeRows.contains(copy.id));
  } catch (error) {
    debugPrint('[Feed] saved lookup failed: $error');
    return false;
  }
});

/// The viewer's My Likes folder, the one every like is written to; null when
/// it cannot be read.
Future<String?> _likesFolderId(Ref ref) async {
  try {
    return (await ref.read(likedGamesFolderProvider.future)).id;
  } catch (error) {
    debugPrint('[Feed] My Likes folder lookup failed: $error');
    return null;
  }
}

/// Shows the save sheet for a loaded board. [showSaveAnalysisSheet] itself;
/// a seam so tests can stand in for the sheet.
typedef FeedSaveSheet =
    Future<void> Function({
      required BuildContext context,
      required ChessBoardStateNew state,
      required ChessBoardProviderParams params,
    });

final feedSaveSheetProvider = Provider<FeedSaveSheet>(
  (ref) => showSaveAnalysisSheet,
);

/// A board index no board screen page ever has. The save sheet is built on
/// the board's own provider, which evaluates only the visible page: on this
/// index it parses the game for the sheet and never takes the engine the
/// Feed is using.
const int kFeedSaveBoardIndex = -1;

/// Save for a Feed post: the board screen's own Save (its auth guard, then
/// [showSaveAnalysisSheet] with databases, a new database and tags) for
/// [game], the way the opening explorer opens it over its own page.
///
/// The sheet is built on the board provider, which nothing on the Feed
/// watches: a manual subscription holds it from the parse until the sheet
/// closes, and the sheet reads the same provider by its params. The board
/// starts on the game's last move, so the saved analysis opens there.
Future<void> openFeedSaveSheet({
  required BuildContext context,
  required WidgetRef ref,
  required GamesTourModel game,
}) async {
  final allowed = await requireFullAuthGuard(context);
  if (!allowed || !context.mounted) return;

  final params = ChessBoardProviderParams(
    game: game,
    index: kFeedSaveBoardIndex,
    startAtLastMove: true,
  );
  final loaded = Completer<ChessBoardStateNew?>();
  final subscription = ref.listenManual<AsyncValue<ChessBoardStateNew>>(
    chessBoardScreenProviderNew(params),
    (_, next) {
      if (loaded.isCompleted) return;
      final board = next.valueOrNull;
      if (board != null &&
          !board.isLoadingMoves &&
          board.analysisState.game != null) {
        loaded.complete(board);
      } else if (next.hasError) {
        loaded.complete(null);
      }
    },
    fireImmediately: true,
  );
  try {
    final board = await loaded.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => null,
    );
    if (!context.mounted) return;
    if (board == null) {
      // The board screen's own words for a game it has not parsed yet.
      showAppSnack(context, 'Please wait for the game to load');
      return;
    }
    await ref.read(feedSaveSheetProvider)(
      context: context,
      state: board,
      params: params,
    );
  } finally {
    subscription.close();
  }
}
