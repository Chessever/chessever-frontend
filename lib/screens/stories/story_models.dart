import 'dart:async';

import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/stories/story_replay.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// At most this many game stories per collection; a collection with more
/// ends in a See all story instead.
const int kStoryCap = 15;

/// How long one game story runs. Every game story fills its bar in the same
/// time, so the bar is honest: the replay is fitted to it, never the bar to
/// the replay.
const Duration kStoryGameDuration = Duration(seconds: 8);

/// How long the See all story runs before the viewer moves on.
const Duration kStorySeeAllDuration = Duration(seconds: 5);

/// How long a collection with no game to show holds before moving on.
const Duration kStoryEmptyDuration = Duration(seconds: 3);

/// One game story.
@immutable
class StoryGame {
  const StoryGame({required this.game, required this.replay, this.caption});

  /// Players, result and final position, as the collection's cards hold
  /// them (the browse preview: never board input).
  final GamesTourModel game;

  /// What the board shows while the story's bar fills.
  final StoryReplay replay;

  /// One line under the board: the event, the opening.
  final String? caption;

  String get id => game.gameId;
}

/// A collection's stories: its first games in the order its page lists
/// them, and how many it has in all.
@immutable
class StoryBatch {
  const StoryBatch({
    required this.games,
    required this.ordered,
    required this.total,
  });

  /// At most [kStoryCap] games, in the collection page's own order.
  final List<StoryGame> games;

  /// Every game of the collection as its page lists them (browse previews).
  /// "Open game" hands the board this list, exactly as the page does, so
  /// the board steps through the collection, not just the stories.
  final List<GamesTourModel> ordered;

  /// How many games the collection holds ("See all 87 games").
  final int total;

  /// Whether the stories end in a See all story.
  bool get seeAll => total > games.length;

  /// Stories in the viewer: one per game, then See all.
  int get storyCount => games.length + (seeAll ? 1 : 0);

  /// Whether story [index] is the See all story.
  bool isSeeAll(int index) => seeAll && index == games.length;

  /// How long story [index] runs.
  Duration durationOf(int index) =>
      isSeeAll(index) ? kStorySeeAllDuration : kStoryGameDuration;
}

/// Whether the stories viewer is on screen. The viewer is not a page route,
/// so the page under it hears this way that a route is over it (Today defers
/// its feed refreshes while it is, and catches up when it turns false).
final storyViewerOpenProvider = StateProvider<bool>((ref) => false);

/// Whether the stories viewer hides the page under it: it fills the screen
/// at rest, or a page opened from it (a game, a collection) is on top. Today
/// treats this as a page over it and stops its live cards' streams until the
/// viewer is gone ([storyViewerOpenProvider] turning false).
final storyViewerCoversProvider = StateProvider<bool>((ref) => false);

/// What a collection's stories are as of now: a collection that gets new
/// games (or new content) reads as unseen again.
String storySignature(Collection collection) =>
    '${collection.gameCount}:${collection.contentVersion ?? ''}';

/// The row's order: collections with stories the reader has not seen first,
/// then the seen ones, each group in the catalog's own order.
List<Collection> orderStoryCollections(
  List<Collection> collections,
  bool Function(Collection collection) seen,
) => [
  for (final c in collections)
    if (!seen(c)) c,
  for (final c in collections)
    if (seen(c)) c,
];

/// The viewer header's second line: who wrote it, or where and when it was
/// played.
String? storyByline(Collection c) {
  final byline = (c.author ?? c.annotator)?.trim();
  if (c.kind != CollectionKind.event) {
    return byline == null || byline.isEmpty ? c.subtitle : 'by $byline';
  }
  final year = c.publishedYear ?? c.dateStart?.year ?? c.dateEnd?.year;
  final location = c.location?.trim();
  final parts = [
    if (byline != null && byline.isNotEmpty) 'by $byline',
    if (year != null) '$year',
    if (location != null && location.isNotEmpty) location,
  ];
  return parts.isEmpty ? c.subtitle : parts.join(' · ');
}

/// [index] inside a batch of [count] stories (0 when it holds none).
int clampStoryIndex(int index, int count) =>
    count <= 0 ? 0 : index.clamp(0, count - 1);

/// The collections the Today row shows: every published collection that
/// holds a game, in the catalog's order. Held for a while after the row
/// leaves the screen, so switching tabs never refetches the catalog or
/// flashes the row's skeleton.
final storyCollectionsProvider = FutureProvider.autoDispose<List<Collection>>((
  ref,
) async {
  final link = _holdAfterLastListener(ref, const Duration(minutes: 10));
  try {
    final all = await ref.watch(collectionsProvider.future);
    return [
      for (final c in all)
        if (c.gameCount > 0) c,
    ];
  } catch (_) {
    // A failed read is never held: the row asks again ([TodayStoryRow]).
    link.close();
    rethrow;
  }
});

