import 'dart:convert';
import 'dart:math' as math;

import 'package:chessever2/screens/feed/logic/feed_ranker.dart';
import 'package:flutter/foundation.dart';

/// What the viewer did with a post, beyond looking at it.
enum FeedAction {
  like,
  save,
  share,
  analyze,
  mySpace,

  /// Played their own moves or scrubbed through the game.
  explore,

  /// Opened the event.
  event,
}

/// One visit to a post, as the Feed saw it: how long it stayed on screen,
/// how much of the game played, and what the viewer did.
@immutable
class FeedVisit {
  const FeedVisit({
    required this.dwell,
    this.progress = 0,
    this.actions = const {},
  });

  final Duration dwell;

  /// Share of the clip's moves that played (0..1).
  final double progress;
  final Set<FeedAction> actions;

  /// How much the visit says the viewer enjoyed the game, 0..1: the reward
  /// the taste model learns from.
  ///
  /// The scale follows what short-video feeds learn from: a swipe away in
  /// the first second is the clearest "not for me", watching through is a
  /// quiet yes, and an action (like, save, share, opening the game) is a
  /// loud one. A long stay without playing on counts too: a reader studying
  /// the position is not bored.
  double get reward {
    var r = 0.0;
    for (final action in actions) {
      r += switch (action) {
        FeedAction.like || FeedAction.save || FeedAction.share => 0.7,
        FeedAction.analyze || FeedAction.mySpace => 0.55,
        FeedAction.explore => 0.35,
        FeedAction.event => 0.25,
      };
    }
    final seconds = dwell.inMilliseconds / 1000;
    if (seconds < 1.2 && r == 0) return 0;
    r += 0.55 * progress.clamp(0.0, 1.0);
    r += 0.3 * (seconds / 20).clamp(0.0, 1.0);
    return r.clamp(0.0, 1.0);
  }
}

/// The families a game's features fall in, and how much each one moves the
/// taste score.
enum _Family {
  player('p', 1.0),
  country('c', 0.6),
  event('e', 0.6),
  kind('k', 1.6),
  venue('v', 1.0),
  time('t', 0.6),
  story('s', 0.7),
  opening('o', 0.4),
  band('b', 0.5),
  result('r', 0.4);

  const _Family(this.prefix, this.weight);
  final String prefix;
  final double weight;

  static _Family of(String feature) {
    final prefix = feature.substring(0, feature.indexOf(':'));
    return values.firstWhere((f) => f.prefix == prefix);
  }
}

/// The features a game is known by: its players and their countries, its
/// event, Freestyle or not, online or over the board, time control, the
/// report's story, opening family, strength band and result.
List<String> feedFeatures(FeedSignals s) {
  final elo = s.averageElo;
  return [
    for (final p in s.playerKeys) 'p:$p',
    for (final c in s.countries) 'c:${c.toUpperCase()}',
    if (s.eventKey != null) 'e:${s.eventKey}',
    // Standard chess over the board is the baseline, not a taste: only
    // what sets a game apart is a feature (and can tire).
    if (s.freestyle) 'k:freestyle',
    if (s.online) 'v:online',
    if (s.timeClass != null) 't:${s.timeClass}',
    if (s.reportType != null) 's:${s.reportType!.name}',
    if ((s.openingKey?.length ?? 0) >= 2)
      'o:${s.openingKey!.substring(0, 2).toUpperCase()}',
    'b:${elo >= 2700
        ? 2700
        : elo >= 2600
        ? 2600
        : elo >= 2500
        ? 2500
        : 2400}',
    s.decisive ? 'r:decisive' : 'r:draw',
  ];
}

/// A starting belief about one feature: the share of visits expected to be
/// enjoyed, and how many visits' worth of evidence the belief is worth.
@immutable
class FeedPrior {
  const FeedPrior(this.mean, this.strength);
  final double mean;
  final double strength;

  /// An unknown feature: even odds, held firmly enough that sampling it
  /// explores without drowning what the feed knows about the game.
  static const neutral = FeedPrior(0.5, 12);
}

