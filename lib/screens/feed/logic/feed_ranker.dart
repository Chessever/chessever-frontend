import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Where a Feed candidate came from. Several pools can offer the same game;
/// the Feed keeps the one that says the most about it (see [FeedNotifier]).
enum FeedPool {
  /// A game from an event running now (`group_broadcasts_current`).
  current,

  /// A strong, recent game from anywhere.
  top,

  /// A player the viewer follows is at the board.
  favorite,

  /// One of today's most liked games.
  liked,

  /// A Gamebase miniature.
  miniature,
}

/// What the ranker knows about one game before its moves are downloaded:
/// all of it comes from the listing row.
@immutable
class FeedSignals {
  const FeedSignals({
    required this.id,
    required this.pool,
    required this.whiteElo,
    required this.blackElo,
    required this.result,
    required this.age,
    this.likes = 0,
    this.eventElo = 0,
    this.eventKey,
    this.playerKeys = const {},
    this.seenBefore = false,
  });

  final String id;
  final FeedPool pool;
  final int whiteElo;
  final int blackElo;

  /// `1-0`, `0-1` or a draw (`1/2-1/2` / `½-½`).
  final String result;

  /// Time since the game finished.
  final Duration age;

  /// Distinct users who liked it today.
  final int likes;

  /// The strongest section average of its event, for [FeedPool.current].
  final int eventElo;

  /// The tour, so two games of one round are not served back to back.
  final String? eventKey;

  /// Player identities (FIDE ids, else names) for the same reason.
  final Set<String> playerKeys;

  /// Shown to this viewer in an earlier session or before a refresh.
  final bool seenBefore;

  bool get decisive => result == '1-0' || result == '0-1';

  FeedSignals withSeenBefore(bool value) => value == seenBefore
      ? this
      : FeedSignals(
          id: id,
          pool: pool,
          whiteElo: whiteElo,
          blackElo: blackElo,
          result: result,
          age: age,
          likes: likes,
          eventElo: eventElo,
          eventKey: eventKey,
          playerKeys: playerKeys,
          seenBefore: value,
        );

  int get averageElo {
    final rated = [whiteElo, blackElo].where((e) => e > 0).toList();
    if (rated.isEmpty) return 0;
    return rated.reduce((a, b) => a + b) ~/ rated.length;
  }

  /// Winner's rating minus loser's; negative is an upset. 0 for a draw or
  /// when either rating is missing.
  int get winnerMargin {
    if (!decisive || whiteElo <= 0 || blackElo <= 0) return 0;
    return result == '1-0' ? whiteElo - blackElo : blackElo - whiteElo;
  }
}

/// How interesting a game is on its own, before variety is considered.
/// Roughly 0 (a quiet club draw from last week) to 7 (today's 2750 upset by
/// a player the viewer follows).
///
/// The weights encode the product call: decisive high-Elo games are the
/// core; upsets, the viewer's own players and what the community liked are
/// the surprises that keep a thumb moving; freshness breaks ties.
double feedInterest(FeedSignals s) {
  var score = ((s.averageElo - 2200) / 300).clamp(0.0, 2.2);
  score += s.decisive ? 1.2 : 0.1;

  final margin = s.winnerMargin;
  if (margin <= -80) score += 0.4 + math.min(0.8, -margin / 250);

  switch (s.pool) {
    case FeedPool.favorite:
      score += 1.6;
    case FeedPool.liked:
      score += 0.5 + 0.35 * math.log(1 + s.likes) / math.ln2;
    case FeedPool.miniature:
      score += 1.0;
    case FeedPool.current:
      score += s.eventElo >= 2600 ? 0.8 : 0.4;
    case FeedPool.top:
      break;
  }

  final hours = s.age.inMinutes / 60;
  score += 0.9 * math.exp(-hours.clamp(0, 24 * 30) / 30);

  if (s.seenBefore) score -= 2.5;
  return score;
}

