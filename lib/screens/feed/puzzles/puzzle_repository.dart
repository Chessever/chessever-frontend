import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/screens/feed/puzzles/feed_puzzle_model.dart';
import 'package:chessever2/screens/feed/puzzles/puzzle_service_client.dart';
import 'package:chessever2/screens/feed/puzzles/puzzle_store.dart';
import 'package:flutter/foundation.dart';

/// How a Feed puzzle ended for the viewer.
enum FeedPuzzleOutcome { solved, revealed }

/// Feed puzzles from ChessEver's puzzle service, served from the local cache
/// first so the Feed never waits on the network when it has puzzles on hand,
/// and topped up in the background.
///
/// Puzzles the viewer has not been shown lead; shown but unfinished ones
/// rotate to the back and give way as fresh ones arrive. Anything the viewer
/// finished (solved, or had the answer shown) is left out of the next load.
/// Fresh puzzles are asked for around the viewer's [FeedPuzzleRating], which
/// every finished puzzle moves.
///
/// With no service configured it serves nothing and sends nothing.
class FeedPuzzleRepository {
  FeedPuzzleRepository({
    required this._client,
    required this._store,
    DateTime Function()? clock,
    math.Random? random,
    this._band,
  }) : _clock = clock ?? DateTime.now,
       _random = random ?? math.Random();

  /// Puzzles per load.
  static const int freshCount = 5;

  /// Fetched puzzles kept on hand: two loads' worth, so the launch after a
  /// refill still has [freshCount] the viewer has not been shown.
  static const int poolTarget = 10;

  /// Puzzles asked for per request. More than [poolTarget], so puzzles the
  /// viewer already has or finished can be skipped without a second request;
  /// fixed, so every viewer in a rating window shares the service's cache.
  static const int fetchLimit = 20;

  /// The service's `seed` range, for a page of our own when its rotating
  /// default page had nothing new.
  static const int seedRange = 10000;

  /// A cached puzzle is replaced after at most this long.
  static const Duration poolMaxAge = Duration(days: 2);

  /// Each puzzle ages out up to this much before [poolMaxAge] (a fixed share
  /// per id), so a batch fetched together does not expire all at once.
  static const Duration poolAgeSpread = Duration(hours: 12);

  final PuzzleServiceClient _client;
  final FeedPuzzleStore _store;
  final DateTime Function() _clock;
  final math.Random _random;

  /// The difficulty the viewer picked (the puzzle rating range shared with
  /// Puzzle Race). When set, fresh puzzles are asked for inside it and
  /// rated puzzles outside it are not served; the adaptive
  /// [FeedPuzzleRating] is still kept, but no longer steers requests.
  final ({int min, int max}) Function()? _band;

  Future<Set<String>>? _doneLoad;
  final Map<String, FeedPuzzleOutcome> _outcomes = {};
  Future<List<CachedPuzzle>>? _refill;
  Future<void> _poolTail = Future<void>.value();

  FeedPuzzleRating? _rating;
  Future<void> _ratingTail = Future<void>.value();

  /// What this repository served, in order, so a reload in the same app
  /// session (resume, a late top-up) keeps those puzzles where they were.
  final List<CachedPuzzle> _sessionServed = [];
  final Set<String> _sessionServedIds = {};

  /// Bumps each time a refill caches puzzles that were not on hand before.
  int _poolAdds = 0;

  /// What the last [load] left running; see [backgroundUpdate].
  Future<bool>? _background;

  static bool _loggedUnconfigured = false;

  /// False when no puzzle service URL is configured: [load] is then always
  /// empty and there is nothing worth retrying.
  bool get isConfigured => _client.isConfigured;

  /// When the service's 429 back-off ends; null when requests may go out.
  DateTime? get blockedUntil => _client.blockedUntil;

  /// Settles once the top-up the last [load] left running in the background
  /// (for a load that came up short) has finished: true when it cached
  /// puzzles that a new [load] would serve. False at once when that load
  /// left nothing running. A top-up for a later launch, after a full load,
  /// is not reported. Never throws.
  Future<bool> get backgroundUpdate => _background ?? Future<bool>.value(false);

  /// How [id] ended in this app session, so a page rebuilt after scrolling
  /// away shows it finished instead of fresh.
  FeedPuzzleOutcome? outcomeOf(String id) => _outcomes[id];

  /// The rating the next top-up asks around, once earlier finishes have
  /// been counted.
  Future<FeedPuzzleRating> get rating async {
    await _ratingTail;
    return _readRating();
  }

