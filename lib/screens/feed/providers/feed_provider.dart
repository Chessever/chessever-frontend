import 'dart:async';

import 'package:chessever2/config/feature_flags.dart';
import 'package:chessever2/localization/locale_provider.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/feed/audio/feed_sfx.dart';
import 'package:chessever2/screens/feed/logic/feed_codec.dart';
import 'package:chessever2/screens/feed/logic/feed_moments.dart';
import 'package:chessever2/screens/feed/logic/feed_pgn.dart';
import 'package:chessever2/screens/feed/logic/feed_ranker.dart'
    show feedIsOnlineEvent;
import 'package:chessever2/screens/feed/logic/feed_report.dart';
import 'package:chessever2/screens/feed/logic/feed_taste.dart';
import 'package:chessever2/screens/feed/models/feed_collection.dart';
import 'package:chessever2/screens/feed/models/feed_entry.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/news/news_models.dart';
import 'package:chessever2/screens/feed/news/news_repository.dart';
import 'package:chessever2/screens/feed/providers/board_feed_client.dart';
import 'package:chessever2/screens/for_you/discovery/models/report_game_type.dart';
import 'package:chessever2/screens/standings/providers/player_utils_provider.dart';
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/providers/streak_providers.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The backend orders the feed. The app hydrates cards and sends feedback.
final boardFeedClientProvider = Provider<BoardFeedClient?>(
  (ref) => BoardFeedClient.forCurrentUser(),
);

class BoardFeedSignInRequired implements Exception {
  const BoardFeedSignInRequired();
}

final feedProvider = AsyncNotifierProvider<FeedNotifier, List<FeedItem>>(
  FeedNotifier.new,
);

/// What lies past the last loaded game, as the last finished
/// [FeedNotifier.loadMore] found it. Feed's tail page reads it: the next
/// post's skeleton while [open], a quiet end of the feed otherwise.
enum FeedMore {
  /// More may come, or is on its way.
  open,

  /// The last load came back with nothing although sources are left (a
  /// failed request, a batch the filters emptied): worth another try.
  stalled,

  /// Every source is read to its end and nothing is left to show.
  exhausted,
}

/// The account the Feed's disk cache is kept under: the signed-in user, or
/// null for a guest (and wherever Supabase is not set up).
String? feedCacheUserId() {
  try {
    return Supabase.instance.client.auth.currentUser?.id;
  } catch (_) {
    return null;
  }
}

/// The first page Feed last cached for [userId], parsed and ready to play:
/// used by the Discovery tile. Empty when
/// nothing is cached, the cache is older than its max age, or it cannot be
/// read. Reads SQLite only, never the network, and never builds
/// [feedProvider].
Future<List<FeedItem>> readFeedFirstPageCache({String? userId}) async {
  try {
    final entry = await AppDatabase.instance.getCache(
      key: FeedNotifier.cacheKey,
      userId: userId,
      maxAge: FeedNotifier._cacheMaxAge,
    );
    if (entry == null) return const [];
    return decodeFlowFeedCache(entry.value, now: DateTime.now());
  } catch (error) {
    debugPrint('[Feed] cache read failed: $error');
    return const [];
  }
}

class FeedNotifier extends AsyncNotifier<List<FeedItem>> {
  /// Where the first page is kept on disk ([readFeedFirstPageCache]).
  static const String cacheKey = 'backend_feed_first_page_v1';
  static const Duration _cacheMaxAge = Duration(minutes: 30);
  static const Duration _pgnTimeout = Duration(seconds: 8);
  static const int _prefetchAhead = 2;
  static const int _minPlies = 10;
  static const int _minDrawPlies = 30;

  int _generation = 0;

  /// The post on screen and what has happened on it so far.
  String? _visitId;
  DateTime? _visitStart;
  double _visitProgress = 0;
  final Set<FeedAction> _visitActions = {};

  BoardFeedClient? _boardServer;
  final _boardPositions = <String, BoardFeedPosition>{};
  final _newsPositions = <int, BoardFeedPosition>{};
  final _newsImpressions = <int>{};
  final _shortPositions = <String, BoardFeedPosition>{};
  final _shortImpressions = <String>{};
  final _collectionPositions = <String, BoardFeedPosition>{};
  final _collectionImpressions = <(String, String)>{};
  List<FeedEntry>? _serverEntries;
  List<FeedEntry>? get serverEntries => _serverEntries;
  String? _boardCursor;

