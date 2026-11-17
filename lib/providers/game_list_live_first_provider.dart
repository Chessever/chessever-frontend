import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The day-grouped game lists that carry a one-tap Live first (Trello #1420).
enum GameListLiveFirstSurface { countrymen, favorites }

/// Whether a game list brings its live games to the top of each day.
///
/// Kept for the session per surface. The order itself is applied where each
/// list is grouped into days ([liveGamesFirst]), so the provider's own query
/// order stays untouched and turning it off restores it exactly.
final gameListLiveFirstProvider =
    StateProvider.family<bool, GameListLiveFirstSurface>(
      (ref, surface) => false,
    );

/// Snack shown when Live first is pressed while nothing is in play.
const String kNoLiveGamesRightNowMessage = 'No live games right now';

/// Presses Live first for [surface].
///
/// Turning it off always works. Turning it on needs a live game in [games]
/// (the list as it is on screen): with none, it stays off and a snack says
/// there are no live games right now, so the tap is never a silent no-op.
void pressGameListLiveFirst({
  required BuildContext context,
  required WidgetRef ref,
  required GameListLiveFirstSurface surface,
  required Iterable<GamesTourModel> games,
}) {
  final controller = ref.read(gameListLiveFirstProvider(surface).notifier);
  if (controller.state) {
    controller.state = false;
    return;
  }
  if (!games.any((game) => GameFilterHelper.isLiveNow(game))) {
    showAppSnack(context, kNoLiveGamesRightNowMessage);
    return;
  }
  controller.state = true;
}

/// [games] with the ones in play first, keeping the given order on both sides
/// of the split. Returns the same list when nothing (or everything) is live.
List<GamesTourModel> liveGamesFirst(
  List<GamesTourModel> games, {
  DateTime? now,
}) {
  final live = <GamesTourModel>[];
  final rest = <GamesTourModel>[];
  for (final game in games) {
    (GameFilterHelper.isLiveNow(game, now: now) ? live : rest).add(game);
  }
  if (live.isEmpty || rest.isEmpty) return games;
  return [...live, ...rest];
}