  /// Records that the viewer finished [id]; it will not be served again. The
  /// first finish of a puzzle also moves the viewer's rating: [assisted] is
  /// a solve that needed a wrong try or a hint. [rating] is the puzzle's.
  Future<void> markFinished(
    String id,
    FeedPuzzleOutcome outcome, {
    int? rating,
    bool assisted = false,
  }) async {
    if (_outcomes[id] != FeedPuzzleOutcome.solved) _outcomes[id] = outcome;
    final done = await _doneIds();
    if (!done.add(id)) return;
    final score = switch (outcome) {
      FeedPuzzleOutcome.solved => assisted ? 0.5 : 1.0,
      FeedPuzzleOutcome.revealed => 0.0,
    };
    final rated = _recordRating(rating ?? _servedRating(id), score);
    try {
      await _store.addDone(id);
    } catch (error) {
      debugPrint('[FeedPuzzles] could not persist $id: $error');
    }
    await rated;
  }

  /// Up to [freshCount] puzzles: what this session already served first,
  /// then puzzles the viewer has not been shown, then shown ones, longest
  /// ago first. Never throws: with no cache and no network (or no service
  /// configured) it returns an empty list and the Feed simply shows no
  /// puzzles.
  Future<List<FeedPuzzle>> load() async {
    _background = null;
    if (!isConfigured) {
      if (!_loggedUnconfigured) {
        _loggedUnconfigured = true;
        debugPrint('[FeedPuzzles] RACE_API_URL is not set; no Feed puzzles.');
      }
      return const [];
    }
    final now = _clock();
    final poolAdds = _poolAdds;
    final done = await _doneIds();

    final kept = [
      for (final c in _sessionServed)
        if (!done.contains(c.puzzle.id)) c,
    ];
    final keptIds = {for (final c in kept) c.puzzle.id};
    final others = [
      for (final c in _live(await _readPool(), now, done))
        if (!keptIds.contains(c.puzzle.id)) c,
    ];
    var pool = [...kept, ..._ordered(others)];

    // Nothing on hand: wait for the service.
    final coldRefill = pool.isEmpty ? _refillPool() : null;
    if (coldRefill != null) pool = await coldRefill;

    final (puzzles, served) = _compose(pool, done);
    final firstServed = [
      for (final c in served)
        if (!_sessionServedIds.contains(c.puzzle.id)) c.servedOn(now),
    ];
    if (firstServed.isNotEmpty) {
      _sessionServed.addAll(firstServed);
      _sessionServedIds.addAll(firstServed.map((c) => c.puzzle.id));
      unawaited(_recordServed(firstServed, now));
    }

    // Top up once fewer than a load's worth of unseen puzzles remain (not
    // straight after a cold refill: that just asked).
    final servedIds = {for (final c in served) c.puzzle.id};
    final unseenLeft = pool
        .where(
          (c) =>
              c.servedAt == null &&
              !servedIds.contains(c.puzzle.id) &&
              !done.contains(c.puzzle.id) &&
              _servable(c.puzzle),
        )
        .length;
    if (coldRefill == null && unseenLeft < freshCount) {
      final refill = _refillPool();
      if (served.length < freshCount) {
        // This load came up short, so the top-up is news for the Feed.
        // Counted from before this load read the pool, so a top-up that
        // lands in between is not missed.
        _background = refill.then(
          (_) => _poolAdds != poolAdds,
          onError: (Object _) => false,
        );
      } else {
        refill.ignore(); // for the next launch
      }
    }
    return puzzles;
  }

  /// The Puzzle tab's next page: up to [freshCount] puzzles that are not in
  /// [have] and not finished, from the pool first and, when it runs short,
  /// one request to the service. Served puzzles are stamped like [load]'s.
  /// Never throws; an empty list means nothing more right now.
  Future<List<FeedPuzzle>> loadMore(Set<String> have) async {
    if (!isConfigured) return const [];
    try {
      final now = _clock();
      final done = await _doneIds();
      bool usable(FeedPuzzle p) =>
          !have.contains(p.id) && !done.contains(p.id) && _servable(p);
      final picks = [
        for (final c in _ordered(_live(await _readPool(), now, done)))
          if (usable(c.puzzle)) c,
      ];
      if (picks.length < freshCount) {
        final ids = {for (final c in picks) c.puzzle.id};
        for (final p in await _fetchFresh({...have, ...done})) {
          if (usable(p) && ids.add(p.id)) picks.add(CachedPuzzle(p, now));
        }
      }
      final served = [
        for (final c in picks.take(freshCount)) c.servedOn(now),
      ];
      for (final c in served) {
        if (_sessionServedIds.add(c.puzzle.id)) _sessionServed.add(c);
      }
      if (served.isNotEmpty) unawaited(_recordServed(served, now));
      return [for (final c in served) c.puzzle];
    } catch (error) {
      debugPrint('[FeedPuzzles] loadMore failed: $error');
      return const [];
    }
  }