  bool _loadingMore = false;

  /// The [loadMore] running now, handed to every caller that asks meanwhile.
  Future<void>? _moreRun;
  FeedMore _more = FeedMore.open;

  /// See [FeedMore]. Not state: the screen reads it when a [loadMore] it
  /// awaited completes, and at every build.
  FeedMore get more => _more;

  @override
  Future<List<FeedItem>> build() async {
    final generation = ++_generation;
    _loadingMore = false;
    _moreRun = null;
    _more = FeedMore.open;
    final viewer = ref.watch(
      currentUserProvider.select(
        (user) => (id: user?.id, isAnonymous: user?.isAnonymous ?? true),
      ),
    );
    final current = ref.read(boardFeedClientProvider);
    _bindBoardSound();

    // Warm the streak wall so winners on a run can say so in their caption.
    // The wall usually lands after the first page is on screen, so items
    // already shown are recaptioned then.
    if (FeatureFlags.streaks) {
      ref.listen<AsyncValue<List<StreakRow>>>(streakWallProvider, (
        previous,
        next,
      ) {
        final rows = next.valueOrNull;
        if (rows == null || identical(rows, previous?.valueOrNull)) return;
        unawaited(_recaptionWhenBuilt(_generation));
      });
    }

    _closeVisit();
    _visitId = null;
    _visitStart = null;
    final previous = _boardServer;
    _boardServer = previous != null && previous.userId == current?.userId
        ? previous
        : current;
    _clearFeedbackPositions();
    _serverEntries = const [];
    _boardCursor = null;

    final server = _boardServer;
    if (server == null) {
      if (viewer.id == null || viewer.isAnonymous) {
        throw const BoardFeedSignInRequired();
      }
      throw const BoardFeedUnavailable(503);
    }
    return _boardItems(
      await _readServerEntries(server, generation, refresh: true),
    );
  }

  /// Keep the current page on screen while asking the backend for a fresh
  /// session. Failures propagate so the screen can offer a retry.
  Future<void> refresh() async {
    final generation = ++_generation;
    final server = _boardServer;
    if (server == null) {
      if (state.error case final Object error) throw error;
      throw const BoardFeedUnavailable(503);
    }
    _closeVisit();
    _visitId = null;
    _visitStart = null;
    _loadingMore = false;
    _moreRun = null;
    final items = await _readServerEntries(server, generation, refresh: true);
    if (generation == _generation) state = AsyncData(_boardItems(items));
  }

  /// Appends the next page. Safe to call repeatedly: while a page is
  /// loading, every call gets that load, so awaiting one means the page has
  /// landed (or [more] says why not). Never throws.
  Future<void> loadMore() {
    final running = _moreRun;
    if (_loadingMore && running != null) return running;
    if (_loadingMore || !state.hasValue) return Future<void>.value();
    _loadingMore = true;
    _more = FeedMore.open;
    final run = _loadMore(_generation);
    _moreRun = run;
    run.whenComplete(() {
      if (identical(_moreRun, run)) _moreRun = null;
    }).ignore();
    return run;
  }

  Future<void> _loadMore(int generation) async {
    final server = _boardServer;
    try {
      if (server == null) return;
      final entries = await _readServerEntries(server, generation);
      if (generation == _generation && entries.isNotEmpty) {
        await _append(generation, _boardItems(entries));
      }
    } catch (_) {
      if (generation == _generation) _more = FeedMore.stalled;
    } finally {
      if (generation == _generation) _loadingMore = false;
    }
  }

  void _clearFeedbackPositions() {
    _boardPositions.clear();
    _newsPositions.clear();
    _newsImpressions.clear();
    _shortPositions.clear();
    _shortImpressions.clear();
    _collectionPositions.clear();
    _collectionImpressions.clear();
  }

  List<FeedItem> _boardItems(List<FeedEntry> entries) => [
    for (final entry in entries.whereType<FeedGameEntry>()) entry.item,
  ];

