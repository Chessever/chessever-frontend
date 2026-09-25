import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:chessever2/config/feature_flags.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/feed/audio/feed_sfx.dart';
import 'package:chessever2/screens/feed/logic/feed_codec.dart';
import 'package:chessever2/screens/feed/logic/feed_moments.dart';
import 'package:chessever2/screens/feed/logic/feed_ranker.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/for_you/discovery/data/discovery_repository.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/standings/providers/player_utils_provider.dart';
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/providers/streak_providers.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The Feed: interesting finished games, fully parsed into plies with
/// critical moments, drawn from a pool by [FeedRanker] so every session is
/// its own mix.
///
/// Sources, all read in parallel into one pool (listing columns only, so a
/// read is a few kilobytes):
/// 1. games of the events running now (`group_broadcasts_current`), the
///    strongest events first by weight;
/// 2. strong decisive-leaning games from anywhere this week;
/// 3. games of the players the user follows;
/// 4. today's most liked games;
/// 5. Gamebase miniatures (today, else this week).
///
/// The ranker picks; only then are the picked games' PGNs fetched, in one
/// batched request, and parsed in a background isolate.
///
/// How it starts fast:
/// - **Warm launch.** The last first page lives in SQLite, already parsed.
///   `build` paints it straight from disk and ranks fresh games behind it.
/// - **Cold launch.** The first page is cut at [_firstPageSize] games as
///   soon as the two public sources answer (followed players get a short
///   grace); the rest of the opening pages follow behind it.
///
/// Games shown in earlier sessions are remembered and demoted, so the feed
/// is new every time it opens. [refresh] re-rolls it with a new seed.
final feedProvider = AsyncNotifierProvider<FeedNotifier, List<FeedItem>>(
  FeedNotifier.new,
);

/// One game waiting to become a [FeedItem].
class _FeedCandidate {
  const _FeedCandidate({
    required this.game,
    required this.signals,
    this.pgn,
    this.loadPgn,
    this.hint,
  });

  final GamesTourModel game;
  final FeedSignals signals;

  /// PGN already downloaded with the listing, when the source includes it.
  final String? pgn;

  /// Its own request, for sources outside the `games` table. Null means
  /// the PGN comes from `games` in the page's batched read.
  final Future<String?> Function()? loadPgn;

  /// Caption input: the followed player's display name, or the miniature
  /// window (`today` / `week`).
  final String? hint;

  bool get hasInlinePgn => pgn != null && pgn!.trim().isNotEmpty;

  FeedPool get pool => signals.pool;

  /// What the caption code calls this source.
  FeedSource get source => switch (pool) {
    FeedPool.favorite => FeedSource.favorite,
    FeedPool.miniature => FeedSource.miniature,
    _ => FeedSource.decisive,
  };
}

/// The next refresh, already done: parsed games drawn by their own ranker
/// from a slice of the week the current feed has not touched, plus what
/// that slice had left for the pages after them.
class _FeedReserve {
  const _FeedReserve({
    required this.items,
    required this.ranker,
    required this.leftovers,
  });

  final List<FeedItem> items;
  final FeedRanker ranker;
  final Map<String, _FeedCandidate> leftovers;
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
/// exactly the page [FeedNotifier.build] paints on its next open. Empty when
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
  static const String cacheKey = 'flow_feed_first_page_v1';
  static const String _shownKey = 'flow_feed_shown_v1';
  static const Duration _cacheMaxAge = Duration(days: 3);

  /// Games in the page `build` returns: two, so the first board plays as
  /// soon as one small batch is parsed. The opening pages follow behind.
  static const int _firstPageSize = 2;
  static const int _openingTopUp = 4;
  static const int _pageSize = 5;

  /// Items kept ready beyond the one on screen.
  static const int _prefetchAhead = 2;

  /// Below this many candidates in the pool, sources are read again.
  static const int _poolLow = 14;

  /// Shown game ids remembered across launches (newest kept).
  static const int _shownMemory = 400;

  static const int _currentMinEventElo = 2300;
  static const int _currentMinRating = 2300;
  static const int _currentLimit = 60;
  static const int _topMinRating = 2550;
  static const int _topLimit = 40;

  /// Games in a reserve: the page a refresh lands on, before any request.
  static const int _reserveSize = 3;

  /// Refresh draws explore the week in slices of [_topLimit] rows, up to
  /// this many slices back from the newest.
  static const int _sliceCount = 24;
  static const int _favoriteLimit = 16;
  static const int _likedLimit = 20;
  static const int _miniatureLimit = 8;

