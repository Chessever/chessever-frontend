import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:chessever2/repository/library/library_game_event.dart'
    show eventTitleFromPgnHeaders;
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/for_you/discovery/data/discovery_repository.dart';
import 'package:chessever2/screens/for_you/discovery/models/report_game_type.dart';
import 'package:chessever2/screens/stories/story_moments.dart';
import 'package:chessever2/screens/stories/story_row_prefs.dart'
    show storyClockProvider, storyDayKey;
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/average_game_rating.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

export 'package:chessever2/screens/stories/story_moments.dart';

/// At most this many collection circles on the row: the ones updated most
/// recently. A collection that gets a new game or an update moves in.
const int kStoryCollectionCap = 8;

/// At most this many stories per collection: its latest game, then up to
/// two others picked for the day.
const int kStoriesPerCollection = 3;

/// A game must show at least this many positions to be a story: a game
/// with one moment is not a story of its own (the latest game included).
const int kStoryMinSegments = 2;

/// How many games, besides the latest, are read to find the day's picks.
const int kStoryCandidatePool = 8;

/// Missed chances shows at most this many games a day.
const int kMissedChancesPerDay = 3;

/// How long a collection with no game to show holds before moving on.
const Duration kStoryEmptyDuration = Duration(seconds: 3);

/// One game story: up to [kStoryMaxSegments] key positions of one game.
@immutable
class StoryGame {
  const StoryGame({required this.game, required this.segments, this.caption});

  /// Players and result as the collection's cards (or the report list)
  /// hold them.
  final GamesTourModel game;

  /// The positions shown, in game order. Never empty.
  final List<StorySegment> segments;

  /// One line over the moment: the event, the opening.
  final String? caption;

  String get id => game.gameId;
}

/// One page of the viewer: segment [segment] of story [story].
@immutable
class StoryFrame {
  const StoryFrame({
    required this.story,
    required this.segment,
    required this.game,
  });

  final int story;
  final int segment;
  final StoryGame game;

  StorySegment get position => game.segments[segment];

  /// The story's first page, after the first story: the bars leave more
  /// room before it.
  bool get startsStory => segment == 0;

  /// The story's last page: watching it sees the story.
  bool get endsStory => segment == game.segments.length - 1;

  String get id => '${game.id}#$segment';
}

/// A collection's stories, and the games its page lists (for Open game).
@immutable
class StoryBatch {
  StoryBatch({
    required this.games,
    required this.ordered,
    int? total,
    this.gameCount,
    this.signature,
  }) : total = total ?? ordered.length,
       frames = List.unmodifiable([
         for (var s = 0; s < games.length; s++)
           for (var p = 0; p < games[s].segments.length; p++)
             StoryFrame(story: s, segment: p, game: games[s]),
       ]);

  /// The stories, each one game.
  final List<StoryGame> games;

  /// Every game the board steps through from Open game: the collection's
  /// own list, or a Missed chances day's games.
  final List<GamesTourModel> ordered;

  /// How many games the collection holds.
  final int total;

  /// The collection's game count when these stories were read.
  final int? gameCount;

  /// The collection's news signature ([storySignature]) these stories were
  /// read under: watching them all catches the reader up to it.
  final String? signature;

  /// The viewer's pages: every story's positions, in order.
  final List<StoryFrame> frames;

  /// Pages in the viewer.
  int get storyCount => frames.length;

  StoryFrame? frameAt(int index) =>
      index < 0 || index >= frames.length ? null : frames[index];

  /// How long page [index] runs.
  Duration durationOf(int index) {
    final frame = frameAt(index);
    return frame == null
        ? kStoryEmptyDuration
        : storySegmentDuration(frame.position);
  }

  /// The page story [story] opens on.
  int firstFrameOf(int story) =>
      frames.indexWhere((f) => f.story == story && f.segment == 0);