  Future<List<FeedEntry>> _readServerEntries(
    BoardFeedClient server,
    int generation, {
    bool refresh = false,
  }) async {
    if (!refresh && _boardCursor == null) {
      _more = FeedMore.exhausted;
      return const [];
    }
    var page = refresh
        ? await server.start(
            server.newRequestId(),
            country: ref.read(countryDropdownProvider).valueOrNull?.countryCode,
            languages: {
              ref.read(localeProvider).languageCode,
              for (final locale in PlatformDispatcher.instance.locales)
                locale.languageCode,
            }.take(8).toList(),
          )
        : await server.next(_boardCursor!);
    for (var attempt = 0; ; attempt++) {
      if (generation != _generation) return const [];
      final hydrated = await _hydrateServerEntries(server, page.cards);
      final items = hydrated.any((item) => item is! FeedAdEntry)
          ? hydrated
          : const <FeedEntry>[];
      if (generation != _generation) return const [];
      final cursor = page.nextCursor;
      if (items.isNotEmpty || cursor == null || attempt == 4) {
        if (refresh) _clearFeedbackPositions();
        for (final item in items) {
          if (item is FeedGameEntry) {
            _boardPositions[item.item.game.gameId] = page.position;
          } else if (item is FeedNewsEntry) {
            _newsPositions[item.news.id] = page.position;
          } else if (item is FeedShortEntry) {
            _shortPositions[item.short.id] = page.position;
          } else if (item is FeedCollectionEntry) {
            _collectionPositions[item.key] = page.position;
          }
        }
        _serverEntries = List.unmodifiable([
          if (!refresh) ...?_serverEntries,
          ...items,
        ]);
        if (refresh) unawaited(_writeCache(_boardItems(items), server.userId));
        _boardCursor = cursor;
        _more = cursor == null
            ? FeedMore.exhausted
            : items.isEmpty
            ? FeedMore.stalled
            : FeedMore.open;
        return items;
      }
      page = await server.next(cursor);
    }
  }

  Future<List<FeedEntry>> _hydrateServerEntries(
    BoardFeedClient server,
    List<BoardFeedCard> cards,
  ) async {
    final counts = <int, int>{
      for (final card in cards)
        if (card.articleCount case final int count)
          if (int.tryParse(card.id) case final int id) id: count,
    };
    final (boards, news) = await (
      _hydrateServerBoards(server, [
        for (final card in cards)
          if (!card.isAd &&
              card.articleCount == null &&
              card.short == null &&
              card.collection == null)
            card.id,
      ]),
      _hydrateGroupedNews(counts),
    ).wait;
    final boardsById = {for (final board in boards) board.game.gameId: board};
    return [
      for (final card in cards)
        if (card.isAd)
          FeedAdEntry.server(card.id)
        else if (card.collection case final collection?)
          FeedCollectionEntry(collection)
        else if (card.short case final short?)
          FeedShortEntry(short)
        else if (card.articleCount == null) ...[
          if (boardsById[card.id] case final FeedItem board)
            FeedGameEntry(board),
        ] else if (news[int.tryParse(card.id)] case final FeedNews article)
          FeedNewsEntry(article),
    ];
  }

  Future<Map<int, FeedNews>> _hydrateGroupedNews(Map<int, int> counts) async {
    if (counts.isEmpty) return const {};
    try {
      return await ref
          .read(feedNewsRepositoryProvider)
          .loadGroupedCards(counts);
    } catch (error) {
      debugPrint('[Feed] grouped news hydration failed: $error');
      return const {};
    }
  }

  void noteNewsVisible(int id) {
    final position = _newsPositions[id];
    if (position != null && _newsImpressions.add(id)) {
      _boardServer?.recordNews(position, id, 'impression');
    }
  }

  void noteNewsOpened(int id) {
    final position = _newsPositions[id];
    if (position != null) _boardServer?.recordNews(position, id, 'open');
  }

  void noteShortVisible(String id) {
    final position = _shortPositions[id];
    if (position != null && _shortImpressions.add(id)) {
      _boardServer?.recordShort(position, id, 'impression');
    }
  }