/// What the Feed has learned about one viewer's taste, and how tired they
/// are of what they just saw.
///
/// **Taste** is a bandit over game features. Each feature (a player, a
/// country, Freestyle, a report story...) keeps a Beta belief of how often
/// the viewer enjoys a game that has it, updated by every visit's
/// [FeedVisit.reward]. Ranking samples from those beliefs (Thompson
/// sampling): a feature the viewer has barely met is uncertain, so it is
/// sometimes sampled high and gets shown; the feed keeps probing for new
/// interests the way short-video feeds do, and settles on what holds the
/// viewer without anyone writing down what that is.
///
/// Beliefs start from what the app already knows ([priors]): followed
/// players and the viewer's country start liked, Freestyle and online
/// blitz start as a minority taste. Every one of those is a starting point
/// the viewer's own behaviour overrides.
///
/// Evidence fades ([_memory] per visit, and by age between sessions), so
/// taste can drift.
class FeedTaste {
  FeedTaste({Map<String, FeedPrior>? priors})
    : priors = {..._productPriors, ...?priors};

  /// The product's own starting beliefs, before the viewer has said a
  /// thing. Mild: a few visits outweigh them.
  static const Map<String, FeedPrior> _productPriors = {
    'k:freestyle': FeedPrior(0.3, 10),
    'v:online': FeedPrior(0.42, 6),
    'r:draw': FeedPrior(0.42, 3),
  };

  /// Starting beliefs: the product's own, then what the app knows.
  final Map<String, FeedPrior> priors;

  /// Evidence per feature: enjoyed and not enjoyed, in visits.
  final Map<String, (double, double)> _evidence = {};

  /// Evidence one visit is worth: two, so a few swipes visibly steer the
  /// feed within a session.
  static const double _weight = 2;

  /// Each visit keeps this share of all older evidence.
  static const double _memory = 0.997;

  /// Evidence older than this between sessions counts half.
  static const Duration halfLife = Duration(days: 21);

  int _visits = 0;
  int get visits => _visits;

  /// The followed players and the viewer's country, from what the app
  /// knows: liked from the start.
  void seed({Iterable<String> players = const [], String? country}) {
    for (final p in players) {
      priors['p:$p'] = const FeedPrior(0.8, 6);
    }
    if (country != null && country.trim().isNotEmpty) {
      priors['c:${country.trim().toUpperCase()}'] = const FeedPrior(0.68, 5);
    }
  }

  FeedPrior _prior(String feature) => priors[feature] ?? FeedPrior.neutral;

  (double, double) _belief(String feature) {
    final prior = _prior(feature);
    final (yes, no) = _evidence[feature] ?? (0.0, 0.0);
    return (
      prior.mean * prior.strength + yes,
      (1 - prior.mean) * prior.strength + no,
    );
  }

  /// The expected share of visits the viewer enjoys among games with
  /// [feature].
  double affinity(String feature) {
    final (a, b) = _belief(feature);
    return a / (a + b);
  }

  /// How much the viewer's taste lifts or sinks [s]: the sum over its
  /// features of each one's log-odds against an even chance, weighted by
  /// family. With [draw], beliefs are sampled instead of averaged
  /// (Thompson sampling): the draw's samples, one per feature, shared by
  /// every candidate it scores.
  double score(FeedSignals s, {FeedTasteDraw? draw}) {
    var total = 0.0;
    for (final f in feedFeatures(s)) {
      final p = (draw?.sample(f) ?? affinity(f)).clamp(0.02, 0.98);
      total += _Family.of(f).weight * math.log(p / (1 - p));
    }
    return total;
  }

  /// Starts a draw: a fresh set of samples from the current beliefs.
  FeedTasteDraw draw(math.Random random) => FeedTasteDraw._(this, random);

  /// Learns from a visit to [s].
  void learn(FeedSignals s, FeedVisit visit) {
    final r = visit.reward;
    for (final entry in _evidence.entries.toList()) {
      final (yes, no) = entry.value;
      _evidence[entry.key] = (yes * _memory, no * _memory);
    }
    for (final f in feedFeatures(s)) {
      final (yes, no) = _evidence[f] ?? (0.0, 0.0);
      _evidence[f] = (yes + _weight * r, no + _weight * (1 - r));
    }
    _visits++;
    _prune();
  }

  /// Keeps the model small: the least evidenced features go first.
  void _prune({int max = 1500}) {
    if (_evidence.length <= max) return;
    final order = _evidence.entries.toList()
      ..sort(
        (a, b) => (a.value.$1 + a.value.$2).compareTo(b.value.$1 + b.value.$2),
      );
    for (final e in order.take(_evidence.length - max)) {
      _evidence.remove(e.key);
    }
  }

