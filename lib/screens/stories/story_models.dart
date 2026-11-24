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
import 'package:chessever2/screens/stories/story_notation.dart';
import 'package:chessever2/screens/stories/story_row_prefs.dart'
    show storyClockProvider, storyDayKey;
import 'package:chessever2/screens/stories/story_seen_store.dart';
import 'package:chessever2/screens/stories/story_visit.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/average_game_rating.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

export 'package:chessever2/screens/stories/story_moments.dart';

/// Missed Chances and the featured collection games share a six-story visit.
const int kStoryLineupSize = 6;
const int kStoryRecentSlots = 3;
const Duration kStoryRecentWindow = Duration(days: 7);

/// How many games, besides the latest, are read to find the day's picks.
const int kStoryCandidatePool = 8;

/// How long a collection with no game to show holds before moving on.
const Duration kStoryEmptyDuration = Duration(seconds: 3);

/// One game story: up to [kStoryMaxSegments] key positions of one game.
@immutable
class StoryGame {
  const StoryGame({
    required this.game,
    required this.segments,
    this.caption,
    this.notation,
  });

  /// Players and result as the collection's cards (or the report list)
  /// hold them.
  final GamesTourModel game;

  /// The positions shown, in game order. Never empty.
  final List<StorySegment> segments;

  /// One line over the moment: the event, the opening.
  final String? caption;

  final StoryNotation? notation;

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
    this.featuredGame = false,
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