  void noteShortOpened(String id) {
    final position = _shortPositions[id];
    if (position != null) _boardServer?.recordShort(position, id, 'open');
  }

  void noteCollectionGameVisible(FeedCollection card, String gameId) {
    final collectionId = card.collection.id;
    final position = _collectionPositions[card.feedKey];
    if (position != null &&
        _collectionImpressions.add((collectionId, gameId))) {
      _boardServer?.recordCollectionGame(
        position,
        collectionId,
        gameId,
        'impression',
      );
    }
  }

  void noteCollectionGameOpened(FeedCollection card, String gameId) {
    final collectionId = card.collection.id;
    final position = _collectionPositions[card.feedKey];
    if (position != null) {
      _boardServer?.recordCollectionGame(
        position,
        collectionId,
        gameId,
        'open',
      );
    }
  }

  Future<List<FeedItem>> _hydrateServerBoards(
    BoardFeedClient server,
    List<String> ids,
  ) async {
    if (ids.isEmpty) return const [];
    final repository = ref.read(gameRepositoryProvider);
    final (rows, classifications) = await (
      repository.getGamesByIds(ids).timeout(_pgnTimeout),
      _loadClassifications(ids),
    ).wait;
    final byId = {for (final row in rows) row.id: row};
    final candidates = <(GamesTourModel, String)>[];
    for (final id in ids) {
      final row = byId[id];
      if (row == null) continue;
      final game = _tourModel(row);
      final pgn = game?.pgn;
      if (game == null || pgn == null || pgn.isEmpty) continue;
      candidates.add((game, pgn));
    }
    final clips = await compute(_parseFlowClips, [
      for (final (_, pgn) in candidates) pgn,
    ]);
    final items = <FeedItem>[];
    final now = DateTime.now();
    for (var index = 0; index < candidates.length; index++) {
      final (game, pgn) = candidates[index];
      final id = game.gameId;
      if (server.completedLocally(id)) continue;
      final type = feedReportType(
        classifications[id],
        pgn,
        _resultOf(game.gameStatus) ?? '',
      );
      final item = _toItem(game, clips[index], pgn, now, reportType: type);
      if (item != null) items.add(item);
    }
    return items;
  }

  /// Called when the viewer reaches [index] so the notifier can prefetch:
  /// at least [_prefetchAhead] ready clips are kept beyond it.
  ///
  /// -1 is the page above the first game: the game Watch opened Feed on
  /// ([FeedScreen.watch]). It is not one of this feed's draws, so the visit
  /// before it ends there and nothing is learned from it.
  void onVisible(int index) {
    final items = state.valueOrNull;
    if (items == null) return;
    if (index >= 0 && index < items.length) {
      _visit(items[index].game.gameId);
    } else if (index < 0) {
      _closeVisit();
      _visitId = null;
      _visitStart = null;
    }
    if (items.length - 1 - index <= _prefetchAhead + 1) {
      unawaited(loadMore());
    }
  }

  /// How much of [gameId]'s clip has played (0..1), as the clip reports it.
  void noteProgress(String gameId, double fraction) {
    if (gameId != _visitId) return;
    if (fraction > _visitProgress) _visitProgress = fraction;
    if (fraction >= 1 &&
        _visitStart != null &&
        DateTime.now().difference(_visitStart!) >= const Duration(seconds: 4)) {
      _recordBoardEvent(gameId, 'complete');
    }
  }

  /// Something the viewer did with [gameId]'s post.
  void noteAction(String gameId, FeedAction action) {
    if (gameId != _visitId) return;
    if (_visitActions.add(action)) _recordBoardEvent(gameId, action.name);
  }

  /// The viewer moved to [gameId]: what they did on the post before it is
  /// learned from, and the next pages are drawn with it.
  void _visit(String gameId) {
    if (gameId == _visitId) return;
    _closeVisit();
    _visitId = gameId;
    _visitStart = DateTime.now();
    _visitProgress = 0;
    _visitActions.clear();
    _recordBoardEvent(gameId, 'impression');
  }

  void _recordBoardEvent(String gameId, String kind) {
    final position = _boardPositions[gameId];
    if (position != null) _boardServer?.record(position, gameId, kind);
  }