  static const Duration _currentAge = Duration(days: 4);
  static const Duration _topAge = Duration(days: 7);
  static const Duration _favoriteAge = Duration(days: 14);
  static const Duration _favoriteGrace = Duration(milliseconds: 400);
  static const Duration _sourceTimeout = Duration(seconds: 6);
  static const Duration _pgnTimeout = Duration(seconds: 8);
  static const Duration _refreshTimeout = Duration(seconds: 15);

  static const int _minPlies = 10;
  static const int _minDrawPlies = 30;

  int _generation = 0;
  FeedRanker _ranker = FeedRanker(0);

  /// Every game already in the list (or picked for it) this generation.
  final Set<String> _seen = <String>{};

  /// Games shown in earlier sessions or before a refresh; demoted, not
  /// excluded, so a quiet day still has a feed.
  final Set<String> _shownBefore = <String>{};
  final List<String> _shownOrder = <String>[];
  bool _shownLoaded = false;

  final Map<String, _FeedCandidate> _pool = <String, _FeedCandidate>{};
  bool _loadingMore = false;

  /// The source reads running now; a second refill joins them instead of
  /// asking every source again.
  ({Future<void> all, Future<void> public, Future<void> favorites})? _inFlight;

  Map<String, int>? _currentTours;
  int _currentOffset = 0;
  bool _currentExhausted = false;
  int _topOffset = 0;
  bool _topExhausted = false;
  int _favoriteOffset = 0;
  bool _favoritesExhausted = false;
  bool _likedExhausted = false;

  /// Ready for the next pull; see [_prepareReserve].
  _FeedReserve? _reserve;
  bool _preparingReserve = false;
  final math.Random _slices = math.Random();
  int _miniatureOffset = 0;
  MiniatureGamesWindow _miniatureWindow = MiniatureGamesWindow.today;
  bool _miniaturesExhausted = false;

  /// Failed requests to the sources every user has. When they all fail and
  /// nothing is cached, the feed reports an error instead of an empty page,
  /// so the screen can offer a retry.
  int _publicSourceFailures = 0;
  Object? _lastFailure;

  @override
  Future<List<FeedItem>> build() async {
    final generation = ++_generation;
    _resetPaging();
    _ranker = FeedRanker(_newSeed());
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

    // The sources start now, alongside the disk reads, not after them.
    final sources = _refillAll(generation);
    final (cachedRaw, _) = await (_readCache(), _loadShown()).wait;
    if (generation != _generation) return const [];
    final cached = cachedRaw.map(_withStreakReason).toList();
    if (cached.isNotEmpty) {
      for (final item in cached) {
        _seen.add(item.game.gameId);
      }
      unawaited(
        _refreshBehindCache(
          generation,
          sources,
        ).then((_) => _prepareReserve(generation)),
      );
      return cached;
    }
    final first = await _loadFirstPage(generation, sources);
    if (generation == _generation && first.isNotEmpty) {
      unawaited(
        _topUp(
          generation,
          _openingTopUp,
          cacheFirst: first,
        ).then((_) => _prepareReserve(generation)),
      );
    }
    return first;
  }

  /// Pull-to-refresh: a new draw over fresh sources.
  ///
  /// With a reserve ready (the usual case) the new page lands in the same
  /// frame, no request in the way, and fresh sources are read behind it.
  /// Without one, the current page stays on screen while the fetch runs and
  /// is swapped only when the fresh page is ready, so a failed refresh keeps
  /// the old content (and rethrows, for the screen to say so). What the
  /// viewer was shown is demoted either way, and the refreshed feed explores
  /// a random slice of the week rather than re-reading the newest games.
  Future<void> refresh() async {
    final generation = ++_generation;
    final showing = [
      for (final item in state.valueOrNull ?? const <FeedItem>[])
        item.game.gameId,
    ];
    showing.forEach(_remember);
    final reserve = _reserve;
    _reserve = null;
    _resetPaging();
    // What is on screen stays out of the new draw, and out of any page
    // appended to the old list should this refresh fail.
    _seen.addAll(showing);
    _topOffset = _randomSlice();

    if (reserve != null && reserve.items.isNotEmpty) {
      _ranker = reserve.ranker;
      for (final item in reserve.items) {
        _seen.add(item.game.gameId);
      }
      for (final candidate in reserve.leftovers.values) {
        _offer(candidate);
      }
      state = AsyncData(List.unmodifiable(reserve.items));
      _recaption();
      unawaited(_afterInstantRefresh(generation, reserve.items));
      return;
    }

    _ranker = FeedRanker(_newSeed());
    final first = await _loadFirstPage(generation, _refillAll(generation))
        .timeout(
          _refreshTimeout,
          onTimeout: () {
            // Abandoned: a late answer must not replace the page the viewer
            // has since moved on from.
            if (generation == _generation) {
              _generation++;
              _loadingMore = false;
            }
            throw TimeoutException('Feed refresh', _refreshTimeout);
          },
        );
    if (generation != _generation) return;
    if (first.isEmpty) throw StateError('Feed refresh found nothing new');
    state = AsyncData(List.unmodifiable(first));
    _recaption();
    unawaited(
      _topUp(
        generation,
        _openingTopUp,
        cacheFirst: first,
      ).then((_) => _prepareReserve(generation)),
    );
  }

