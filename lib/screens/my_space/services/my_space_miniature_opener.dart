import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/gamebase/models/gamebase_game.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Opens a My Space Miniature only after hydrating a complete canonical game.
///
/// Summary metadata never becomes a fabricated PGN. If Gamebase cannot return
/// a move-bearing game document, the caller receives an honest failure.
Future<void> openMySpaceMiniature({
  required BuildContext context,
  required WidgetRef ref,
  required GamebaseMiniature miniature,
}) async {
  final fullGame = await ref
      .read(gamebaseRepositoryProvider)
      .getGameWithPgn(miniature.canonicalGameId);
  if (fullGame == null) {
    throw const MySpaceMiniatureOpenException(
      'The complete game is unavailable right now. Try again.',
    );
  }

  final builtPgn = buildPgnFromGamebaseData(fullGame.data);
  String? playablePgn;
  for (final candidate in <String?>[fullGame.pgn, builtPgn]) {
    final normalized = candidate?.trim();
    if (normalized != null &&
        normalized.isNotEmpty &&
        pgnHasMoves(normalized)) {
      playablePgn = normalized;
      break;
    }
  }
  if (playablePgn == null) {
    throw const MySpaceMiniatureOpenException(
      'This miniature has no complete move record, so it cannot be opened.',
    );
  }
  if (!context.mounted) return;

  final game = _toBoardGame(
    miniature: miniature,
    fullGame: fullGame,
    pgn: playablePgn,
  );
  ref
      .read(gameCardWrapperProvider)
      .navigateToChessBoard(
        context: context,
        orderedGames: <GamesTourModel>[game],
        gameIndex: 0,
        onReturnFromChessboard: (_) {},
        viewSource: ChessboardView.tour,
        hideEventInfo: true,
        showGamebaseButton: false,
        disableGamebaseOverlayByDefault: true,
        showClock: false,
      );
}

final class MySpaceMiniatureOpenException implements Exception {
  const MySpaceMiniatureOpenException(this.message);

  final String message;

  @override
  String toString() => message;
}

GamesTourModel _toBoardGame({
  required GamebaseMiniature miniature,
  required GamebaseGameWithPgn fullGame,
  required String pgn,
}) {
  final whiteName =
      _firstText(<String?>[fullGame.whiteName, miniature.whiteName]) ?? 'White';
  final blackName =
      _firstText(<String?>[fullGame.blackName, miniature.blackName]) ?? 'Black';
  final event =
      _firstText(<String?>[fullGame.event, miniature.event]) ?? 'Miniatures';
  final eco = _firstText(<String?>[fullGame.eco, miniature.eco]);
  final opening = _combinedOpening(
    opening: _firstText(<String?>[fullGame.opening, miniature.opening]),
    variation: _firstText(<String?>[fullGame.variation, miniature.variation]),
  );

  return GamesTourModel(
    gameId: miniature.canonicalGameId,
    source: GameSource.gamebase,
    whitePlayer: PlayerCard(
      name: whiteName,
      federation: miniature.whiteFed?.trim() ?? '',
      title: '',
      rating: _safeRating(fullGame.whiteElo ?? miniature.whiteElo),
      countryCode: miniature.whiteFed?.trim() ?? '',
      team: null,
      gamebasePlayerId: miniature.whitePlayerId?.trim(),
    ),
    blackPlayer: PlayerCard(
      name: blackName,
      federation: miniature.blackFed?.trim() ?? '',
      title: '',
      rating: _safeRating(fullGame.blackElo ?? miniature.blackElo),
      countryCode: miniature.blackFed?.trim() ?? '',
      team: null,
      gamebasePlayerId: miniature.blackPlayerId?.trim(),
    ),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus:
        miniature.result == MiniatureGameResult.whiteWins
            ? GameStatus.whiteWins
            : GameStatus.blackWins,
    roundId: 'gamebase-miniatures',
    roundSlug: eco,
    tourId: event,
    tourSlug: _firstText(<String?>[fullGame.site]),
    pgn: pgn,
    boardNr: miniature.finalMoveNumber > 0 ? miniature.finalMoveNumber : null,
    lastMoveTime: miniature.date ?? fullGame.date,
    dateStart: miniature.date ?? fullGame.date,
    gameDay: miniature.date ?? fullGame.date,
    eco: eco,
    openingName: opening,
    timeControl: _timeControlName(miniature.timeControl),
    avgElo: miniature.avgRating,
    isOnline: miniature.isOnline,
    sourceGameId: miniature.canonicalGameId,
  );
}

String? _firstText(Iterable<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  }
  return null;
}

String? _combinedOpening({
  required String? opening,
  required String? variation,
}) {
  if (opening == null) return variation;
  if (variation == null || variation == opening) return opening;
  return '$opening · $variation';
}

int _safeRating(int? rating) {
  return rating == null || rating < 0 || rating > 4000 ? 0 : rating;
}

String _timeControlName(MiniatureGameTimeControl control) => switch (control) {
  MiniatureGameTimeControl.classical => 'Classical',
  MiniatureGameTimeControl.rapid => 'Rapid',
  MiniatureGameTimeControl.blitz => 'Blitz',
};