  void _closeVisit() {
    final id = _visitId;
    final start = _visitStart;
    if (id == null || start == null) return;
    final dwell = DateTime.now().difference(start);
    if (_visitProgress >= 1 && dwell >= const Duration(seconds: 4)) {
      _recordBoardEvent(id, 'complete');
    } else if (_visitProgress < 0.3 &&
        dwell < const Duration(seconds: 3) &&
        _visitActions.isEmpty) {
      _recordBoardEvent(id, 'skip');
    }
  }

  Future<Map<String, Object?>> _loadClassifications(List<String> ids) async {
    try {
      return await ref
          .read(gameRepositoryProvider)
          .getFeedGameClassifications(ids)
          .timeout(const Duration(seconds: 2));
    } catch (error) {
      // Older backends and temporary metadata failures still have Reports.
      debugPrint('[Feed] report categories unavailable: $error');
      return const {};
    }
  }

  FeedItem? _toItem(
    GamesTourModel game,
    FeedClip? clip,
    String pgn,
    DateTime now, {
    ReportGameType? reportType,
  }) {
    if (clip == null || clip.plyCount < _minPlies) return null;
    // Feed replays need both a saved report and evaluations.
    if (!clip.hasReport || !clip.hasEvals) return null;
    if (game.source != GameSource.supabase || !game.gameStatus.isFinished) {
      return null;
    }
    final result = clip.result ?? _resultOf(game.gameStatus);
    if (result == null) return null;
    if (result != _resultOf(game.gameStatus)) return null;
    if (result == '½-½' && clip.plyCount < _minDrawPlies) return null;

    final streak = _streakOf(game, result, event: clip.event);
    return FeedItem(
      // Listings carry no moves; hand the board the ones just fetched.
      game: game.copyWith(pgn: pgn, isPgnDeferred: false),
      plies: clip.plies,
      reason:
          streak?.reason ??
          feedReasonFor(
            source: FeedSource.decisive,
            hint: null,
            game: game,
            plies: clip.plies,
            result: result,
            now: now,
          ),
      eventLabel: clip.event ?? _prettySlug(game.tourSlug),
      result: result,
      hasEvals: clip.hasEvals,
      signal: streak?.signal,
      reportType: reportType,
    );
  }

  static DateTime? _dayOf(String? raw) {
    final parsed = DateTime.tryParse(raw ?? '');
    return parsed == null
        ? null
        : DateTime.utc(parsed.year, parsed.month, parsed.day);
  }

  /// "Ding Liren · 6 classical wins in a row" (and the header's streak mark)
  /// when the game's winner is on a live streak in the game's time class and
  /// this win is part of it (over the board only, the way the streak ledger
  /// counts). Null otherwise, or while the wall is loading.
  ({String reason, FeedSignal signal})? _streakOf(
    GamesTourModel game,
    String? result, {
    String? event,
  }) {
    if (!FeatureFlags.streaks) return null;
    final winner = switch (result) {
      '1-0' => game.whitePlayer,
      '0-1' => game.blackPlayer,
      _ => null,
    };
    final fideId = winner?.fideId;
    final timeClass = StreakTimeClassX.tryParse(game.timeControl?.trim());
    if (winner == null || fideId == null || timeClass == null) return null;

    final rows = ref.read(streakWallProvider).valueOrNull;
    if (rows == null) return null;
    StreakRow? run;
    for (final row in rows) {
      if (row.fideId == fideId && row.timeClass == timeClass) {
        run = row;
        break;
      }
    }
    // Same floor as every streak list: below 2650 a run is not a story.
    if (run == null ||
        run.currentStreak < kStreakWallMin ||
        !passesStreakFloor(run)) {
      return null;
    }
    if (feedIsOnlineEvent(game.tourSlug, event)) return null;

    // Only a win after the loss that anchors the run is part of it. The
    // ledger orders a day's games by time, which the wall does not carry, so
    // a win from the anchor loss's own day may have come before it: no
    // caption rather than a wrong one. Wins before the run's first win are
    // not in it either.
    final anchorDay = _dayOf(run.anchorLossGameDay);
    final played = game.bucketDate;
    if (anchorDay == null || played == null) return null;
    final playedDay = DateTime.utc(played.year, played.month, played.day);
    if (!playedDay.isAfter(anchorDay)) return null;
    final startDay = _dayOf(run.streakStartGameDay);
    if (startDay != null && playedDay.isBefore(startDay)) return null;

    final name = formatPlayerDisplayName(winner.name);
    if (name.isEmpty) return null;
    return (
      reason:
          '$name · ${run.currentStreak} '
          '${timeClass.label.toLowerCase()} wins in a row',
      signal: FeedSignal(
        FeedSignalKind.streak,
        name: name,
        count: run.currentStreak,
      ),
    );
  }