  /// Where [gameId]'s story is in [ordered], for the board.
  int orderedIndexOf(String gameId) =>
      ordered.indexWhere((g) => g.gameId == gameId);
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

// ------------------------------------------------------------ Missed chances

/// The slug of the Missed chances circle: never a collection's.
const String kMissedChancesSlug = '\u0000missed_chances';

/// Whether [collection] is the Missed chances circle.
bool isMissedChances(Collection collection) =>
    collection.slug == kMissedChancesSlug;

/// The Missed chances circle for the local day of [now]: a new set of games
/// each day, so its signature is the day.
Collection missedChancesCollection(DateTime now) {
  final day = storyDayKey(now);
  return Collection(
    id: kMissedChancesSlug,
    slug: kMissedChancesSlug,
    kind: CollectionKind.event,
    title: 'Missed chances',
    subtitle: 'Wins that got away',
    gameCount: kMissedChancesPerDay,
    contentVersion: 'missed:$day',
    updatedAt: DateTime(now.year, now.month, now.day),
    access: CollectionAccess.free,
  );
}

// ------------------------------------------------------------------ the row

/// What makes a collection new to the reader: a new game or an update
/// changes its content version (the server bumps it on every rebuild of the
/// collection's games), else its game count.
String storySignature(Collection c) =>
    c.contentVersion?.trim().isNotEmpty == true
    ? 'v:${c.contentVersion}'
    : 'n:${c.gameCount}';

/// When [c] last changed, for the row's order: its update, else when it
/// was published or played.
DateTime? storyRecency(Collection c) =>
    c.updatedAt ?? c.publishedAt ?? c.dateEnd ?? c.dateStart;

int _byRecency(Collection a, Collection b) {
  final ra = storyRecency(a);
  final rb = storyRecency(b);
  if (ra == null || rb == null) {
    if (ra != null) return -1;
    if (rb != null) return 1;
    return 0;
  }
  return rb.compareTo(ra);
}

/// The collections the row shows: the [cap] updated most recently, in that
/// order (catalog order between equals).
List<Collection> selectStoryCollections(
  List<Collection> catalog, {
  int cap = kStoryCollectionCap,
}) {
  final indexed = [for (var i = 0; i < catalog.length; i++) (i, catalog[i])];
  indexed.sort((a, b) {
    final byRecency = _byRecency(a.$2, b.$2);
    return byRecency != 0 ? byRecency : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed.take(cap)) e.$2];
}

/// The row's order: what arrived while the row was put away ([fresh], by
/// slug) first, then circles with something the reader has not seen, then
/// the seen ones, each group most recently updated first. A collection
/// that gets a new game lands leftmost.
List<Collection> orderStoryCollections(
  List<Collection> collections,
  bool Function(Collection collection) seen, {
  Set<String> fresh = const {},
}) {
  final indexed = [
    for (var i = 0; i < collections.length; i++) (i, collections[i]),
  ];
  int group(Collection c) => fresh.contains(c.slug)
      ? 0
      : seen(c)
      ? 2
      : 1;
  indexed.sort((a, b) {
    final byGroup = group(a.$2).compareTo(group(b.$2));
    if (byGroup != 0) return byGroup;
    final byRecency = _byRecency(a.$2, b.$2);
    return byRecency != 0 ? byRecency : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// The viewer header's second line: who wrote it, or where and when it was
/// played.
String? storyByline(Collection c) {
  if (isMissedChances(c)) return c.subtitle;
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

/// [index] inside a batch of [count] pages (0 when it holds none).
int clampStoryIndex(int index, int count) =>
    count <= 0 ? 0 : index.clamp(0, count - 1);

/// Which page [index] of [batch] is ([StoryFrame.id]), or null when the
/// batch has no such page.
String? storyIdAt(StoryBatch batch, int index) => batch.frameAt(index)?.id;

/// Where page [id] ([storyIdAt]) is in [batch] now; null when it is gone.
/// A re-read can put new games before it.
int? storyIndexOf(StoryBatch batch, String id) {
  final index = batch.frames.indexWhere((f) => f.id == id);
  return index < 0 ? null : index;
}

/// The collections the Today row can show: every published collection that
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

// ------------------------------------------------------------ the stories

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
/// positions can be read. A locked Premium collection shows its latest
/// game's final position only (opening it is gated, as on its page).
bool storyMovesReadable(Collection detail) =>
    !detail.isPremium || detail.contentLocked == false;

/// The line over a game story's moment.
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

/// "White won", "Draw", for a still's label.
String? _resultLabel(GameStatus status) => switch (status) {
  GameStatus.whiteWins => 'White won',
  GameStatus.blackWins => 'Black won',
  GameStatus.draw => 'Draw',
  _ => null,
};

/// [game]'s final position as one page: for a game whose moves cannot be
/// read here (a locked collection), or one with nothing else to show.
StoryGame stillStoryGame(CollectionGame game) {
  final preview = game.game;
  return StoryGame(
    game: preview,
    segments: [
      StorySegment.still(
        game.card.finalFen ?? preview.fen,
        _uciMove(game.card.lastMove ?? preview.lastMove),
        label: _resultLabel(preview.gameStatus),
      ),
    ],
    caption: storyCaption(game),
  );
}

/// [game]'s story from [pgn]: its key positions, or its final position when
/// none can be read. [segments] hands in positions already picked.
StoryGame buildStoryGame(
  CollectionGame game, {
  String? pgn,
  List<StorySegment>? segments,
}) {
  final picked =
      segments ??
      (() {
        final story = parseStoryPgn(pgn);
        return story == null
            ? const <StorySegment>[]
            : pickStorySegments(story);
      })();
  if (picked.isEmpty) return stillStoryGame(game);
  return StoryGame(
    game: game.game,
    segments: List.unmodifiable(picked),
    caption: storyCaption(game),
  );
}

Move? _uciMove(String? uci) {
  if (uci == null || uci.trim().isEmpty) return null;
  try {
    return Move.parse(uci.trim());
  } catch (_) {
    return null;
  }
}

/// A short stable number for [text] (FNV-1a).
int storySeed(String text) {
  var hash = 0x811c9dc5;
  for (final unit in utf8.encode(text)) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}

/// The collection's latest game: the one added or updated most recently,
/// else the newest played, else its first.
CollectionGame? latestStoryGame(List<CollectionGame> games) {
  if (games.isEmpty) return null;
  CollectionGame? best;
  for (final g in games) {
    final at = g.card.updatedAt;
    if (at == null) continue;
    final bestAt = best?.card.updatedAt;
    if (bestAt == null || at.isAfter(bestAt)) best = g;
  }
  return best ?? collectionGamesNewestFirst(games).first;
}

/// The games after [latest] that may be the day's picks for [slug] on
/// [day]: shuffled with a seed of the day and the slug (the same picks all
/// day, new ones tomorrow), games with notes first. At most [pool].
List<CollectionGame> storyDailyCandidates(
  List<CollectionGame> games, {
  required CollectionGame? latest,
  required String slug,
  required String day,
  int pool = kStoryCandidatePool,
}) {
  final others = [
    for (final g in games)
      if (g.id != latest?.id) g,
  ];
  final random = math.Random(storySeed('$day|$slug'));
  for (var i = others.length - 1; i > 0; i--) {
    final j = random.nextInt(i + 1);
    final swap = others[i];
    others[i] = others[j];
    others[j] = swap;
  }
  bool annotated(CollectionGame g) =>
      g.card.hasAnnotations || g.card.commentCount > 0 || g.card.nagCount > 0;
  return [
    ...others.where(annotated),
    ...others.where((g) => !annotated(g)),
  ].take(pool).toList(growable: false);
}

/// A collection's stories from the positions found: [latest] first, then
/// [candidates] in their order, each only with at least
/// [kStoryMinSegments] positions, up to [kStoriesPerCollection] in all.
///
/// A collection where no game has that many still shows one story: the
/// first game (the latest first) with a position worth a stop, else the
/// latest game's final position. A circle is never empty.
List<StoryGame> chooseCollectionStories({
  required CollectionGame? latest,
  required List<CollectionGame> candidates,
  required Map<String, List<StorySegment>> segments,
}) {
  final games = [?latest, ...candidates];
  final stories = <StoryGame>[];
  for (final g in games) {
    if (stories.length >= kStoriesPerCollection) break;
    final found = segments[g.id] ?? const [];
    if (found.length < kStoryMinSegments) continue;
    stories.add(buildStoryGame(g, segments: found));
  }
  if (stories.isNotEmpty) return stories;
  for (final g in games) {
    final found = segments[g.id] ?? const [];
    if (found.isNotEmpty) return [buildStoryGame(g, segments: found)];
  }
  return latest == null ? const [] : [stillStoryGame(latest)];
}

// ----------------------------------------------------------- analysis

/// One game to read for its positions.
@immutable
class StoryAnalysisJob {
  const StoryAnalysisJob({
    required this.id,
    required this.pgn,
    this.missed = false,
    this.hint,
  });

  final String id;
  final String pgn;

  /// Read for its missed wins ([pickMissedChanceSegments]).
  final bool missed;

  /// The Missed Chance topic's own ply, for a missed game.
  final int? hint;
}

/// What a game read gave: its positions and the event its PGN names.
@immutable
class StoryAnalysis {
  const StoryAnalysis({required this.segments, this.event});

  final List<StorySegment> segments;
  final String? event;
}

/// Reads every job's game. Pure: runs on a background isolate in the app.
Map<String, StoryAnalysis> analyzeStoryJobs(List<StoryAnalysisJob> jobs) => {
  for (final job in jobs) job.id: _analyze(job),
};

StoryAnalysis _analyze(StoryAnalysisJob job) {
  try {
    final story = parseStoryPgn(job.pgn);
    if (story == null) return const StoryAnalysis(segments: []);
    return StoryAnalysis(
      segments: job.missed
          ? pickMissedChanceSegments(story, hint: job.hint)
          : pickStorySegments(story),
      event: eventTitleFromPgnHeaders(story.game.headers),
    );
  } catch (e) {
    debugPrint('[Stories] ${job.id} unreadable: $e');
    return const StoryAnalysis(segments: []);
  }
}

typedef StoryAnalyzer =
    Future<Map<String, StoryAnalysis>> Function(List<StoryAnalysisJob> jobs);

/// Where games are read for their positions: a background isolate in the
/// app (a few games of moves and comments is real work), in place in tests.
final storyAnalyzerProvider = Provider<StoryAnalyzer>(
  (ref) =>
      (jobs) => jobs.isEmpty
      ? Future.value(const {})
      : Isolate.run(() => analyzeStoryJobs(jobs)),
);

/// How long the viewer waits for the games' moves before it shows what it
/// has (the latest game's final position).
const Duration kStoryReplayWait = Duration(seconds: 6);

/// One collection's stories, by slug: read once and kept warm for a few
/// minutes after the viewer lets them go, so reopening a circle is instant
/// and the next collection is ready before the reader reaches it.
///
/// Its latest game first, then up to two others picked for the day; only
/// the games those are read with their moves. A collection the reader may
/// not read shows its latest game's final position.
final storyBatchProvider = FutureProvider.autoDispose
    .family<StoryBatch, String>((ref, slug) async {
      if (slug == kMissedChancesSlug) {
        return ref.watch(missedChancesBatchProvider.future);
      }
      final link = _holdAfterLastListener(ref, const Duration(minutes: 5));
      try {
        final contentsRead = ref.watch(collectionContentsProvider(slug).future);
        final detailRead = ref.watch(collectionDetailProvider(slug).future);
        final contents = await contentsRead;
        final detail = await detailRead;
        final ordered = storyGameOrder(detail.kind, contents);
        final day = storyDayKey(ref.read(storyClockProvider)());
        final latest = latestStoryGame(contents.games);
        final candidates = storyDailyCandidates(
          contents.games,
          latest: latest,
          slug: slug,
          day: day,
        );
        var segments = const <String, List<StorySegment>>{};
        if (latest != null && storyMovesReadable(detail)) {
          try {
            final wanted = [latest, ...candidates];
            // Only the stretches of the server's order that hold these
            // games are read with their moves, never the whole collection.
            final pgns = await ref
                .read(collectionsRepositoryProvider)
                .fetchPgnsOf(
                  slug,
                  {for (final g in wanted) g.id},
                  order: [for (final g in contents.games) g.id],
                )
                .timeout(kStoryReplayWait);
            final analysis = await ref.read(storyAnalyzerProvider)([
              for (final g in wanted)
                if (pgns[g.id] case final pgn?)
                  StoryAnalysisJob(id: g.id, pgn: pgn),
            ]);
            segments = {
              for (final MapEntry(:key, :value) in analysis.entries)
                key: value.segments,
            };
          } catch (e) {
            debugPrint('[Stories] $slug positions unavailable: $e');
          }
        }
        return StoryBatch(
          games: chooseCollectionStories(
            latest: latest,
            candidates: candidates,
            segments: segments,
          ),
          ordered: List.unmodifiable([for (final g in ordered) g.game]),
          total: ordered.length,
          gameCount: detail.gameCount,
          signature: storySignature(detail),
        );
      } catch (_) {
        // A failed read is never kept: the next look tries again.
        link.close();
        rethrow;
      }
    });

/// The day's Missed chances: up to [kMissedChancesPerDay] games from the
/// Reports' Missed Chance topic, read from games finished before today (the
/// same games all day, new ones tomorrow), the ones with the most missed
/// wins to find first, then shown newest first. Free readers see the same
/// stories; opening a game asks for access as Reports does.
final missedChancesBatchProvider = FutureProvider.autoDispose<StoryBatch>((
  ref,
) async {
  final link = _holdAfterLastListener(ref, const Duration(minutes: 30));
  try {
    final now = ref.read(storyClockProvider)();
    final day = storyDayKey(now);
    final page = await ref
        .watch(discoveryRepositoryProvider)
        .fetchAnalyzedGamesPage(
          pageSize: 24,
          gameType: ReportGameType.missedChance,
          until: DateTime(now.year, now.month, now.day),
        );
    final analysis = await ref.read(storyAnalyzerProvider)([
      for (final game in page.items)
        if (game.pgn case final pgn?)
          StoryAnalysisJob(
            id: game.gameId,
            pgn: pgn,
            missed: true,
            hint: page.storyPlies[game.gameId],
          ),
    ]);
    final games = chooseMissedChanceStories(page.items, analysis, day: day);
    return StoryBatch(
      games: games,
      ordered: List.unmodifiable([for (final g in games) g.game]),
      gameCount: games.length,
      signature: 'v:missed:$day',
    );
  } catch (_) {
    link.close();
    rethrow;
  }
});

/// A Missed chances day from [games] and what reading them gave: the games
/// with the most missed wins to find (a game asking for none comes last),
/// stronger games first between equals, at most [kMissedChancesPerDay],
/// then newest first.
List<StoryGame> chooseMissedChanceStories(
  List<GamesTourModel> games,
  Map<String, StoryAnalysis> analysis, {
  required String day,
}) {
  int asks(StoryAnalysis a) => a.segments.where((s) => s.puzzle != null).length;
  final usable = [
    for (final g in games)
      if ((analysis[g.gameId]?.segments ?? const []).isNotEmpty) g,
  ];
  usable.sort((a, b) {
    final left = analysis[a.gameId]!;
    final right = analysis[b.gameId]!;
    final byAsks = asks(right).compareTo(asks(left));
    if (byAsks != 0) return byAsks;
    final bySize = right.segments.length.compareTo(left.segments.length);
    if (bySize != 0) return bySize;
    final byRating =
        effectiveAverageGameRating(
          b.whitePlayer.rating,
          b.blackPlayer.rating,
        ).compareTo(
          effectiveAverageGameRating(
            a.whitePlayer.rating,
            a.blackPlayer.rating,
          ),
        );
    if (byRating != 0) return byRating;
    return storySeed(
      '$day|${a.gameId}',
    ).compareTo(storySeed('$day|${b.gameId}'));
  });
  final picked = usable.take(kMissedChancesPerDay).toList()
    ..sort((a, b) {
      final at = a.lastMoveTime;
      final bt = b.lastMoveTime;
      if (at == null || bt == null) {
        if (at == bt) return 0;
        return at == null ? 1 : -1;
      }
      return bt.compareTo(at);
    });
  return [
    for (final g in picked)
      StoryGame(
        game: g,
        segments: List.unmodifiable(analysis[g.gameId]!.segments),
        caption: analysis[g.gameId]!.event,
      ),
  ];
}

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