  /// This collection visit features one specific game. Its circle goes
  /// quiet when that game was watched, even if earlier visits featured others.
  final bool featuredGame;

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
    gameCount: 1,
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

/// Reserves up to three places for recent additions or updates. The rest
/// come from a rotating window through the catalog, so books that seldom
/// change can surface without occupying a permanent slot.
({List<Collection> recent, List<Collection> archive}) selectStoryCollections(
  List<Collection> catalog, {
  required StoryVisit visit,
  required bool hasMissedChances,
}) {
  final unique = <String>{};
  final ordered =
      [
        for (final c in catalog)
          if (!isMissedChances(c) && c.gameCount > 0 && unique.add(c.slug)) c,
      ]..sort((a, b) {
        final byRecency = _byRecency(a, b);
        return byRecency == 0 ? a.slug.compareTo(b.slug) : byRecency;
      });
  final cutoff = visit.startedAt.subtract(kStoryRecentWindow);
  final recent = ordered
      .where((c) {
        final changed = storyRecency(c);
        return changed != null && !changed.isBefore(cutoff);
      })
      .take(kStoryRecentSlots)
      .toList(growable: false);
  final slugs = {for (final c in recent) c.slug};
  final pool = [
    for (final c in ordered)
      if (!slugs.contains(c.slug)) c,
  ];
  final count = kStoryLineupSize - (hasMissedChances ? 1 : 0) - recent.length;
  if (pool.length <= count) return (recent: recent, archive: pool);
  final offset = (visit.rotation * count) % pool.length;
  return (
    recent: recent,
    archive: [for (var i = 0; i < count; i++) pool[(offset + i) % pool.length]],
  );
}

/// The row's order: circles with something the reader has not seen, then
/// the seen ones, each group most recently updated first. A collection
/// that gets a new game lands leftmost.
List<Collection> orderStoryCollections(
  List<Collection> collections,
  bool Function(Collection collection) seen,
) {
  final indexed = [
    for (var i = 0; i < collections.length; i++) (i, collections[i]),
  ];
  int group(Collection c) => seen(c) ? 1 : 0;
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

/// Whether a server from before the stories' own read
/// ([CollectionsRepository.fetchStoryGames]) lets this viewer read
/// [detail]'s PGNs: that server keeps a Premium collection's moves from a
/// reader without Premium.
bool storyMovesReadable(Collection detail) =>
    !detail.isPremium || detail.contentLocked == false;

/// The games a collection's stories are read from: its latest game, then
/// the day's picks, with the PGNs found for them by game id.
typedef StoryGamesRead = ({
  CollectionGame? latest,
  List<CollectionGame> candidates,
  Map<String, String> pgns,
});

/// [slug]'s stories' games for [day] among [games] (the collection as the
/// browse read lists it).
///
/// The server picks them and hands their PGNs to every reader alike
/// (gamebase `include=story`), so a guest and a free reader watch exactly
/// what a Premium reader watches; Premium is asked for when a story opens
/// its game, its collection or its event, never to watch it. A game the server names
/// that the browse read does not hold (the collection changed between the
/// two reads) is left out: it could not be opened from its story.
///
/// A server from before that read leaves the picking here
/// ([latestStoryGame], [storyDailyCandidates]), with PGNs only where it lets
/// this viewer read them ([storyMovesReadable]).
Future<StoryGamesRead> readStoryGames(
  CollectionsRepository repository, {
  required String slug,
  required String day,
  required Collection detail,
  required List<CollectionGame> games,
}) async {
  final served = await repository.fetchStoryGames(slug, day: day);
  if (served != null) {
    final byId = {for (final g in games) g.id: g};
    final picked = [for (final card in served) ?byId[card.id]];
    return (
      latest: picked.firstOrNull,
      candidates: picked.skip(1).toList(growable: false),
      pgns: {
        for (final card in served)
          if (card.pgn case final pgn?) card.id: pgn,
      },
    );
  }
  final latest = latestStoryGame(games);
  final candidates = storyDailyCandidates(
    games,
    latest: latest,
    slug: slug,
    day: day,
  );
  if (latest == null || !storyMovesReadable(detail)) {
    return (
      latest: latest,
      candidates: candidates,
      pgns: const <String, String>{},
    );
  }
  // Only the stretches of the server's order that hold these games are read
  // with their moves, never the whole collection.
  final pgns = await repository.fetchPgnsOf(
    slug,
    {
      for (final g in [latest, ...candidates]) g.id,
    },
    order: [for (final g in games) g.id],
  );
  return (latest: latest, candidates: candidates, pgns: pgns);
}

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

/// [game]'s final position as one page: for a game with nothing else to
/// show, or whose moves could not be read just now. No words under it: the
/// player rows carry the result on it.
StoryGame stillStoryGame(CollectionGame game, {StoryNotation? notation}) {
  final preview = game.game;
  return StoryGame(
    game: preview,
    segments: [
      StorySegment.still(
        game.card.finalFen ?? preview.fen,
        _uciMove(game.card.lastMove ?? preview.lastMove),
      ),
    ],
    caption: storyCaption(game),
    notation: notation,
  );
}

/// [game]'s story from [pgn]: its key positions, or its final position when
/// none can be read. [segments] hands in positions already picked.
StoryGame buildStoryGame(
  CollectionGame game, {
  String? pgn,
  List<StorySegment>? segments,
  StoryNotation? notation,
}) {
  final story = parseStoryPgn(pgn);
  final moves = notation ?? story?.notation;
  final picked =
      segments ?? (story == null ? const [] : pickStorySegments(story));
  if (picked.isEmpty) return stillStoryGame(game, notation: moves);
  return StoryGame(
    game: game.game,
    segments: List.unmodifiable(picked),
    caption: storyCaption(game),
    notation: moves,
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

/// Features one playable game per collection. Keep the visit's pick or an
/// unfinished story if available, then prefer an unwatched game, latest
/// first. When moves are unavailable, the latest game's final board remains
/// a usable preview.
StoryGame? chooseCollectionStory({
  required CollectionGame? latest,
  required List<CollectionGame> candidates,
  required Map<String, StoryAnalysis> analysis,
  Set<String> watched = const {},
  String? preferredId,
}) {
  final games = [?latest, ...candidates];
  final playable = games.where(
    (g) => analysis[g.id]?.segments.isNotEmpty ?? false,
  );
  final picked =
      playable.where((g) => g.id == preferredId).firstOrNull ??
      playable.where((g) => !watched.contains(g.id)).firstOrNull ??
      playable.firstOrNull;
  if (picked != null) {
    final story = analysis[picked.id]!;
    return buildStoryGame(
      picked,
      segments: story.segments,
      notation: story.notation,
    );
  }
  final fallback = games.firstOrNull;
  return fallback == null ? null : stillStoryGame(fallback);
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
  const StoryAnalysis({required this.segments, this.event, this.notation});

  final List<StorySegment> segments;
  final String? event;
  final StoryNotation? notation;
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
          : completeCollectionStory(story, pickStorySegments(story)),
      event: eventTitleFromPgnHeaders(story.game.headers),
      notation: story.notation,
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
/// One game from the day's candidate pool, with identical playable content
/// across account tiers ([readStoryGames]).
final storyBatchProvider = FutureProvider.autoDispose
    .family<StoryBatch, String>((ref, slug) async {
      if (slug == kMissedChancesSlug) {
        return ref.watch(missedChancesBatchProvider.future);
      }
      final visit = ref.watch(storyVisitProvider);
      final seen = ref.read(storySeenProvider.notifier);
      final link = _holdAfterLastListener(ref, const Duration(minutes: 5));
      try {
        final contentsRead = ref.watch(collectionContentsProvider(slug).future);
        final detailRead = ref.watch(collectionDetailProvider(slug).future);
        final contents = await contentsRead;
        final detail = await detailRead;
        final ordered = storyGameOrder(detail.kind, contents);
        var latest = latestStoryGame(contents.games);
        var candidates = const <CollectionGame>[];
        var analysis = const <String, StoryAnalysis>{};
        if (latest != null) {
          try {
            final read = await readStoryGames(
              ref.read(collectionsRepositoryProvider),
              slug: slug,
              day: visit.day,
              detail: detail,
              games: contents.games,
            ).timeout(kStoryReplayWait);
            latest = read.latest ?? latest;
            candidates = read.candidates;
            analysis = await ref.read(storyAnalyzerProvider)([
              for (final g in [?read.latest, ...read.candidates])
                if (read.pgns[g.id] case final pgn?)
                  StoryAnalysisJob(id: g.id, pgn: pgn),
            ]);
          } catch (e) {
            debugPrint('[Stories] $slug positions unavailable: $e');
          }
        }
        final signature = storySignature(detail);
        final picked = chooseCollectionStory(
          latest: latest,
          candidates: candidates,
          analysis: analysis,
          watched: seen.watchedGames(slug),
          preferredId:
              visit.pickFor(slug, signature) ?? seen.unfinishedGame(detail),
        );
        if (picked != null && !picked.segments.first.isStill) {
          visit.remember(slug, signature, picked.id);
        }
        return StoryBatch(
          games: [?picked],
          ordered: List.unmodifiable([for (final g in ordered) g.game]),
          total: ordered.length,
          gameCount: detail.gameCount,
          signature: signature,
          featuredGame: true,
        );
      } catch (_) {
        // A failed read is never kept: the next look tries again.
        link.close();
        rethrow;
      }
    });

/// One Missed Chances game from Reports, kept for the day. It prefers an
/// unwatched game with a win to find. Opening it uses the Reports access
/// rules.
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
    final games = chooseMissedChanceStories(
      page.items,
      analysis,
      day: day,
      watched: ref
          .read(storySeenProvider.notifier)
          .watchedGames(kMissedChancesSlug),
    );
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
/// stronger games first between equals.
List<StoryGame> chooseMissedChanceStories(
  List<GamesTourModel> games,
  Map<String, StoryAnalysis> analysis, {
  required String day,
  Set<String> watched = const {},
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
  final best = usable.firstOrNull;
  if (best == null) return const [];
  final needsPuzzle = asks(analysis[best.gameId]!) > 0;
  final picked =
      usable
          .where(
            (g) =>
                !watched.contains(g.gameId) &&
                (!needsPuzzle || asks(analysis[g.gameId]!) > 0),
          )
          .firstOrNull ??
      best;
  return [
    StoryGame(
      game: picked,
      segments: List.unmodifiable(analysis[picked.gameId]!.segments),
      caption: analysis[picked.gameId]!.event,
      notation: analysis[picked.gameId]!.notation,
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