  /// Cached items get their streak caption and mark back (the cache
  /// re-derives the generic one on read) once the wall is in.
  FeedItem _withStreakReason(FeedItem item) {
    final streak = _streakOf(item.game, item.result, event: item.eventLabel);
    if (streak == null ||
        (streak.reason == item.reason && streak.signal == item.signal)) {
      return item;
    }
    return item.copyWith(reason: streak.reason, signal: streak.signal);
  }

  /// Waits for the page being built, then recaptions it (see [_recaption]).
  Future<void> _recaptionWhenBuilt(int generation) async {
    final current = state;
    if (current is! AsyncData<List<FeedItem>> || current.isLoading) {
      try {
        await future;
      } catch (_) {
        return; // A failed build has nothing to caption.
      }
    }
    if (generation != _generation) return;
    _recaption();
  }

  /// Gives items already in the feed the streak caption the wall now allows,
  /// e.g. the cached page painted before the wall had loaded.
  void _recaption() {
    final current = state;
    if (current is! AsyncData<List<FeedItem>> || current.isLoading) return;
    final items = current.value;
    List<FeedItem>? next;
    for (var i = 0; i < items.length; i++) {
      final item = _withStreakReason(items[i]);
      if (identical(item, items[i])) continue;
      (next ??= List.of(items))[i] = item;
    }
    if (next != null) {
      final byId = {for (final item in next) item.game.gameId: item};
      _serverEntries = [
        for (final entry in _serverEntries ?? const [])
          if (entry case FeedGameEntry(:final item))
            FeedGameEntry(byId[item.game.gameId] ?? item)
          else
            entry,
      ];
      state = AsyncData(List.unmodifiable(next));
    }
  }

  Future<void> _append(int generation, List<FeedItem> items) async {
    if (!state.hasValue) {
      try {
        await future;
      } catch (_) {
        // A failed build leaves nothing to append to; start from empty.
      }
    }
    if (generation != _generation) return;
    final current = state.valueOrNull ?? const <FeedItem>[];
    // Games landed from behind (the opening pages, a warm launch's fresh
    // ones): whatever stalled before is past.
    if (_more == FeedMore.stalled) _more = FeedMore.open;
    state = AsyncData(List.unmodifiable([...current, ...items]));
  }

  /// Keeps [FeedSfx] in step with the board's Sound setting, read the same
  /// way `FeedMoveSound` and the board read it: loading or failed is off.
  void _bindBoardSound() {
    ref.listen<AsyncValue<BoardSettingsNew>>(boardSettingsProviderNew, (
      _,
      next,
    ) {
      FeedSfx.instance.boardSoundEnabled =
          next.valueOrNull?.soundEnabled == true;
    }, fireImmediately: true);
  }

  Future<void> _writeCache(List<FeedItem> items, String userId) async {
    try {
      await AppDatabase.instance.setCache(
        key: cacheKey,
        userId: userId,
        value: encodeFlowFeedCache(items),
      );
    } catch (error) {
      debugPrint('[Feed] cache write failed: $error');
    }
  }
}

// -----------------------------------------------------------------------------
// Pure helpers (top level so the isolate entry point captures nothing)
// -----------------------------------------------------------------------------

List<FeedClip?> _parseFlowClips(List<String> pgns) => [
  for (final pgn in pgns) feedClipFromPgn(pgn),
];

