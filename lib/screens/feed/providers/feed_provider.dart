import 'dart:async';

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
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/standings/providers/player_utils_provider.dart';
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/providers/streak_providers.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The Feed: interesting finished games, fully parsed into plies with
/// critical moments, ordered so the first clip can start instantly.
///
/// How it starts instantly:
/// - **Warm launch.** The last good first page lives in SQLite, already parsed
///   (plies, moments, captions). `build` paints it straight from disk and
///   fetches fresh games behind it, appending them and re-caching.
/// - **Cold launch.** Every source is queried in parallel, but the first page
///   is cut as soon as the one-query Supabase source answers (favorites get a
///   short grace to join). Only games whose PGN is already in hand go into it;
///   miniatures, which need a second request per game, join from page two.
///
/// Sources, interleaved so the feed never runs one kind for long:
/// 1. prewarmed annotated games — finished top boards from the last ~48h whose
///    `games.pgn` carries `[%eval]` (and often a report's `$240`–`$247` NAGs);
/// 2. games of the players the user follows;
/// 3. Gamebase miniatures (today, else this week), strongest first;
/// 4. decisive high-Elo games without evals.
///
/// Parsing and moment detection run in a background isolate. Unfinished games
/// and draws under 30 plies are skipped; every game appears at most once.
final feedProvider =
    AsyncNotifierProvider<FeedNotifier, List<FeedItem>>(
      FeedNotifier.new,
    );

/// One game waiting to become a [FeedItem].
class _FeedCandidate {
  const _FeedCandidate({
    required this.game,
    required this.source,
    this.pgn,
    this.loadPgn,
    this.hint,
  });

  final GamesTourModel game;
  final FeedSource source;

  /// PGN already downloaded with the listing, when the source includes it.
  final String? pgn;

  /// Second request for sources whose listing carries no moves.
  final Future<String?> Function()? loadPgn;

  /// Caption input: the followed player's display name, or the miniature
  /// window (`today` / `week`).
  final String? hint;

  bool get hasInlinePgn => pgn != null && pgn!.trim().isNotEmpty;
}

class FeedNotifier extends AsyncNotifier<List<FeedItem>> {
  static const String _cacheKey = 'flow_feed_first_page_v1';
  static const Duration _cacheMaxAge = Duration(days: 3);

  static const int _firstPageSize = 5;
  static const int _pageSize = 6;

  /// Items kept ready beyond the one on screen.
  static const int _prefetchAhead = 2;

  static const int _topMinElo = 2550;

  /// `getHighEloGames` reads `3 × limit` rows and filters by Elo in Dart, so
  /// its next page starts `3 × limit` rows further on.
  static const int _topLimit = 12;
  static const int _topRowsPerPage = _topLimit * 3;
  static const int _favoriteLimit = 16;
  static const int _miniatureLimit = 8;

  static const Duration _freshAge = Duration(hours: 48);
  static const Duration _windowAge = Duration(days: 7);
  static const Duration _favoriteAge = Duration(days: 14);
  static const Duration _favoriteGrace = Duration(milliseconds: 600);
  static const Duration _pgnTimeout = Duration(seconds: 8);

  static const int _minPlies = 10;
  static const int _minDrawPlies = 30;

  /// Five slots: annotated games get two, everything else one.
  static const List<FeedSource> _schedule = [
    FeedSource.annotated,
    FeedSource.favorite,
    FeedSource.annotated,
    FeedSource.miniature,
    FeedSource.decisive,
  ];

  int _generation = 0;
  final Set<String> _seen = <String>{};
  final Map<FeedSource, List<_FeedCandidate>> _queues = {
    for (final source in FeedSource.values) source: <_FeedCandidate>[],
  };
  int _slot = 0;
  bool _loadingMore = false;
  Future<void>? _refilling;

  int _topOffset = 0;
  int _topEmptyPages = 0;
  bool _topExhausted = false;
  int _favoriteOffset = 0;
  bool _favoritesExhausted = false;
  int _miniatureOffset = 0;
  MiniatureGamesWindow _miniatureWindow = MiniatureGamesWindow.today;
  bool _miniaturesExhausted = false;

  /// Failed requests to the two sources every user has (top games,
  /// miniatures). When both fail and nothing is cached, the feed reports an
  /// error instead of an empty page, so the screen can offer a retry.
  int _publicSourceFailures = 0;
  Object? _lastFailure;