  /// Behind an instant refresh: every source again, the pages after the
  /// reserve, then the reserve for the pull after this one.
  Future<void> _afterInstantRefresh(
    int generation,
    List<FeedItem> first,
  ) async {
    try {
      final sources = _refillAll(generation);
      // The reserve's leftovers usually cover the next pages already.
      if (_pool.length < _openingTopUp) await sources.all;
      if (generation != _generation) return;
      await _topUp(generation, _openingTopUp, cacheFirst: first);
      await sources.all;
      await _prepareReserve(generation);
    } catch (error, stack) {
      debugPrint('[Feed] after refresh failed: $error\n$stack');
    }
  }

  int _randomSlice() => _slices.nextInt(_sliceCount) * _topLimit;

  /// Parses the next refresh ahead of time: [_reserveSize] games drawn by a
  /// fresh ranker from a random slice of the week's strong games, joined by
  /// a share of what the running events and the viewer's own sources have
  /// in the pool. Its games leave this feed's draw, so the refresh is new.
  Future<void> _prepareReserve(int generation) async {
    if (_reserve != null || _preparingReserve) return;
    _preparingReserve = true;
    try {
      final slice = <String, _FeedCandidate>{};
      final repository = ref.read(gameRepositoryProvider);
      final since = DateTime.now().subtract(_topAge);
      var rows = await repository.getFeedCandidateGames(
        since: since,
        minRating: _topMinRating,
        limit: _topLimit,
        offset: _randomSlice(),
      );
      if (rows.isEmpty) {
        rows = await repository.getFeedCandidateGames(
          since: since,
          minRating: _topMinRating,
          limit: _topLimit,
        );
      }
      if (generation != _generation) return;
      for (final row in rows) {
        final game = _tourModel(row);
        if (game == null || _seen.contains(game.gameId)) continue;
        if (!game.gameStatus.isFinished) continue;
        slice[game.gameId] = _FeedCandidate(
          game: game,
          signals: _signalsOf(game, FeedPool.top),
        );
      }
      // Some of the pool's own flavour: current events, followed players,
      // likes and miniatures, a few each, taken out of this feed's draw.
      final byPool = <FeedPool, int>{};
      for (final candidate in _pool.values.toList()..shuffle(_slices)) {
        if (candidate.pool == FeedPool.top) continue;
        final taken = byPool[candidate.pool] ?? 0;
        if (taken >= 3) continue;
        byPool[candidate.pool] = taken + 1;
        slice[candidate.game.gameId] = candidate;
        _pool.remove(candidate.game.gameId);
      }
      if (slice.isEmpty) return;

      final ranker = FeedRanker(_newSeed());
      final items = await _materialize(
        generation,
        _reserveSize,
        from: slice,
        ranker: ranker,
      );
      if (generation != _generation || items.isEmpty) return;
      // The whole slice stays out of this feed: it is the next one's.
      _seen.addAll(slice.keys);
      _reserve = _FeedReserve(items: items, ranker: ranker, leftovers: slice);
    } catch (error) {
      debugPrint('[Feed] reserve failed: $error');
    } finally {
      _preparingReserve = false;
    }
  }

  /// Appends the next page. Safe to call repeatedly; no-ops while loading.
  Future<void> loadMore() async {
    if (_loadingMore || !state.hasValue) return;
    final generation = _generation;
    _loadingMore = true;
    try {
      var items = <FeedItem>[];
      // Two rounds: filters (short draws, unparsable PGNs) can empty a batch.
      for (var round = 0; round < 2 && items.isEmpty; round++) {
        if (_pool.length < _poolLow) await _refillAll(generation).all;
        if (generation != _generation) return;
        items = await _materialize(generation, _pageSize);
        if (generation != _generation) return;
        if (items.isEmpty && _allSourcesExhausted && _pool.isEmpty) break;
      }
      if (items.isNotEmpty) await _append(generation, items);
    } catch (error, stack) {
      debugPrint('[Feed] loadMore failed: $error\n$stack');
    } finally {
      if (generation == _generation) _loadingMore = false;
    }
  }