/// Picks the Feed's next game from a pool of candidates, one at a time.
///
/// Not a sort. A sorted feed shows the same five games to everyone, in the
/// same order, every launch; this is a weighted draw, so every session is
/// its own:
///
/// * **Softmax draw.** Each candidate's chance is `exp(interest / T)`: the
///   best games come up most, but anything decent can.
/// * **Variety.** The draw is damped for a candidate that repeats the pool,
///   event, players or drawn result of the last few picks, so the feed never
///   runs one kind of game for long; three games in a row from one event
///   never happen while anything else is left.
/// * **Jackpots.** Every 3 to 5 picks (the gap itself is random) the draw is
///   skipped and the single best remaining game is served: a variable-ratio
///   reward, the rhythm that makes one more swipe feel worth it. The very
///   first pick is always one.
/// * **Exploration.** One pick in ten is uniform over the pool, so a
///   low-ranked miniature or an unknown player's brilliancy still surfaces.
///
/// Seeded, so one session's order is stable and a test can replay it; a new
/// session (or a pull-to-refresh) brings a new seed.
class FeedRanker {
  FeedRanker(int seed) : _random = math.Random(seed) {
    _jackpotIn = 0; // the first pick is the hook
  }

  final math.Random _random;

  /// The most recent picks, newest last.
  final List<FeedSignals> _history = [];
  late int _jackpotIn;

  static const double temperature = 0.7;
  static const double explore = 0.1;
  static const int _historySize = 4;

  /// How much a candidate is held back for echoing the recent picks: 1 is
  /// not at all.
  @visibleForTesting
  double varietyFactor(FeedSignals s) {
    if (_history.isEmpty) return 1;
    var factor = 1.0;
    final last = _history.last;
    if (last.pool == s.pool) {
      factor *= 0.6;
      if (_history.length >= 2 &&
          _history[_history.length - 2].pool == s.pool) {
        factor *= 0.4;
      }
    }
    // One more game of an event just shown is fine, held back a little;
    // [next] never allows a third in a row.
    if (s.eventKey != null && s.eventKey == last.eventKey) factor *= 0.3;
    for (final h in _history) {
      if (h.playerKeys.any(s.playerKeys.contains)) {
        factor *= 0.25;
        break;
      }
    }
    if (!last.decisive && !s.decisive) factor *= 0.5;
    return factor;
  }

  /// Takes the next pick out of [pool] (and returns it), or null when no
  /// candidate passes [eligible].
  FeedSignals? next(
    List<FeedSignals> pool, {
    bool Function(FeedSignals)? eligible,
  }) {
    var options = [
      for (final s in pool)
        if (eligible == null || eligible(s)) s,
    ];
    if (options.isEmpty) return null;

    // Hard rule behind the soft penalties: never a third game in a row from
    // one event while anything else is left.
    if (_history.length >= 2) {
      final event = _history.last.eventKey;
      if (event != null && _history[_history.length - 2].eventKey == event) {
        final others = [
          for (final s in options)
            if (s.eventKey != event) s,
        ];
        if (others.isNotEmpty) options = others;
      }
    }

    final FeedSignals pick;
    if (_jackpotIn <= 0) {
      pick = _best(options);
      _jackpotIn = 3 + _random.nextInt(3);
    } else if (_random.nextDouble() < explore) {
      pick = options[_random.nextInt(options.length)];
      _jackpotIn--;
    } else {
      pick = _draw(options);
      _jackpotIn--;
    }

    pool.remove(pick);
    _history.add(pick);
    if (_history.length > _historySize) _history.removeAt(0);
    return pick;
  }

  FeedSignals _best(List<FeedSignals> options) {
    FeedSignals? best;
    var bestScore = double.negativeInfinity;
    for (final s in options) {
      final score = feedInterest(s) + math.log(varietyFactor(s));
      if (score > bestScore) {
        best = s;
        bestScore = score;
      }
    }
    return best!;
  }

  FeedSignals _draw(List<FeedSignals> options) {
    // Shifted by the top score so exp never overflows.
    final scores = [for (final s in options) feedInterest(s) / temperature];
    final top = scores.reduce(math.max);
    final weights = [
      for (var i = 0; i < options.length; i++)
        math.exp(scores[i] - top) * varietyFactor(options[i]),
    ];
    final total = weights.fold<double>(0, (a, b) => a + b);
    var roll = _random.nextDouble() * total;
    for (var i = 0; i < options.length; i++) {
      roll -= weights[i];
      if (roll <= 0) return options[i];
    }
    return options.last;
  }
}