  @override
  Future<List<FeedItem>> build() async {
    final generation = ++_generation;
    _resetPaging();
    _bindBoardSound();

    // Warm the streak wall so winners on a run can say so in their caption.
    // The wall usually lands after the cached page is on screen (it decodes
    // ~2k rows in an isolate), so items already shown are recaptioned then.
    ref.listen<AsyncValue<List<StreakRow>>>(streakWallProvider, (
      previous,
      next,
    ) {
      final rows = next.valueOrNull;
      if (rows == null || identical(rows, previous?.valueOrNull)) return;
      if (generation != _generation) return;
      unawaited(_recaptionWhenBuilt(generation));
    });

    final cached = (await _readCache()).map(_withStreakReason).toList();
    if (generation != _generation) return cached;
    if (cached.isNotEmpty) {
      for (final item in cached) {
        _seen.add(item.game.gameId);
      }
      unawaited(_refreshBehindCache(generation));
      return cached;
    }
    return _loadFirstPage(generation);
  }

  /// Appends the next page. Safe to call repeatedly; no-ops while loading.
  Future<void> loadMore() async {
    if (_loadingMore || !state.hasValue) return;
    final generation = _generation;
    _loadingMore = true;
    try {
      var items = <FeedItem>[];
      // Two rounds: filters (draws, unfinished) can empty a small batch.
      for (var round = 0; round < 2 && items.isEmpty; round++) {
        if (_queuedCount < _pageSize) await _refillQueues(generation);
        if (generation != _generation) return;
        items = await _materialize(_pageSize);
        if (generation != _generation) return;
        if (items.isEmpty && _allSourcesExhausted && _queuedCount == 0) break;
      }
      if (items.isNotEmpty) await _append(generation, items);
    } catch (error, stack) {
      debugPrint('[Feed] loadMore failed: $error\n$stack');
    } finally {
      if (generation == _generation) _loadingMore = false;
    }
  }

  /// Called when the viewer reaches [index] so the notifier can prefetch.
  ///
  /// Items in the list are always fully parsed, so "prefetch" means keeping at
  /// least [_prefetchAhead] ready clips beyond [index]: when the tail gets that
  /// close, the next page's PGNs are fetched and parsed in the background.
  void onVisible(int index) {
    final items = state.valueOrNull;
    if (items == null) return;
    if (items.length - 1 - index <= _prefetchAhead + 1) {
      unawaited(loadMore());
    }
  }

  // ---------------------------------------------------------------------------
  // First page
  // ---------------------------------------------------------------------------

  Future<List<FeedItem>> _loadFirstPage(int generation) async {
    final top = _fetchTop(generation);
    final favorites = _fetchFavorites(generation);
    final miniatures = _fetchMiniatures(generation);

    await top;
    if (generation != _generation) return const [];
    // Give a followed player's game a moment to make the first page.
    await favorites.timeout(_favoriteGrace, onTimeout: () {});
    if (generation != _generation) return const [];

    var items = await _materialize(_firstPageSize, inlineOnly: true);
    if (items.isEmpty && generation == _generation) {
      // Nothing inline yet: wait for every source and pay for PGN fetches.
      await Future.wait([favorites, miniatures]);
      if (generation != _generation) return const [];
      if (_queuedCount == 0) await _refillQueues(generation);
      items = await _materialize(_firstPageSize);
    }
    if (generation != _generation) return const [];
    if (items.isEmpty && _publicSourceFailures >= 2) {
      throw StateError('Feed unavailable: $_lastFailure');
    }
    if (items.isNotEmpty) unawaited(_writeCache(items));
    return items;
  }