  /// Called when the viewer reaches [index] so the notifier can prefetch:
  /// at least [_prefetchAhead] ready clips are kept beyond it.
  void onVisible(int index) {
    final items = state.valueOrNull;
    if (items == null) return;
    if (index >= 0 && index < items.length) {
      _remember(items[index].game.gameId);
    }
    if (items.length - 1 - index <= _prefetchAhead + 1) {
      unawaited(loadMore());
    }
  }

  // ---------------------------------------------------------------------------
  // First page
  // ---------------------------------------------------------------------------

  Future<List<FeedItem>> _loadFirstPage(
    int generation,
    ({Future<void> all, Future<void> public, Future<void> favorites}) sources,
  ) async {
    // The two public sources decide the first pick; a followed player's game
    // gets a short grace to compete for it.
    await Future.wait([
      sources.public,
      sources.favorites.timeout(_favoriteGrace, onTimeout: () {}),
    ]).timeout(_sourceTimeout, onTimeout: () => const []);
    if (generation != _generation) return const [];
    if (_pool.isEmpty) {
      await sources.all.timeout(_sourceTimeout, onTimeout: () {});
      if (generation != _generation) return const [];
    }

    var items = await _materialize(generation, _firstPageSize);
    if (items.isEmpty && generation == _generation && _pool.isNotEmpty) {
      // The first picks all failed to load or parse: one more batch.
      items = await _materialize(generation, _firstPageSize + 2);
    }
    if (generation != _generation) return const [];
    if (items.isEmpty && _publicSourceFailures >= 2) {
      throw StateError('Feed unavailable: $_lastFailure');
    }
    return items;
  }

  /// The opening pages behind the first one, then the cache for next launch.
  Future<void> _topUp(
    int generation,
    int count, {
    required List<FeedItem> cacheFirst,
  }) async {
    try {
      final more = await _materialize(generation, count);
      if (generation != _generation) return;
      if (more.isNotEmpty) await _append(generation, more);
      unawaited(_writeCache([...cacheFirst, ...more]));
    } catch (error, stack) {
      debugPrint('[Feed] opening top-up failed: $error\n$stack');
    }
  }

  /// Warm launch: the cached page is on screen; rank fresh games behind it.
  Future<void> _refreshBehindCache(
    int generation,
    ({Future<void> all, Future<void> public, Future<void> favorites}) sources,
  ) async {
    try {
      await sources.all;
      if (generation != _generation) return;
      final fresh = await _materialize(generation, _pageSize);
      if (generation != _generation || fresh.isEmpty) return;
      await _append(generation, fresh);
      // Next launch opens on these, not on what the viewer just saw.
      unawaited(_writeCache(fresh));
    } catch (error, stack) {
      debugPrint('[Feed] background refresh failed: $error\n$stack');
    }
  }

  // ---------------------------------------------------------------------------
  // Sources
  // ---------------------------------------------------------------------------

  /// Reads every source that still has games, in parallel. [public] settles
  /// with the two sources every viewer has; [favorites] with the followed
  /// players; [all] with everything.
  ({Future<void> all, Future<void> public, Future<void> favorites}) _refillAll(
    int generation,
  ) {
    final running = _inFlight;
    if (running != null) return running;
    Future<void> guard(Future<void> Function() run) =>
        run().timeout(_sourceTimeout, onTimeout: () {});
    final public = Future.wait([
      if (!_currentExhausted) guard(() => _fetchCurrent(generation)),
      if (!_topExhausted) guard(() => _fetchTop(generation)),
    ]);
    final favorites = _favoritesExhausted
        ? Future<void>.value()
        : guard(() => _fetchFavorites(generation));
    final others = Future.wait([
      if (!_likedExhausted) guard(() => _fetchLiked(generation)),
      if (!_miniaturesExhausted) guard(() => _fetchMiniatures(generation)),
    ]);
    final all = Future.wait([public, favorites, others]);
    final reads = (all: all, public: public, favorites: favorites);
    _inFlight = reads;
    all.whenComplete(() {
      if (identical(_inFlight, reads)) _inFlight = null;
    }).ignore();
    return reads;
  }

  bool get _allSourcesExhausted =>
      _currentExhausted &&
      _topExhausted &&
      _favoritesExhausted &&
      _likedExhausted &&
      _miniaturesExhausted;