/// [game] as the post Watch opens Feed on ([FeedScreen.watch]), its moves
/// read off [pgn]. Unlike the feed's own draws it needs no report and no
/// finished result: any game with a move to play is watchable, a live one
/// up to the move it has reached. [likeable] and [exportable] carry what
/// the board it came from allows. Null when [pgn] has no playable mainline.
FeedItem? feedWatchItem(
  GamesTourModel game,
  String pgn, {
  bool likeable = true,
  bool exportable = true,
  bool hideEvaluation = false,
  bool hideResult = false,
}) {
  final clip = feedClipFromPgn(
    feedSpoilerFreePgn(pgn, evaluation: hideEvaluation, result: hideResult),
  );
  if (clip == null || clip.plyCount < 1) return null;
  return FeedItem(
    // Share and Save read the moves off the game.
    game: game.copyWith(pgn: pgn, isPgnDeferred: false),
    plies: clip.plies,
    reason: '',
    eventLabel:
        clip.event ?? _archiveEventOf(game) ?? _prettySlug(game.tourSlug),
    result: hideResult ? null : clip.result ?? _resultOf(game.gameStatus),
    hasEvals: clip.hasEvals,
    likeable: likeable,
    exportable: exportable,
    boardGame: game,
    hideEvaluation: hideEvaluation,
    hideResult: hideResult,
  );
}

final RegExp _evalComment = RegExp(r'\[%eval[^\]]*\]');
final RegExp _resultHeader = RegExp(r'\[Result\s+"[^"]*"\]');
final RegExp _resultToken = RegExp(r'(1-0|0-1|1/2-1/2|½-½)\s*$');

/// [pgn] without what No Spoilers hides, so the clip is built without it:
/// its [%eval] comments ([evaluation]: no eval, and no verdict read off an
/// eval swing), and its result ([result]: no "White wins" on the last move).
/// The report's own move classes stay, as the board still shows them.
@visibleForTesting
String feedSpoilerFreePgn(
  String pgn, {
  required bool evaluation,
  required bool result,
}) {
  var out = pgn;
  if (evaluation) out = out.replaceAll(_evalComment, '');
  if (result) {
    out = out
        .replaceAll(_resultHeader, '[Result "*"]')
        .replaceFirst(_resultToken, '*');
  }
  return out;
}

GamesTourModel? _tourModel(Games row) {
  if (!const {'1-0', '0-1', '1/2-1/2'}.contains(row.status)) return null;
  try {
    return GamesTourModel.fromGame(row);
  } catch (_) {
    return null; // missing players / names: not showable anyway
  }
}

String? _resultOf(GameStatus status) => switch (status) {
  GameStatus.whiteWins => '1-0',
  GameStatus.blackWins => '0-1',
  GameStatus.draw => '½-½',
  _ => null,
};

/// [exported], or [recorded] when [exported] only adds moves past the end
/// of [recorded]'s mainline. A board that lets the reader extend a game's
/// mainline (board-editor games: imported, prep and collection games)
/// exports their moves after the last one as the game's own; Watch plays
/// the game as it was recorded. A changed move, or a recorded PGN with no
/// moves (a position set up in the editor), keeps [exported].
String feedRecordedPgn(String? recorded, String exported) {
  final own = recorded == null ? null : parseFlowPgn(recorded);
  if (own == null || own.moves.isEmpty) return exported;
  final shown = parseFlowPgn(exported);
  if (shown == null || shown.moves.length <= own.moves.length) return exported;
  for (var i = 0; i < own.moves.length; i++) {
    if (shown.moves[i].uci != own.moves[i].uci) return exported;
  }
  return recorded!;
}

/// The event an archive game names in its tourId (the gamebase event, as
/// the board shows it), when its PGN gives none Feed can read. Null for
/// other sources, and for the archive's placeholder names.
String? _archiveEventOf(GamesTourModel game) {
  if (game.source != GameSource.gamebase && game.source != GameSource.twic) {
    return null;
  }
  final event = game.tourId.trim();
  if (event.isEmpty || event == 'Miniatures' || event == 'Gamebase') {
    return null;
  }
  return event;
}

String? _prettySlug(String? slug) {
  final value = slug?.trim();
  if (value == null || value.isEmpty) return null;
  if (!value.contains('-')) return value;
  return value
      .split('-')
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');
}
