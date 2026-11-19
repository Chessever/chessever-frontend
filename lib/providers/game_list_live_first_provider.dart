import 'dart:async';

import 'package:chessever2/providers/app_resume_signal_provider.dart';
import 'package:chessever2/providers/live_game_ids_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The day-grouped game lists that carry a one-tap Live first (Trello #1420).
enum GameListLiveFirstSurface { countrymen, favorites }

/// Whether a game list brings its live games to the top of the list.
///
/// Kept for the session per surface. The order itself is applied where each
/// list is grouped into days ([gatherLiveGamesFirst]), so the provider's own
/// query order stays untouched and turning it off restores it exactly.
final gameListLiveFirstProvider =
    StateProvider.family<bool, GameListLiveFirstSurface>(
      (ref, surface) => false,
    );

/// Snack shown when Live first is pressed while nothing is in play.
const String kNoLiveGamesRightNowMessage = 'No live games right now';

/// What a press of a game list's Live first did.
enum GameListLiveFirstPress { turnedOn, turnedOff, nothingLive }

/// Presses Live first for [surface].
///
/// Turning it off always works. Turning it on needs a game in play: one in
/// [liveIds], the server's answer the capsule counts, or, while that is
/// unknown (null), one in [games] (the list as it is on screen) that looks
/// live from its own row. With none, it stays off and a snack says there
/// are no live games right now, so the tap is never a silent no-op.
GameListLiveFirstPress pressGameListLiveFirst({
  required BuildContext context,
  required WidgetRef ref,
  required GameListLiveFirstSurface surface,
  required Iterable<GamesTourModel> games,
  Set<String>? liveIds,
}) {
  final controller = ref.read(gameListLiveFirstProvider(surface).notifier);
  if (controller.state) {
    controller.state = false;
    return GameListLiveFirstPress.turnedOff;
  }
  final anyLive = liveIds != null
      ? liveIds.isNotEmpty
      : games.any((game) => GameFilterHelper.isInPlay(game));
  if (!anyLive) {
    showAppSnack(context, kNoLiveGamesRightNowMessage);
    return GameListLiveFirstPress.nothingLive;
  }
  controller.state = true;
  return GameListLiveFirstPress.turnedOn;
}

/// The games a day-grouped list counts as in play: the server's [live] set
/// (`get_live_game_ids`, already scoped to the list's players and filter),
/// less any game the list already shows as finished, its row being newer
/// than the answer. Null while [live] is unknown, so the capsule says "See
/// live" rather than a guessed number.
///
/// Games of the set the loaded pages do not hold yet still count: Live first
/// lists them as it turns on (`ensureListed`), so what it lifts is what the
/// capsule said.
Set<String>? listedLiveGameIds(
  Set<String>? live,
  Iterable<GamesTourModel> listed,
) {
  if (live == null) return null;
  if (live.isEmpty) return const <String>{};
  final finished = <String>{
    for (final game in listed)
      if (game.effectiveGameStatus.isFinished && live.contains(game.gameId))
        game.gameId,
  };
  return finished.isEmpty ? live : live.difference(finished);
}

/// A game list's live-game poll ([LiveGameIdsNotifier]) paused while a
/// route (a board) covers its page, and asked once as the page comes back.
///
/// Shown again, the poll asks by itself when something it waits on changed
/// while it was paused: the live rounds ([liveRoundsIdProvider]) or an app
/// resume ([appResumedSignalProvider]). Back from a board with neither, the
/// page asks it here. Either way the return costs one request, never two
/// back to back.
class CoveredLiveGamesPoll {
  Set<String>? _liveRoundsAtCover;
  int? _resumesAtCover;

  /// The page is covered: [poll] waits. Already waiting, it keeps what it
  /// waited on from the first cover.
  void cover(WidgetRef ref, LiveGameIdsNotifier? poll) {
    if (poll == null) return;
    if (poll.visible) {
      _liveRoundsAtCover = _liveRounds(ref);
      _resumesAtCover = ref.read(appResumedSignalProvider);
    }
    poll.visible = false;
  }