  /// Games of the events running now. The tour roster is read once per
  /// generation; the games page by offset.
  Future<void> _fetchCurrent(int generation) async {
    final repository = ref.read(gameRepositoryProvider);
    try {
      final tours = _currentTours ??= await repository.getCurrentEventTourElos(
        minEventElo: _currentMinEventElo,
      );
      if (generation != _generation) return;
      if (tours.isEmpty) {
        _currentExhausted = true;
        return;
      }
      final offset = _currentOffset;
      _currentOffset += _currentLimit;
      final rows = await repository.getFeedCandidateGames(
        since: DateTime.now().subtract(_currentAge),
        tourIds: tours.keys.toList(growable: false),
        minRating: _currentMinRating,
        limit: _currentLimit,
        offset: offset,
      );
      if (generation != _generation) return;
      if (rows.length < _currentLimit) _currentExhausted = true;
      for (final row in rows) {
        final game = _tourModel(row);
        if (game == null) continue;
        _offer(
          _FeedCandidate(
            game: game,
            signals: _signalsOf(
              game,
              FeedPool.current,
              eventElo: tours[row.tourId] ?? 0,
            ),
          ),
        );
      }
    } catch (error) {
      if (generation != _generation) return;
      debugPrint('[Feed] current events failed: $error');
      _publicSourceFailures++;
      _lastFailure = error;
      _currentExhausted = true;
    }
  }

  /// Strong games from anywhere this week.
  Future<void> _fetchTop(int generation) async {
    final offset = _topOffset;
    _topOffset += _topLimit;
    try {
      final rows = await ref
          .read(gameRepositoryProvider)
          .getFeedCandidateGames(
            since: DateTime.now().subtract(_topAge),
            minRating: _topMinRating,
            limit: _topLimit,
            offset: offset,
          );
      if (generation != _generation) return;
      if (rows.length < _topLimit) _topExhausted = true;
      for (final row in rows) {
        final game = _tourModel(row);
        if (game == null) continue;
        _offer(
          _FeedCandidate(game: game, signals: _signalsOf(game, FeedPool.top)),
        );
      }
    } catch (error) {
      if (generation != _generation) return;
      debugPrint('[Feed] top games failed: $error');
      _publicSourceFailures++;
      _lastFailure = error;
      _topExhausted = true;
    }
  }

  Future<void> _fetchFavorites(int generation) async {
    try {
      final favorites = await ref
          .read(favoritePlayersProviderNew.future)
          .timeout(const Duration(seconds: 4));
      final fideIds = <String>{
        for (final favorite in favorites)
          if ((favorite.fideId ?? '').trim().isNotEmpty)
            favorite.fideId!.trim(),
      };
      if (fideIds.isEmpty) {
        _favoritesExhausted = true;
        return;
      }
      final offset = _favoriteOffset;
      _favoriteOffset += _favoriteLimit;
      final games = await ref
          .read(gameRepositoryProvider)
          .getGamesByMultipleFideIds(
            fideIds: fideIds.toList(growable: false),
            limit: _favoriteLimit,
            offset: offset,
          );
      if (generation != _generation) return;
      if (games.length < _favoriteLimit) _favoritesExhausted = true;

      final followed = fideIds.map(int.tryParse).whereType<int>().toSet();
      var inWindow = 0;
      for (final row in games) {
        final game = _tourModel(row);
        if (game == null || !_isRecent(game, _favoriteAge)) continue;
        inWindow++;
        if (!game.gameStatus.isFinished) continue;
        final player = followed.contains(game.whitePlayer.fideId)
            ? game.whitePlayer
            : followed.contains(game.blackPlayer.fideId)
            ? game.blackPlayer
            : null;
        if (player == null) continue;
        _offer(
          _FeedCandidate(
            game: game,
            signals: _signalsOf(game, FeedPool.favorite),
            pgn: row.isPgnDeferred ? null : row.pgn,
            hint: formatPlayerDisplayName(player.name),
          ),
        );
      }
      if (games.isNotEmpty && inWindow == 0) _favoritesExhausted = true;
    } catch (error) {
      if (generation != _generation) return;
      debugPrint('[Feed] favorites failed: $error');
      _favoritesExhausted = true;
    }
  }

  /// Today's most liked games: the one Most Liked window every viewer may
  /// read. Read once per generation.
  Future<void> _fetchLiked(int generation) async {
    _likedExhausted = true;
    try {
      final result = await ref
          .read(discoveryRepositoryProvider)
          .fetchMostLiked(
            MostLikedQuery(MostLikedPeriod.today, DateTime.now()),
            limit: _likedLimit,
          );
      if (generation != _generation) return;
      final gamebase = ref.read(gamebaseRepositoryProvider);
      for (final entry in result.entries) {
        final game = entry.game;
        if (!game.gameStatus.isFinished) continue;
        _offer(
          _FeedCandidate(
            game: game,
            signals: _signalsOf(game, FeedPool.liked, likes: entry.likes),
            loadPgn: game.source == GameSource.gamebase
                ? () async => (await gamebase.getGameWithPgn(game.gameId))?.pgn
                : null,
          ),
        );
      }
    } catch (error) {
      debugPrint('[Feed] most liked failed: $error');
    }
  }