  String encode(DateTime now) => jsonEncode({
    'at': now.toIso8601String(),
    'visits': _visits,
    'e': {
      for (final e in _evidence.entries) e.key: [e.value.$1, e.value.$2],
    },
  });

  /// Restores what [encode] wrote, faded by its age.
  void restore(String raw, DateTime now) {
    final map = jsonDecode(raw) as Map<String, Object?>;
    final at = DateTime.tryParse(map['at'] as String? ?? '') ?? now;
    final age = now.difference(at).inMinutes / halfLife.inMinutes;
    final keep = math.pow(0.5, age.clamp(0, 50)).toDouble();
    _visits = (map['visits'] as num?)?.toInt() ?? 0;
    final evidence = map['e'] as Map<String, Object?>? ?? const {};
    for (final e in evidence.entries) {
      final pair = (e.value as List).cast<num>();
      if (pair.length != 2) continue;
      _evidence[e.key] = (pair[0] * keep, pair[1] * keep);
    }
  }
}

/// One set of Thompson samples from a [FeedTaste].
class FeedTasteDraw {
  FeedTasteDraw._(this._taste, this._random);

  final FeedTaste _taste;
  final math.Random _random;
  final Map<String, double> _samples = {};

  double sample(String feature) => _samples.putIfAbsent(feature, () {
    final (a, b) = _taste._belief(feature);
    final x = _gamma(a, _random);
    final y = _gamma(b, _random);
    return x / (x + y);
  });
}

/// Fatigue: how much of each feature the viewer has seen lately.
///
/// Every pick adds one to each of its features, and every pick after it
/// takes a share away ([recovery]), so the feed spaces a kind of game out
/// instead of counting it against a cap. Fatigue weighs less on what the
/// viewer loves: a game is held back by `fatigue × 2(1 − affinity)²`, so a
/// Freestyle fan sees Freestyle more often than someone who swipes it away,
/// and nobody sees one event all evening.
class FeedFatigue {
  FeedFatigue();

  FeedFatigue.copy(FeedFatigue other) {
    _level.addAll(other._level);
  }

  final Map<String, double> _level = {};

  /// Share of fatigue left after each pick: an event, a player or a kind
  /// of game is remembered for longer than a story or an opening.
  static double recovery(String feature) => switch (feature[0]) {
    'e' || 'p' || 'k' => 0.88,
    _ => 0.8,
  };

  /// How hard each family tires: one event, one player, one kind of game
  /// tire fast; a strength band or a result barely at all.
  static double _strength(String feature) => switch (feature[0]) {
    'e' => 5.0,
    'p' => 2.6,
    'k' => 6.0,
    'v' => 2.2,
    's' => 1.4,
    'o' => 0.8,
    'c' => 0.7,
    't' => 0.5,
    _ => 0.3,
  };

  void picked(FeedSignals s) {
    for (final key in _level.keys.toList()) {
      final next = _level[key]! * recovery(key);
      if (next < 0.01) {
        _level.remove(key);
      } else {
        _level[key] = next;
      }
    }
    for (final f in feedFeatures(s)) {
      _level[f] = (_level[f] ?? 0) + 1;
    }
  }

  /// How much [s] is held back, in interest points.
  double penalty(FeedSignals s, FeedTaste taste) {
    var total = 0.0;
    for (final f in feedFeatures(s)) {
      final level = _level[f];
      if (level == null) continue;
      final unloved = 1 - taste.affinity(f);
      total += _strength(f) * level * 2 * unloved * unloved;
    }
    return total;
  }
}

// Marsaglia–Tsang gamma sampler.
double _gamma(double shape, math.Random random) {
  if (shape < 1) {
    return _gamma(shape + 1, random) *
        math.pow(random.nextDouble(), 1 / shape).toDouble();
  }
  final d = shape - 1 / 3;
  final c = 1 / math.sqrt(9 * d);
  while (true) {
    double x, v;
    do {
      x = _normal(random);
      v = 1 + c * x;
    } while (v <= 0);
    v = v * v * v;
    final u = random.nextDouble();
    if (u < 1 - 0.0331 * x * x * x * x) return d * v;
    if (math.log(u) < 0.5 * x * x + d * (1 - v + math.log(v))) return d * v;
  }
}

double _normal(math.Random random) {
  final u1 = 1 - random.nextDouble();
  final u2 = random.nextDouble();
  return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
}
