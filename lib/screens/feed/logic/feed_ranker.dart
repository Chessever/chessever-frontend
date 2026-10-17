import 'dart:math' as math;

import 'package:chessever2/screens/for_you/discovery/models/report_game_type.dart';
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
    this.reportInterest = 0,
    this.reportType,
    this.openingKey,
    this.freestyle = false,
    this.online = false,
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

  /// Bounded bonus from the generated report’s actual turning points.
  final double reportInterest;
  final ReportGameType? reportType;
  final String? openingKey;

  /// Chess960 / Freestyle: a novelty in small doses (PM, Trello: "out of 10
  /// games one can be freestyle"), never the feed's staple.
  final bool freestyle;

  /// Played online (Titled Tuesday, Freestyle Friday, 3+0 Thursday...).
  /// Those events dump hundreds of games an evening; over the board games
  /// must not be drowned by them.
  final bool online;

  bool get decisive => result == '1-0' || result == '0-1';

  FeedSignals withSeenBefore(
    bool value, {
    double? reportInterest,
    ReportGameType? reportType,
    bool? freestyle,
    bool? online,
  }) =>
      value == seenBefore &&
          reportInterest == null &&
          reportType == null &&
          (freestyle == null || freestyle == this.freestyle) &&
          (online == null || online == this.online)
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
          reportInterest: reportInterest ?? this.reportInterest,
          reportType: reportType ?? this.reportType,
          openingKey: openingKey,
          freestyle: freestyle ?? this.freestyle,
          online: online ?? this.online,
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

/// Event names (tour slug or PGN `[Event]`) of Chess960 / Freestyle play.
final RegExp _freestyleName = RegExp(
  r'(freestyle|fischer\s*random|chess\s*960|\b960\b|chess9lx)',
  caseSensitive: false,
);

/// The streak ledger's online rule on event names
/// (`player_streak_is_online`). Not [GamesTourModel.isOnline]: that only
/// means the game carries a Lichess id, which every relayed OTB broadcast
/// game does.
final RegExp _onlineName = RegExp(
  r'(titled tuesday|\bonline\b|chess\.com|\bchesscom\b|\blichess\b'
  r'|\bbullet\b|speed chess championship|champions chess tour|\bcct\b'
  r'|freestyle friday|\d\+\d\s*thursday|\binternet\b|\bvirtual\b'
  r'|titled arena|\btornelo\b|\bchess24\b|\be-?sports\b'
  r'|\b\d+ \d+ thursday|collegiate chess league|\bbrawl\b)',
  caseSensitive: false,
);

String _eventText(String? slug, String? event) =>
    '${slug?.replaceAll(RegExp(r'[-_]+'), ' ') ?? ''} ${event ?? ''}';

/// Whether a tour slug or event name says Chess960 / Freestyle.
bool feedIsFreestyleEvent(String? slug, [String? event]) =>
    _freestyleName.hasMatch(_eventText(slug, event));

/// Whether a tour slug or event name says the event is played online.
bool feedIsOnlineEvent(String? slug, [String? event]) =>
    _onlineName.hasMatch(_eventText(slug, event));

final RegExp _pgnVariant = RegExp(r'^\[Variant "([^"]*)"\]', multiLine: true);
final RegExp _pgnFen = RegExp(r'^\[FEN "([^"]*)"\]', multiLine: true);

/// Whether [pgn] is a Chess960 / Freestyle game: a 960-flavoured `[Variant]`
/// header, or a `[FEN]` that is a full starting array with the back rank
/// shuffled. Catches Freestyle games of events whose name does not say so.
bool feedPgnIsFreestyle(String pgn) {
  final variant = _pgnVariant.firstMatch(pgn)?.group(1) ?? '';
  if (_freestyleName.hasMatch(variant)) return true;
  final fen = _pgnFen.firstMatch(pgn)?.group(1);
  if (fen == null) return false;
  final ranks = fen.split(' ').first.split('/');
  if (ranks.length != 8) return false;
  return ranks[1] == 'pppppppp' &&
      ranks[6] == 'PPPPPPPP' &&
      ranks[0] != 'rnbqkbnr' &&
      ranks[0].length == 8 &&
      ranks[0].toUpperCase() == ranks[7];
}

final RegExp _pgnSite = RegExp(r'^\[Site "([^"]*)"\]', multiLine: true);