  Future<void> _fetchMiniatures(int generation) async {
    final repository = ref.read(gamebaseRepositoryProvider);
    try {
      var window = _miniatureWindow;
      var offset = _miniatureOffset;
      Future<GamebaseMiniaturesPage> read() => repository.getMiniatures(
        filter: MiniatureGamesFilter(
          window: window,
          sort: MiniatureGamesSort.rating,
          order: MiniatureGamesSortOrder.desc,
        ),
        limit: _miniatureLimit,
        offset: offset,
      );
      var page = await read();
      if (generation != _generation) return;
      // A quiet day: widen to the week once.
      if (page.items.isEmpty && window == MiniatureGamesWindow.today) {
        window = MiniatureGamesWindow.week;
        offset = 0;
        page = await read();
        if (generation != _generation) return;
      }
      _miniatureWindow = window;
      _miniatureOffset = offset + page.items.length;
      if (!page.hasMore) {
        if (window == MiniatureGamesWindow.today) {
          // Today is used up; carry on through the week.
          _miniatureWindow = MiniatureGamesWindow.week;
          _miniatureOffset = 0;
        } else {
          _miniaturesExhausted = true;
        }
      }
      for (final miniature in page.items) {
        final game = miniature.toGamesTourModel();
        _offer(
          _FeedCandidate(
            game: game,
            signals: _signalsOf(game, FeedPool.miniature),
            loadPgn: () async =>
                (await repository.getGameWithPgn(miniature.gameId))?.pgn,
            hint: window.name,
          ),
        );
      }
    } catch (error) {
      if (generation != _generation) return;
      debugPrint('[Feed] miniatures failed: $error');
      _publicSourceFailures++;
      _lastFailure = error;
      _miniaturesExhausted = true;
    }
  }

  FeedSignals _signalsOf(
    GamesTourModel game,
    FeedPool pool, {
    int likes = 0,
    int eventElo = 0,
  }) {
    final finished = game.lastMoveTime ?? game.bucketDate;
    String key(PlayerCard p) => p.fideId?.toString() ?? p.name.trim();
    return FeedSignals(
      id: game.gameId,
      pool: pool,
      whiteElo: game.whitePlayer.rating,
      blackElo: game.blackPlayer.rating,
      result: _resultOf(game.gameStatus) ?? '',
      age: finished == null
          ? const Duration(days: 30)
          : DateTime.now().difference(finished),
      likes: likes,
      eventElo: eventElo,
      eventKey: game.tourId,
      playerKeys: {key(game.whitePlayer), key(game.blackPlayer)},
    );
  }

  // ---------------------------------------------------------------------------
  // Pool → items
  // ---------------------------------------------------------------------------

  /// Adds [candidate] to the pool. A game several sources offer keeps the
  /// version that ranks higher, and any PGN either one carried.
  void _offer(_FeedCandidate candidate) {
    final id = candidate.game.gameId;
    if (_seen.contains(id) || !candidate.game.gameStatus.isFinished) return;
    final existing = _pool[id];
    if (existing == null) {
      _pool[id] = candidate;
      return;
    }
    final keep =
        feedInterest(candidate.signals) > feedInterest(existing.signals)
        ? candidate
        : existing;
    final other = identical(keep, candidate) ? existing : candidate;
    _pool[id] = keep.hasInlinePgn || !other.hasInlinePgn
        ? keep
        : _FeedCandidate(
            game: keep.game,
            signals: keep.signals,
            pgn: other.pgn,
            loadPgn: keep.loadPgn,
            hint: keep.hint,
          );
  }