  /// The page is in view again. With [ask] (back from a board, where games
  /// may have started or ended), the server is asked once.
  void uncover(WidgetRef ref, LiveGameIdsNotifier? poll, {bool ask = false}) {
    if (poll == null) return;
    final asksItself = !poll.visible && _changedSinceCover(ref);
    _liveRoundsAtCover = null;
    _resumesAtCover = null;
    poll.visible = true;
    if (ask && !asksItself) unawaited(poll.refresh());
  }

  /// The poll's own rule: any resume, or another set of live rounds (a
  /// first value is no change).
  bool _changedSinceCover(WidgetRef ref) {
    final resumes = _resumesAtCover;
    if (resumes != null && ref.read(appResumedSignalProvider) != resumes) {
      return true;
    }
    final before = _liveRoundsAtCover;
    final now = _liveRounds(ref);
    return before != null && now != null && !setEquals(before, now);
  }

  /// The live rounds as they stand. Never started from here: a running poll
  /// keeps them followed.
  static Set<String>? _liveRounds(WidgetRef ref) =>
      ref.exists(liveRoundsIdProvider)
      ? ref.read(liveRoundsIdProvider).valueOrNull?.toSet()
      : null;
}

/// Whether [game] is in play for a list's Live first: in [liveIds] once the
/// server has answered, by its own row ([GameFilterHelper.isInPlay]) while
/// that answer is unknown.
bool isListedGameLive(
  GamesTourModel game,
  Set<String>? liveIds, {
  DateTime? now,
}) => liveIds != null
    ? liveIds.contains(game.gameId)
    : GameFilterHelper.isInPlay(game, now: now);

/// A day-grouped list ([grouped]: day key to games, newest day first, the
/// [unknownKey] day last) with Live first applied: every game in play
/// ([isListedGameLive]) gathered at the head of the newest day, today at the
/// earliest, in the order the list had them, the day's other games after
/// them. Everything else keeps its day and its order; a day the move empties
/// is dropped.
///
/// A game in play is today's game, whatever day its row is filed under (a
/// round that started before midnight, a day ahead in the organiser's time
/// zone), so the live games read together where the list starts, which is
/// where turning Live first on takes the reader. Day keys are `yyyy-MM-dd`,
/// so they order as strings; [todayKey] is today's in the list's own
/// calendar.
Map<String, List<GamesTourModel>> gatherLiveGamesFirst(
  Map<String, List<GamesTourModel>> grouped, {
  required String todayKey,
  required String unknownKey,
  Set<String>? liveIds,
  DateTime? now,
}) {
  final live = <GamesTourModel>[];
  final rest = <String, List<GamesTourModel>>{};
  for (final entry in grouped.entries) {
    final kept = <GamesTourModel>[];
    for (final game in entry.value) {
      (isListedGameLive(game, liveIds, now: now) ? live : kept).add(game);
    }
    if (kept.isNotEmpty) rest[entry.key] = kept;
  }
  if (live.isEmpty) return grouped;

  var target = todayKey;
  for (final key in rest.keys) {
    if (key != unknownKey && key.compareTo(target) > 0) target = key;
  }
  final keys = {...rest.keys, target}.toList()
    ..sort((a, b) {
      if (a == unknownKey) return b == unknownKey ? 0 : 1;
      if (b == unknownKey) return -1;
      return b.compareTo(a);
    });
  return {
    for (final key in keys)
      key: key == target ? [...live, ...?rest[key]] : rest[key]!,
  };
}

/// [games] (in a list's order, [compare]) with [added] merged in, each
/// before the first listed game it sorts ahead of. The listed games keep
/// their exact order: nothing already on screen swaps places.
List<GamesTourModel> insertGamesInOrder(
  List<GamesTourModel> games,
  Iterable<GamesTourModel> added,
  int Function(GamesTourModel a, GamesTourModel b) compare,
) {
  final merged = List<GamesTourModel>.of(games);
  for (final game in added) {
    var index = merged.length;
    for (var i = 0; i < merged.length; i++) {
      if (compare(game, merged[i]) < 0) {
        index = i;
        break;
      }
    }
    merged.insert(index, game);
  }
  return merged;
}
