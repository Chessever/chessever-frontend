import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';

/// Returns games in the same display order used by event game lists.
///
/// Pinned games are promoted ahead of unpinned games, but pinned games still
/// use the event's board/round ordering instead of the order in which they
/// were pinned or auto-pinned.
List<Games> sortGamesForEventDisplay(
  List<Games> games, {
  required List<String> pinnedIds,
  bool prioritizePins = true,
}) {
  if (games.isEmpty) return const <Games>[];

  final gameInfo = <String, (int, int)>{};
  for (final game in games) {
    gameInfo[game.id] = (
      extractRoundNumberFromSlug(game.roundSlug),
      extractGameNumberFromSlug(game.roundSlug),
    );
  }

  final sortedGames = List<Games>.from(games);
  sortedGames.sort((a, b) {
    if (prioritizePins) {
      final aPinned = pinnedIds.contains(a.id);
      final bPinned = pinnedIds.contains(b.id);
      if (aPinned != bPinned) return aPinned ? -1 : 1;
    }

    final (roundA, gameA) = gameInfo[a.id] ?? (0, 0);
    final (roundB, gameB) = gameInfo[b.id] ?? (0, 0);

    // Current/live rounds are rendered first by the existing event UI.
    if (roundA != roundB) return roundB.compareTo(roundA);

    // Preserve existing match/game ordering inside a round when available.
    if (gameA != gameB) return gameB.compareTo(gameA);

    // Board order is the stable canonical order inside the pinned and
    // unpinned groups. Missing board numbers go after numbered boards.
    final aBoard = a.boardNr, bBoard = b.boardNr;
    if (aBoard != null && bBoard != null) return aBoard.compareTo(bBoard);
    if (aBoard != null) return -1;
    if (bBoard != null) return 1;
    return 0;
  });

  return sortedGames;
}

/// Same ordering as [sortGamesForEventDisplay], for already mapped card models.
List<GamesTourModel> sortGameModelsForEventDisplay(
  List<GamesTourModel> games, {
  required List<String> pinnedIds,
  bool prioritizePins = true,
}) {
  if (games.isEmpty) return const <GamesTourModel>[];

  final sortedGames = List<GamesTourModel>.from(games);
  sortedGames.sort((a, b) {
    if (prioritizePins) {
      final aPinned = pinnedIds.contains(a.gameId);
      final bPinned = pinnedIds.contains(b.gameId);
      if (aPinned != bPinned) return aPinned ? -1 : 1;
    }

    final roundA = extractRoundNumberFromSlug(a.roundSlug ?? '');
    final roundB = extractRoundNumberFromSlug(b.roundSlug ?? '');
    if (roundA != roundB) return roundB.compareTo(roundA);

    final gameA = extractGameNumberFromSlug(a.roundSlug ?? '');
    final gameB = extractGameNumberFromSlug(b.roundSlug ?? '');
    if (gameA != gameB) return gameB.compareTo(gameA);

    final aBoard = a.boardNr, bBoard = b.boardNr;
    if (aBoard != null && bBoard != null) return aBoard.compareTo(bBoard);
    if (aBoard != null) return -1;
    if (bBoard != null) return 1;
    return 0;
  });

  return sortedGames;
}

int extractRoundNumberFromSlug(String roundSlug) {
  final match =
      RegExp(r'round-?(\d+)', caseSensitive: false).firstMatch(roundSlug) ??
      RegExp(r'(\d+)').firstMatch(roundSlug);
  return int.tryParse(match?.group(1) ?? '0') ?? 0;
}

int extractGameNumberFromSlug(String roundSlug) {
  final match = RegExp(
    r'game-?(\d+)',
    caseSensitive: false,
  ).firstMatch(roundSlug);
  return int.tryParse(match?.group(1) ?? '0') ?? 0;
}