  /// Warm launch: the cached page is on screen; fetch fresh games behind it.
  Future<void> _refreshBehindCache(int generation) async {
    try {
      await Future.wait([
        _fetchTop(generation),
        _fetchFavorites(generation),
        _fetchMiniatures(generation),
      ]);
      if (generation != _generation) return;
      final fresh = await _materialize(_firstPageSize);
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

  Future<void> _refillQueues(int generation) {
    return _refilling ??= () async {
      try {
        await Future.wait([
          if (!_topExhausted) _fetchTop(generation),
          if (!_favoritesExhausted) _fetchFavorites(generation),
          if (!_miniaturesExhausted) _fetchMiniatures(generation),
        ]);
      } finally {
        _refilling = null;
      }
    }();
  }

  bool get _allSourcesExhausted =>
      _topExhausted && _favoritesExhausted && _miniaturesExhausted;

  /// Top boards, finished, recent. Annotated ones (PGN carries `[%eval]`) are
  /// the prewarmed content; decisive ones without evals fill in behind.
  ///
  /// Games from the last [_freshAge] lead their queue; older ones inside
  /// [_windowAge] follow, so a quiet day between tournaments still has a feed.
  Future<void> _fetchTop(int generation) async {
    if (_topExhausted) return;
    final offset = _topOffset;
    _topOffset += _topRowsPerPage;
    try {
      final games = await ref
          .read(gameRepositoryProvider)
          .getHighEloGames(
            minElo: _topMinElo,
            limit: _topLimit,
            offset: offset,
          );
      if (generation != _generation) return;

      final fresh = <_FeedCandidate>[];
      final older = <_FeedCandidate>[];
      var inWindow = 0;
      for (final row in games) {
        final game = _tourModel(row);
        if (game == null || !_isRecent(game, _windowAge)) continue;
        inWindow++;
        if (!game.gameStatus.isFinished) continue;
        final pgn = row.pgn;
        final hasEval = pgn?.contains('[%eval') ?? false;
        final decisiveResult =
            game.gameStatus == GameStatus.whiteWins ||
            game.gameStatus == GameStatus.blackWins;
        if (!hasEval && !decisiveResult) continue;
        final candidate = _FeedCandidate(
          game: game,
          source: hasEval ? FeedSource.annotated : FeedSource.decisive,
          pgn: row.isPgnDeferred ? null : pgn,
          loadPgn: () => ref.read(gameRepositoryProvider).getGamePgn(row.id),
        );
        (_isRecent(game, _freshAge) ? fresh : older).add(candidate);
      }
      for (final group in [fresh, older]) {
        _byStrength(group);
        for (final source in [
          FeedSource.annotated,
          FeedSource.decisive,
        ]) {
          _enqueue(source, [
            for (final candidate in group)
              if (candidate.source == source) candidate,
          ]);
        }
      }

      // Rows arrive newest first, so a page with nothing inside the window
      // means the window is behind us. Elo filtering can empty a page on its
      // own, so a few empty pages are tolerated before giving up.
      if (games.isNotEmpty && inWindow == 0) {
        _topExhausted = true;
      } else if (games.isEmpty) {
        _topEmptyPages++;
        if (_topEmptyPages >= 3) _topExhausted = true;
      } else {
        _topEmptyPages = 0;
      }
    } catch (error) {
      debugPrint('[Feed] top games failed: $error');
      _publicSourceFailures++;
      _lastFailure = error;
      _topEmptyPages++;
      if (_topEmptyPages >= 3) _topExhausted = true;
    }
  }

  Future<void> _fetchFavorites(int generation) async {
    if (_favoritesExhausted) return;
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
      final candidates = <_FeedCandidate>[];
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
        candidates.add(
          _FeedCandidate(
            game: game,
            source: FeedSource.favorite,
            pgn: row.isPgnDeferred ? null : row.pgn,
            loadPgn: () => ref.read(gameRepositoryProvider).getGamePgn(row.id),
            hint: formatPlayerDisplayName(player.name),
          ),
        );
      }
      if (games.isNotEmpty && inWindow == 0) _favoritesExhausted = true;
      _enqueue(FeedSource.favorite, candidates);
    } catch (error) {
      debugPrint('[Feed] favorites failed: $error');
      _favoritesExhausted = true;
    }
  }