  /// Draws up to [count] games from the pool, fetches the PGNs they still
  /// need (one batched read for every `games` row, in parallel with any
  /// others), then parses them all in one background isolate.
  Future<List<FeedItem>> _materialize(
    int generation,
    int count, {
    Map<String, _FeedCandidate>? from,
    FeedRanker? ranker,
  }) async {
    final pool = from ?? _pool;
    final draw = ranker ?? _ranker;
    // History may have loaded after a candidate was offered; read it now.
    final signals = [
      for (final c in pool.values)
        c.signals.withSeenBefore(_shownBefore.contains(c.game.gameId)),
    ];
    final picked = <_FeedCandidate>[];
    while (picked.length < count) {
      final next = draw.next(signals);
      if (next == null) break;
      final candidate = pool.remove(next.id);
      if (candidate == null || !_seen.add(next.id)) continue;
      picked.add(candidate);
    }
    if (picked.isEmpty) return const [];

    final batchIds = [
      for (final c in picked)
        if (!c.hasInlinePgn && c.loadPgn == null) c.game.gameId,
    ];
    final (batch, own) = await (
      _batchPgns(batchIds),
      Future.wait([
        for (final c in picked)
          c.hasInlinePgn || c.loadPgn == null
              ? Future<String?>.value(c.pgn)
              : _loadOwnPgn(c),
      ]),
    ).wait;
    if (generation != _generation) return const [];

    final ready = <(_FeedCandidate, String)>[];
    for (var i = 0; i < picked.length; i++) {
      final pgn = own[i] ?? batch[picked[i].game.gameId];
      if (pgn != null && pgn.trim().isNotEmpty) ready.add((picked[i], pgn));
    }
    if (ready.isEmpty) return const [];

    final clips = await compute(_parseFlowClips, [
      for (final (_, pgn) in ready) pgn,
    ]);

    final now = DateTime.now();
    final items = <FeedItem>[];
    for (var i = 0; i < ready.length; i++) {
      final (candidate, pgn) = ready[i];
      final item = _toItem(candidate, clips[i], pgn, now);
      if (item != null) items.add(item);
    }
    return items;
  }

  Future<Map<String, String>> _batchPgns(List<String> ids) async {
    if (ids.isEmpty) return const {};
    try {
      return await ref
          .read(gameRepositoryProvider)
          .getGamePgns(ids)
          .timeout(_pgnTimeout);
    } catch (error) {
      debugPrint('[Feed] PGN batch failed: $error');
      return const {};
    }
  }

  Future<String?> _loadOwnPgn(_FeedCandidate candidate) async {
    try {
      final pgn = await candidate.loadPgn!().timeout(_pgnTimeout);
      return pgn == null || pgn.trim().isEmpty ? null : pgn;
    } catch (error) {
      debugPrint('[Feed] PGN for ${candidate.game.gameId} failed: $error');
      return null;
    }
  }

  FeedItem? _toItem(
    _FeedCandidate candidate,
    FeedClip? clip,
    String pgn,
    DateTime now,
  ) {
    if (clip == null || clip.plyCount < _minPlies) return null;
    final game = candidate.game;
    if (game.gameStatus.isOngoing) return null;
    final result = clip.result ?? _resultOf(game.gameStatus);
    if (result == null) return null;
    if (result == '½-½' && clip.plyCount < _minDrawPlies) return null;

    final streak = _streakOf(game, result, event: clip.event);
    return FeedItem(
      // Listings carry no moves; hand the board the ones just fetched.
      game: game.copyWith(pgn: pgn, isPgnDeferred: false),
      plies: clip.plies,
      reason:
          streak?.reason ??
          feedReasonFor(
            source: candidate.source,
            hint: candidate.hint,
            game: game,
            plies: clip.plies,
            result: result,
            now: now,
          ),
      eventLabel: clip.event ?? _prettySlug(game.tourSlug),
      result: result,
      hasEvals: clip.hasEvals,
      signal: streak?.signal ?? _signalFor(candidate),
    );
  }

  /// The header mark a source earns on its own, strongest first: the
  /// followed player, today's likes, an upset, a miniature. Top boards of a
  /// running event earn none: the event label already says where it is.
  static FeedSignal? _signalFor(_FeedCandidate candidate) {
    final s = candidate.signals;
    if (s.pool == FeedPool.favorite) {
      final name = candidate.hint?.trim() ?? '';
      if (name.isNotEmpty) {
        return FeedSignal(FeedSignalKind.favorite, name: name);
      }
    }
    if (s.pool == FeedPool.liked && s.likes > 1) {
      return FeedSignal(FeedSignalKind.liked, count: s.likes);
    }
    if (s.winnerMargin <= -_upsetMargin) {
      return FeedSignal(FeedSignalKind.upset, count: -s.winnerMargin);
    }
    if (s.pool == FeedPool.miniature) {
      return const FeedSignal(FeedSignalKind.miniature);
    }
    return null;
  }

  /// Rating points the winner must have been below the loser for the
  /// header to call it an upset.
  static const int _upsetMargin = 150;