  /// Drops cached puzzles rated outside [min]..[max] (a new difficulty), so
  /// the next load tops up inside it. Unrated puzzles stay.
  Future<void> retainWithin(int min, int max) async {
    try {
      await _locked(() async {
        final pool = await _store.readPool();
        final kept = [
          for (final c in pool)
            if (_inBand(c.puzzle, min, max)) c,
        ];
        if (kept.length != pool.length) await _store.writePool(kept);
      });
    } catch (error) {
      debugPrint('[FeedPuzzles] could not apply difficulty: $error');
    }
  }

  /// Inside the viewer's difficulty, when one is set.
  bool _servable(FeedPuzzle puzzle) {
    final band = _band?.call();
    return band == null || _inBand(puzzle, band.min, band.max);
  }

  static bool _inBand(FeedPuzzle puzzle, int min, int max) {
    final rating = puzzle.rating;
    return rating == null || (rating >= min && rating <= max);
  }

  /// Waits for background fetches and cache writes to settle (tests).
  @visibleForTesting
  Future<void> settle() async {
    await _refill;
    await _poolTail;
    await _ratingTail;
  }

  // ---------------------------------------------------------------- rating

  Future<FeedPuzzleRating> _readRating() async {
    final known = _rating;
    if (known != null) return known;
    FeedPuzzleRating? stored;
    try {
      stored = await _store.readRating();
    } catch (error) {
      debugPrint('[FeedPuzzles] rating unreadable: $error');
    }
    // An update that landed while the read was in flight wins.
    return _rating ??= stored ?? FeedPuzzleRating.initial;
  }

  /// Folds one finish into the rating, one finish at a time, so two quick
  /// finishes both count.
  Future<void> _recordRating(int? puzzleRating, double score) {
    final update = _ratingTail.then((_) async {
      final next = (await _readRating()).after(
        puzzleRating: puzzleRating,
        score: score,
      );
      _rating = next;
      try {
        await _store.writeRating(next);
      } catch (error) {
        debugPrint('[FeedPuzzles] could not save rating: $error');
      }
    });
    _ratingTail = update.then<void>((_) {}, onError: (Object _) {});
    return _ratingTail;
  }

  int? _servedRating(String id) {
    for (final c in _sessionServed) {
      if (c.puzzle.id == id) return c.puzzle.rating;
    }
    return null;
  }

  // ----------------------------------------------------------------- pool