/// Whether [pgn] was played on a server: its `[Site]` is Chess.com or a
/// lichess.org game. Relayed over-the-board games name their venue there.
bool feedPgnIsOnline(String pgn) {
  final site = _pgnSite.firstMatch(pgn)?.group(1) ?? '';
  return RegExp(
    r'chess\.com|lichess\.org',
    caseSensitive: false,
  ).hasMatch(site);
}

/// The floor every game of the public pools must clear: both players rated
/// and the pairing strong on average, so one 2550 in an open online event
/// does not carry a 1960 opponent's game into the feed. The viewer's own
/// players and community favourites are their own reason to be there.
bool feedMeetsQualityFloor(FeedSignals s) {
  switch (s.pool) {
    case FeedPool.favorite:
    case FeedPool.liked:
    case FeedPool.miniature:
      return true;
    case FeedPool.current:
    case FeedPool.top:
      if (s.whiteElo <= 0 || s.blackElo <= 0) return false;
      return s.averageElo >= 2350 && math.min(s.whiteElo, s.blackElo) >= 2150;
  }
}

/// How interesting a game is on its own, before variety is considered.
/// Report highlights and recency lead; rating and personal interest support
/// them. A rating gap alone says nothing about the game's chess quality.
///
/// The weights encode the product call: decisive high-Elo games are the
/// core; report stories, the viewer's players and community favourites add
/// variety. Recent games receive a substantial freshness bonus.
double feedInterest(FeedSignals s) {
  var score = ((s.averageElo - 2200) / 300).clamp(0.0, 2.2);
  score += s.decisive ? 0.8 : 0.1;

  switch (s.pool) {
    case FeedPool.favorite:
      score += 0.8;
    case FeedPool.liked:
      score += (0.35 * math.log(1 + s.likes) / math.ln2).clamp(0.0, 1.0);
    case FeedPool.miniature:
      score += 1.0;
    case FeedPool.current:
      score += s.eventElo >= 2600 ? 0.8 : 0.4;
    case FeedPool.top:
      break;
  }

  final hours = s.age.inMinutes / 60;
  score += 1.8 * math.exp(-hours.clamp(0, 24 * 30) / 48);

  score += s.reportInterest.clamp(0.0, 3.0);
  // Held back a little on their own; the ranker's quotas do the rest.
  if (s.freestyle) score -= 0.4;
  if (s.online) score -= 0.25;
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
///   best games come up most, but anything decent can. Candidates far below
///   the best one on offer ([qualityBand]) are not drawn at all, so a deep
///   pool of weak games cannot win on sheer numbers.
/// * **Variety.** The draw is damped for a candidate that repeats the pool,
///   event, players or drawn result of the last few picks, so the feed never
///   runs one kind of game for long; three games in a row from one event
///   never happen while anything else is left.
/// * **Quotas.** Over any [window] consecutive picks: at most
///   [freestylePerWindow] Freestyle game, [eventPerWindow] games of one
///   event, [onlinePerWindow] online games and [playerPerWindow] games of one
///   player, while anything else is left. A running event that dumps
///   hundreds of games an evening gets its share of the feed, not the feed.
/// * **Jackpots.** Every 3 to 5 picks (the gap itself is random) the draw is
///   skipped and the single best remaining game is served: a variable-ratio
///   reward, the rhythm that makes one more swipe feel worth it. The very
///   first pick is always one.
/// * **Exploration.** Occasional draws within the promising quality band let
///   an unknown player's report highlight surface without a weak random pick.
///
/// Seeded, so one session's order is stable and a test can replay it; a new
/// session (or a pull-to-refresh) brings a new seed.
class FeedRanker {
  FeedRanker(int seed) : _random = math.Random(seed) {
    _jackpotIn = 0; // the first pick is the hook
  }

  /// A ranker that starts from [feed]'s recent picks, for previewing a
  /// shortlist: its draws respect the quotas the feed has already used up,
  /// so the shortlist is not all of the one kind the feed may not show.
  FeedRanker.following(FeedRanker feed, int seed)
    : _random = math.Random(seed) {
    _history.addAll(feed._history);
    _jackpotIn = 0;
  }

  final math.Random _random;

  /// The most recent picks, newest last, at most [window].
  final List<FeedSignals> _history = [];
  late int _jackpotIn;

  static const double temperature = 0.7;
  static const double explore = 0.08;

  /// Interest below the best candidate on offer past which a game is not
  /// drawn: at [temperature] 0.7 it had a 1.4% weight against the best.
  static const double qualityBand = 3.0;

  /// The span the quotas count over.
  static const int window = 10;
  static const int freestylePerWindow = 1;
  static const int eventPerWindow = 3;
  static const int onlinePerWindow = 4;
  static const int playerPerWindow = 2;

  /// The recent picks the soft variety damping looks at.
  static const int _recentSize = 4;

  Iterable<FeedSignals> get _recent => _history.length <= _recentSize
      ? _history
      : _history.sublist(_history.length - _recentSize);

  int _count(bool Function(FeedSignals) test) => _history.where(test).length;

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
    if (s.eventKey != null) {
      // One more game of an event just shown is fine, held back a little;
      // [next] never allows a third in a row.
      if (s.eventKey == last.eventKey) factor *= 0.3;
      // And the more of the window it already has, the less it gets more.
      final shown = _count((h) => h.eventKey == s.eventKey);
      for (var i = 0; i < shown; i++) {
        factor *= 0.6;
      }
    }
    for (final h in _recent) {
      if (h.playerKeys.any(s.playerKeys.contains)) {
        factor *= 0.25;
        break;
      }
    }
    if (s.freestyle && _history.any((h) => h.freestyle)) factor *= 0.2;
    if (s.online && last.online) factor *= 0.6;
    if (!last.decisive && !s.decisive) factor *= 0.5;
    if (s.reportType != null && s.reportType == last.reportType) factor *= 0.45;
    if (s.openingKey != null && s.openingKey == last.openingKey) factor *= 0.65;
    return factor;
  }

  /// Whether [s] would break a quota of the current window. [eligible]
  /// candidates that do are passed over while any that does not is left.
  @visibleForTesting
  bool breaksQuota(FeedSignals s) => _quotas.any((quota) => quota(s));

  late final List<bool Function(FeedSignals)> _quotas = [
    (s) => s.freestyle && _count((h) => h.freestyle) >= freestylePerWindow,
    (s) =>
        s.eventKey != null &&
        _count((h) => h.eventKey == s.eventKey) >= eventPerWindow,
    (s) => s.online && _count((h) => h.online) >= onlinePerWindow,
    (s) => s.playerKeys.any(
      (p) => _count((h) => h.playerKeys.contains(p)) >= playerPerWindow,
    ),
  ];

  /// [options] narrowed by [keep], unless that leaves nothing.
  static List<FeedSignals> _prefer(
    List<FeedSignals> options,
    bool Function(FeedSignals) keep,
  ) {
    final kept = [
      for (final s in options)
        if (keep(s)) s,
    ];
    return kept.isEmpty ? options : kept;
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

    // Hard rules behind the soft penalties, most important first; each one
    // gives way only when nothing else is left. A rule that would empty the
    // options is skipped, never the ones before it.
    for (final quota in _quotas) {
      options = _prefer(options, (s) => !quota(s));
    }
    if (_history.length >= 2) {
      final before = _history[_history.length - 2];
      // Never a third game in a row from one event...
      final event = _history.last.eventKey;
      if (event != null && before.eventKey == event) {
        options = _prefer(options, (s) => s.eventKey != event);
      }
      // ...nor a third story of one kind.
      final type = _history.last.reportType;
      if (type != null && before.reportType == type) {
        options = _prefer(options, (s) => s.reportType != type);
      }
    }

    final FeedSignals pick;
    if (_jackpotIn <= 0) {
      pick = _best(options);
      _jackpotIn = 3 + _random.nextInt(3);
    } else if (_random.nextDouble() < explore) {
      // Explore within a quality band instead of randomly serving the weakest
      // or oldest game merely because it survived eligibility.
      final best = options.map(feedInterest).reduce(math.max);
      final promising = [
        for (final s in options)
          if (feedInterest(s) >= best - 1.5) s,
      ];
      pick = promising[_random.nextInt(promising.length)];
      _jackpotIn--;
    } else {
      pick = _draw(options);
      _jackpotIn--;
    }

    pool.remove(pick);
    _history.add(pick);
    if (_history.length > window) _history.removeAt(0);
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

  FeedSignals _draw(List<FeedSignals> all) {
    final interest = [for (final s in all) feedInterest(s)];
    final best = interest.reduce(math.max);
    final options = <FeedSignals>[];
    final scores = <double>[];
    for (var i = 0; i < all.length; i++) {
      if (interest[i] < best - qualityBand) continue;
      options.add(all[i]);
      // Shifted by the top score so exp never overflows.
      scores.add((interest[i] - best) / temperature);
    }
    final weights = [
      for (var i = 0; i < options.length; i++)
        math.exp(scores[i]) * varietyFactor(options[i]),
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