  /// The streak ledger's online rule on event names
  /// (`player_streak_is_online`), applied to the tour slug and the PGN
  /// `[Event]`. Not [GamesTourModel.isOnline]: that only means the game
  /// carries a Lichess id, which every relayed OTB broadcast game does.
  static final RegExp _onlineEventName = RegExp(
    r'(titled tuesday|\bonline\b|chess\.com|\bchesscom\b|\blichess\b'
    r'|\bbullet\b|speed chess championship|champions chess tour|\bcct\b'
    r'|freestyle friday|\d\+\d\s*thursday|\binternet\b|\bvirtual\b'
    r'|titled arena|\btornelo\b|\bchess24\b|\be-?sports\b)',
    caseSensitive: false,
  );

  static bool _isOnlineEvent(GamesTourModel game, String? event) {
    final slug = game.tourSlug?.replaceAll(RegExp(r'[-_]+'), ' ') ?? '';
    return _onlineEventName.hasMatch('$slug ${event ?? ''}');
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
    if (_isOnlineEvent(game, event)) return null;

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
    if (next != null) state = AsyncData(List.unmodifiable(next));
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
    state = AsyncData(List.unmodifiable([...current, ...items]));
  }

  // ---------------------------------------------------------------------------
  // Plumbing
  // ---------------------------------------------------------------------------

  void _resetPaging() {
    _seen.clear();
    _pool.clear();
    _loadingMore = false;
    _inFlight = null;
    _reserve = null;
    _currentTours = null;
    _currentOffset = 0;
    _currentExhausted = false;
    _topOffset = 0;
    _topExhausted = false;
    _favoriteOffset = 0;
    _favoritesExhausted = false;
    _likedExhausted = false;
    _miniatureOffset = 0;
    _miniatureWindow = MiniatureGamesWindow.today;
    _miniaturesExhausted = false;
    _publicSourceFailures = 0;
    _lastFailure = null;
  }

  static int _newSeed() => math.Random().nextInt(1 << 31);

  /// Notes [id] as shown to this viewer, for this and later sessions.
  void _remember(String id) {
    if (!_shownBefore.add(id)) return;
    _shownOrder.add(id);
    if (_shownOrder.length > _shownMemory) {
      _shownBefore.remove(_shownOrder.removeAt(0));
    }
    _scheduleShownWrite();
  }

  Timer? _shownWrite;

  /// Coalesces a burst of swipes into one small write.
  void _scheduleShownWrite() {
    if (!_shownLoaded) return;
    _shownWrite?.cancel();
    _shownWrite = Timer(const Duration(seconds: 3), () {
      unawaited(_writeShown());
    });
  }

  Future<void> _loadShown() async {
    if (_shownLoaded) return;
    try {
      final entry = await AppDatabase.instance.getCache(
        key: _shownKey,
        userId: _userId,
        maxAge: const Duration(days: 30),
      );
      final ids = entry == null
          ? const <Object?>[]
          : (jsonDecode(entry.value) as List<Object?>);
      // Stored oldest first; anything noted this session stays newest.
      final stored = [
        for (final id in ids.whereType<String>())
          if (_shownBefore.add(id)) id,
      ];
      _shownOrder.insertAll(0, stored);
      while (_shownOrder.length > _shownMemory) {
        _shownBefore.remove(_shownOrder.removeAt(0));
      }
    } catch (error) {
      debugPrint('[Feed] shown history unreadable: $error');
    } finally {
      _shownLoaded = true;
    }
  }

  Future<void> _writeShown() async {
    try {
      await AppDatabase.instance.setCache(
        key: _shownKey,
        userId: _userId,
        value: jsonEncode(_shownOrder),
      );
    } catch (error) {
      debugPrint('[Feed] shown history write failed: $error');
    }
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

  String? get _userId => feedCacheUserId();

  Future<List<FeedItem>> _readCache() => readFeedFirstPageCache(userId: _userId);

  Future<void> _writeCache(List<FeedItem> items) async {
    try {
      await AppDatabase.instance.setCache(
        key: cacheKey,
        userId: _userId,
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

GamesTourModel? _tourModel(Games row) {
  try {
    return GamesTourModel.fromGame(row);
  } catch (_) {
    return null; // missing players / names: not showable anyway
  }
}

bool _isRecent(GamesTourModel game, Duration maxAge) {
  final played = game.bucketDate;
  if (played == null) return false;
  return DateTime.now().difference(played) <= maxAge;
}

String? _resultOf(GameStatus status) => switch (status) {
  GameStatus.whiteWins => '1-0',
  GameStatus.blackWins => '0-1',
  GameStatus.draw => '½-½',
  _ => null,
};

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