/// The order the collection page lists [contents] in by default: a book's
/// latest game first, anything else under its rounds and chapters.
List<CollectionGame> storyGameOrder(
  CollectionKind kind,
  CollectionContents contents,
) {
  if (kind == CollectionKind.book) {
    return collectionGamesNewestFirst(contents.games);
  }
  return [
    for (final group in groupCollectionGames(contents.sections, contents.games))
      ...group.games,
  ];
}

/// Whether the server lets this viewer read [detail]'s games, so their
/// moves may replay. A Premium collection's verdict comes from the detail
/// read; a collection that is locked shows its final positions only.
bool storyReplaysReadable(Collection detail) =>
    !detail.isPremium || detail.contentLocked == false;

/// The line under a game story's board.
String? storyCaption(CollectionGame game) {
  String? clean(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty || text == '?' ? null : text;
  }

  final eco = clean(game.card.eco);
  final opening = clean(game.card.opening);
  final parts = [
    ?clean(game.card.event),
    if (opening != null) eco == null ? opening : '$eco $opening' else ?eco,
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// [game]'s story: its PGN replayed when there is one, its final position
/// otherwise.
StoryGame buildStoryGame(CollectionGame game, {String? pgn}) {
  final preview = game.game;
  final replay =
      StoryReplay.fromPgn(pgn) ??
      StoryReplay.still(
        game.card.finalFen ?? preview.fen,
        _uciMove(game.card.lastMove ?? preview.lastMove),
      );
  return StoryGame(game: preview, replay: replay, caption: storyCaption(game));
}

Move? _uciMove(String? uci) {
  if (uci == null || uci.trim().isEmpty) return null;
  try {
    return Move.parse(uci.trim());
  } catch (_) {
    return null;
  }
}

/// How long the viewer waits for the replays' moves before it shows the
/// games' final positions instead.
const Duration kStoryReplayWait = Duration(seconds: 6);

/// One collection's stories, by slug: read once and kept warm for a few
/// minutes after the viewer lets them go, so reopening a circle is instant
/// and the next collection is ready before the reader reaches it.
///
/// The games are the collection page's own browse previews, in its order.
/// Their moves are read only when the server lets this viewer read them
/// ([storyReplaysReadable]), and never hold the stories up for long: a game
/// whose moves do not arrive shows its final position.
final storyBatchProvider = FutureProvider.autoDispose
    .family<StoryBatch, String>((ref, slug) async {
      final link = _holdAfterLastListener(ref, const Duration(minutes: 5));
      try {
        final contentsRead = ref.watch(collectionContentsProvider(slug).future);
        final detailRead = ref.watch(collectionDetailProvider(slug).future);
        final contents = await contentsRead;
        final detail = await detailRead;
        final ordered = storyGameOrder(detail.kind, contents);
        final shown = ordered.take(kStoryCap).toList();
        var pgns = const <String, String>{};
        if (shown.isNotEmpty && storyReplaysReadable(detail)) {
          try {
            // Only the stretches of the server's order that hold these
            // games are read with their moves, never the whole collection.
            pgns = await ref
                .read(collectionsRepositoryProvider)
                .fetchPgnsOf(
                  slug,
                  {for (final g in shown) g.id},
                  order: [for (final g in contents.games) g.id],
                )
                .timeout(kStoryReplayWait);
          } catch (e) {
            debugPrint('[Stories] $slug replays unavailable: $e');
          }
        }
        return StoryBatch(
          games: [for (final g in shown) buildStoryGame(g, pgn: pgns[g.id])],
          ordered: List.unmodifiable([for (final g in ordered) g.game]),
          total: ordered.length,
        );
      } catch (_) {
        // A failed read is never kept: the next look tries again.
        link.close();
        rethrow;
      }
    });

/// Keeps [ref]'s provider alive for [hold] after its last listener leaves.
KeepAliveLink _holdAfterLastListener(Ref ref, Duration hold) {
  final link = ref.keepAlive();
  Timer? release;
  ref.onCancel(() {
    release?.cancel();
    release = Timer(hold, link.close);
  });
  ref.onResume(() {
    release?.cancel();
    release = null;
  });
  ref.onDispose(() => release?.cancel());
  return link;
}