  Future<void> _fetchMiniatures(int generation) async {
    if (_miniaturesExhausted) return;
    final repository = ref.read(gamebaseRepositoryProvider);
    try {
      var window = _miniatureWindow;
      var offset = _miniatureOffset;
      var page = await repository.getMiniatures(
        filter: MiniatureGamesFilter(
          window: window,
          sort: MiniatureGamesSort.rating,
          order: MiniatureGamesSortOrder.desc,
        ),
        limit: _miniatureLimit,
        offset: offset,
      );
      if (generation != _generation) return;
      // A quiet day: widen to the week once.
      if (page.items.isEmpty && window == MiniatureGamesWindow.today) {
        window = MiniatureGamesWindow.week;
        offset = 0;
        page = await repository.getMiniatures(
          filter: MiniatureGamesFilter(
            window: window,
            sort: MiniatureGamesSort.rating,
            order: MiniatureGamesSortOrder.desc,
          ),
          limit: _miniatureLimit,
          offset: offset,
        );
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

      _enqueue(FeedSource.miniature, [
        for (final miniature in page.items)
          _FeedCandidate(
            game: miniature.toGamesTourModel(),
            source: FeedSource.miniature,
            loadPgn: () async {
              final game = await repository.getGameWithPgn(miniature.gameId);
              return game?.pgn;
            },
            hint: window.name,
          ),
      ]);
    } catch (error) {
      debugPrint('[Feed] miniatures failed: $error');
      _publicSourceFailures++;
      _lastFailure = error;
      _miniaturesExhausted = true;
    }
  }

  // ---------------------------------------------------------------------------
  // Queues → items
  // ---------------------------------------------------------------------------

  void _enqueue(FeedSource source, List<_FeedCandidate> candidates) {
    final queue = _queues[source]!;
    final queued = {for (final candidate in queue) candidate.game.gameId};
    for (final candidate in candidates) {
      final id = candidate.game.gameId;
      if (_seen.contains(id) || !queued.add(id)) continue;
      queue.add(candidate);
    }
  }

  int get _queuedCount =>
      _queues.values.fold(0, (sum, queue) => sum + queue.length);

  /// Next candidate on the [_schedule], skipping empty queues. With
  /// [inlineOnly], only candidates whose PGN is already in hand qualify.
  _FeedCandidate? _takeNext({required bool inlineOnly}) {
    for (var step = 0; step < _schedule.length; step++) {
      final slot = (_slot + step) % _schedule.length;
      final queue = _queues[_schedule[slot]]!;
      final index = inlineOnly
          ? queue.indexWhere((candidate) => candidate.hasInlinePgn)
          : (queue.isEmpty ? -1 : 0);
      if (index < 0) continue;
      _slot = (slot + 1) % _schedule.length;
      return queue.removeAt(index);
    }
    return null;
  }

  /// Turns up to [count] queued candidates into ready [FeedItem]s: fetches
  /// the PGNs they still need in parallel, then parses every game in one
  /// background isolate.
  Future<List<FeedItem>> _materialize(
    int count, {
    bool inlineOnly = false,
  }) async {
    final picked = <_FeedCandidate>[];
    while (picked.length < count) {
      final next = _takeNext(inlineOnly: inlineOnly);
      if (next == null) break;
      if (_seen.contains(next.game.gameId)) continue;
      picked.add(next);
    }
    if (picked.isEmpty) return const [];

    final pgns = await Future.wait(picked.map(_pgnFor));
    final ready = <(_FeedCandidate, String)>[
      for (var i = 0; i < picked.length; i++)
        if (pgns[i] != null) (picked[i], pgns[i]!),
    ];
    if (ready.isEmpty) return const [];

    final clips = await compute(_parseFlowClips, [
      for (final (_, pgn) in ready) pgn,
    ]);

    final now = DateTime.now();
    final items = <FeedItem>[];
    for (var i = 0; i < ready.length; i++) {
      final (candidate, pgn) = ready[i];
      final item = _toItem(candidate, clips[i], pgn, now);
      if (item == null || !_seen.add(item.game.gameId)) continue;
      items.add(item);
    }
    return items;
  }

  Future<String?> _pgnFor(_FeedCandidate candidate) async {
    if (candidate.hasInlinePgn) return candidate.pgn;
    final load = candidate.loadPgn;
    if (load == null) return null;
    try {
      final pgn = await load().timeout(_pgnTimeout);
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
      // Miniature listings carry a header-only PGN; hand the board the moves.
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

  /// The header mark a source earns on its own: the followed player for a
  /// favorite, "Miniature" for a miniature. Top boards earn none.
  static FeedSignal? _signalFor(_FeedCandidate candidate) {
    switch (candidate.source) {
      case FeedSource.favorite:
        final name = candidate.hint?.trim() ?? '';
        return name.isEmpty
            ? null
            : FeedSignal(FeedSignalKind.favorite, name: name);
      case FeedSource.miniature:
        return const FeedSignal(FeedSignalKind.miniature);
      case FeedSource.annotated:
      case FeedSource.decisive:
        return null;
    }
  }

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
    for (final queue in _queues.values) {
      queue.clear();
    }
    _slot = 0;
    _loadingMore = false;
    _refilling = null;
    _topOffset = 0;
    _topEmptyPages = 0;
    _topExhausted = false;
    _favoriteOffset = 0;
    _favoritesExhausted = false;
    _miniatureOffset = 0;
    _miniatureWindow = MiniatureGamesWindow.today;
    _miniaturesExhausted = false;
    _publicSourceFailures = 0;
    _lastFailure = null;
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

  String? get _userId {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  Future<List<FeedItem>> _readCache() async {
    try {
      final entry = await AppDatabase.instance.getCache(
        key: _cacheKey,
        userId: _userId,
        maxAge: _cacheMaxAge,
      );
      if (entry == null) return const [];
      return decodeFlowFeedCache(entry.value, now: DateTime.now());
    } catch (error) {
      debugPrint('[Feed] cache read failed: $error');
      return const [];
    }
  }

  Future<void> _writeCache(List<FeedItem> items) async {
    try {
      await AppDatabase.instance.setCache(
        key: _cacheKey,
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

void _byStrength(List<_FeedCandidate> candidates) {
  candidates.sort((a, b) {
    final byElo = b.game.cardElo.compareTo(a.game.cardElo);
    if (byElo != 0) return byElo;
    return (a.game.boardNr ?? 999).compareTo(b.game.boardNr ?? 999);
  });
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