  /// Runs [task] after every earlier pool read-modify-write has settled, so
  /// served stamps and refills never overwrite each other.
  Future<T> _locked<T>(Future<T> Function() task) {
    final result = _poolTail.then((_) => task());
    _poolTail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<List<CachedPuzzle>> _readPool() async {
    try {
      return await _locked(_store.readPool);
    } catch (error) {
      debugPrint('[FeedPuzzles] pool unreadable: $error');
      return const [];
    }
  }

  /// Stamps [served] as shown at [at], which moves them behind the unseen
  /// ones, so the next launch leads with puzzles the viewer has not seen.
  Future<void> _recordServed(List<CachedPuzzle> served, DateTime at) async {
    try {
      await _locked(() async {
        final done = await _doneIds();
        final byId = {for (final c in await _store.readPool()) c.puzzle.id: c};
        // Re-inserted in serve order, which the stable sort keeps among
        // puzzles stamped together.
        for (final c in served) {
          byId[c.puzzle.id] = (byId.remove(c.puzzle.id) ?? c).servedOn(at);
        }
        final kept = _ordered(
          _live(byId.values, at, done),
        ).take(poolTarget).toList();
        await _store.writePool(kept);
      });
    } catch (error) {
      debugPrint('[FeedPuzzles] could not record served puzzles: $error');
    }
  }

  Future<List<CachedPuzzle>> _refillPool() {
    final running = _refill;
    if (running != null) return running;
    final fetch = _doRefill();
    _refill = fetch;
    fetch.whenComplete(() {
      if (identical(_refill, fetch)) _refill = null;
    }).ignore();
    return fetch;
  }

  Future<List<CachedPuzzle>> _doRefill() async {
    var live = const <CachedPuzzle>[];
    try {
      final done = await _doneIds();
      live = _ordered(_live(await _readPool(), _clock(), done));
      final unseen = live
          .where((c) => c.servedAt == null && _servable(c.puzzle))
          .length;
      if (unseen >= freshCount) return live;

      final fetched = await _fetchFresh({
        ...done,
        for (final c in live) c.puzzle.id,
      });
      if (fetched.isEmpty) return live;

      return await _locked(() async {
        final at = _clock();
        // Read again: served stamps may have landed while the service
        // answered.
        final current = _live(await _store.readPool(), at, done);
        final ids = {for (final c in current) c.puzzle.id};
        // Unseen first, so the trim drops shown puzzles before fresh ones.
        final added = <String>{};
        final kept = _ordered([
          ...current,
          for (final p in fetched)
            if (!done.contains(p.id) && ids.add(p.id) && added.add(p.id))
              CachedPuzzle(p, at),
        ]).take(poolTarget).toList();
        await _store.writePool(kept);
        if (kept.any((c) => added.contains(c.puzzle.id))) _poolAdds++;
        return kept;
      });
    } catch (error) {
      debugPrint('[FeedPuzzles] refill failed: $error');
      return live;
    }
  }

  /// One request around the viewer's rating. The service's default page
  /// rotates every few minutes and is shared by everyone in the window, so
  /// when it holds nothing the viewer lacks, one more request asks for a
  /// page of our own.
  Future<List<FeedPuzzle>> _fetchFresh(Set<String> have) async {
    final band = _band?.call() ?? (await rating).band;
    Future<List<FeedPuzzle>> ask([int? seed]) => _client.feed(
      minRating: band.min,
      maxRating: band.max,
      limit: fetchLimit,
      seed: seed,
    );
    try {
      final page = await ask();
      if (page.isEmpty || page.any((p) => !have.contains(p.id))) return page;
      return await ask(_random.nextInt(seedRange));
    } on PuzzleServiceRateLimitedException catch (error) {
      debugPrint('[FeedPuzzles] backing off until ${error.until}');
    } catch (error) {
      debugPrint('[FeedPuzzles] fetch failed: $error');
    }
    return const [];
  }

  // -------------------------------------------------------------- helpers

  /// The finished ids, read once and then kept up to date in memory.
  Future<Set<String>> _doneIds() => _doneLoad ??= () async {
    try {
      return await _store.readDone();
    } catch (error) {
      debugPrint('[FeedPuzzles] finished ids unreadable: $error');
      return <String>{};
    }
  }();

  bool _isLive(CachedPuzzle c, DateTime now, Set<String> done) =>
      !done.contains(c.puzzle.id) &&
      now.difference(c.fetchedAt) < maxAgeOf(c.puzzle.id);

  /// How long [id] stays in the pool: [poolMaxAge] less a share of
  /// [poolAgeSpread] fixed by the id, so puzzles fetched together age out
  /// one by one instead of emptying the pool in the same instant.
  @visibleForTesting
  static Duration maxAgeOf(String id) {
    var hash = 0;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x3fffffff;
    }
    // Golden-ratio steps spread even near-identical ids evenly over [0, 1).
    final share = (hash * 0.6180339887498949) % 1.0;
    return poolMaxAge - poolAgeSpread * share;
  }

  List<CachedPuzzle> _live(
    Iterable<CachedPuzzle> pool,
    DateTime now,
    Set<String> done,
  ) {
    final seen = <String>{};
    return [
      for (final c in pool)
        if (_isLive(c, now, done) && seen.add(c.puzzle.id)) c,
    ];
  }

  /// Unseen puzzles first, in the order they were fetched; then shown ones,
  /// the longest-ago shown first.
  static List<CachedPuzzle> _ordered(Iterable<CachedPuzzle> pool) {
    final unseen = <CachedPuzzle>[];
    final shown = <CachedPuzzle>[];
    for (final c in pool) {
      (c.servedAt == null ? unseen : shown).add(c);
    }
    mergeSort(shown, compare: (a, b) => a.servedAt!.compareTo(b.servedAt!));
    return [...unseen, ...shown];
  }

  /// Up to [freshCount] pool puzzles in order, with the pool entries served.
  (List<FeedPuzzle>, List<CachedPuzzle>) _compose(
    List<CachedPuzzle> pool,
    Set<String> done,
  ) {
    final out = <FeedPuzzle>[];
    final served = <CachedPuzzle>[];
    final band = _band?.call();
    for (final c in pool) {
      if (served.length >= freshCount) break;
      if (done.contains(c.puzzle.id)) continue;
      if (band != null && !_inBand(c.puzzle, band.min, band.max)) continue;
      out.add(c.puzzle);
      served.add(c);
    }
    return (out, served);
  }
}
