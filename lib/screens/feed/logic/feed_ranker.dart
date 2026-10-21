import 'dart:math' as math;

import 'package:chessever2/screens/feed/logic/feed_taste.dart';
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
    this.countries = const {},
    this.timeClass,
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

  /// The players' countries (ISO codes), for the viewer's countrymen.
  final Set<String> countries;

  /// `standard`, `rapid` or `blitz`, when the event says.
  final String? timeClass;

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
          countries: countries,
          timeClass: timeClass,
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
  if (s.seenBefore) score -= 2.5;
  return score;
}

/// Picks the Feed's next game from a pool of candidates, one at a time.
///
/// Not a sort, and no fixed rules about what may follow what. Each
/// candidate's appeal is three things the feed knows at that moment:
///
/// * **Quality** ([feedInterest]): strength, result, report highlights,
///   freshness.
/// * **Taste** ([FeedTaste]): what this viewer has enjoyed, sampled rather
///   than averaged, so uncertain interests get probed now and then.
/// * **Fatigue** ([FeedFatigue]): what the last picks already showed. An
///   event that dumps hundreds of games an evening tires after a game or
///   two and comes back a few posts later; a kind of game the viewer
///   swipes away (Freestyle, say) tires harder than one they love.
///
/// The pick is a softmax draw over appeal, except:
///
/// * **Jackpots.** Every 3 to 5 picks (the gap itself is random) the best
///   game on offer is served outright: a variable-ratio reward, the rhythm
///   that makes one more swipe feel worth it. The very first pick is one.
/// * **Exploration** is built in: taste is sampled, so an interest the
///   feed is unsure of is sometimes sampled high and gets its chance, and
///   one the viewer has turned down stays down.
/// * **Quality band.** Games far below the best on offer
///   ([qualityBand]) are not drawn, whatever the viewer's taste; a deep pool
///   of weak games cannot win on numbers.
///
/// Seeded, so one session's order is stable and a test can replay it; a new
/// session (or a pull-to-refresh) brings a new seed.
class FeedRanker {
  FeedRanker(int seed, {FeedTaste? taste})
    : _random = math.Random(seed),
      taste = taste ?? FeedTaste(),
      _fatigue = FeedFatigue() {
    _jackpotIn = 0; // the first pick is the hook
  }

  /// A ranker that starts from [feed]'s taste and fatigue, for previewing a
  /// shortlist: it does not fill up with what the feed is tired of.
  FeedRanker.following(FeedRanker feed, int seed)
    : _random = math.Random(seed),
      taste = feed.taste,
      _fatigue = FeedFatigue.copy(feed._fatigue) {
    _jackpotIn = 0;
  }

  final math.Random _random;

  /// Shared with the feed that owns it: learning lands in every ranker.
  final FeedTaste taste;
  final FeedFatigue _fatigue;
  late int _jackpotIn;

  static const double temperature = 0.7;

  /// Interest below the best candidate on offer past which a game is not
  /// drawn: at [temperature] 0.7 it had a 1.4% weight against the best.
  static const double qualityBand = 3.0;

  /// Quality, taste and fatigue together; see the class doc.
  @visibleForTesting
  double appeal(FeedSignals s, {FeedTasteDraw? draw}) =>
      feedInterest(s) + taste.score(s, draw: draw) - _fatigue.penalty(s, taste);

  /// Takes the next pick out of [pool] (and returns it), or null when no
  /// candidate passes [eligible].
  FeedSignals? next(
    List<FeedSignals> pool, {
    bool Function(FeedSignals)? eligible,
  }) {
    final all = [
      for (final s in pool)
        if (eligible == null || eligible(s)) s,
    ];
    if (all.isEmpty) return null;

    final interest = {for (final s in all) s: feedInterest(s)};
    final best = interest.values.reduce(math.max);
    final options = [
      for (final s in all)
        if (interest[s]! >= best - qualityBand) s,
    ];
    final draw = taste.draw(_random);

    final FeedSignals pick;
    if (_jackpotIn <= 0) {
      // A jackpot is a sure thing: taste as expected, not as sampled.
      pick = _top(options, null);
      _jackpotIn = 3 + _random.nextInt(3);
    } else {
      pick = _softmax(options, (s) => appeal(s, draw: draw));
      _jackpotIn--;
    }

    pool.remove(pick);
    _fatigue.picked(pick);
    return pick;
  }

  FeedSignals _top(List<FeedSignals> options, FeedTasteDraw? draw) {
    FeedSignals? best;
    var bestScore = double.negativeInfinity;
    for (final s in options) {
      final score = appeal(s, draw: draw);
      if (score > bestScore) {
        best = s;
        bestScore = score;
      }
    }
    return best!;
  }

  FeedSignals _softmax(
    List<FeedSignals> options,
    double Function(FeedSignals) score,
  ) {
    final scores = [for (final s in options) score(s) / temperature];
    // Shifted by the top score so exp never overflows.
    final top = scores.reduce(math.max);
    final weights = [for (final x in scores) math.exp(x - top)];
    final total = weights.fold<double>(0, (a, b) => a + b);
    var roll = _random.nextDouble() * total;
    for (var i = 0; i < options.length; i++) {
      roll -= weights[i];
      if (roll <= 0) return options[i];
    }
    return options.last;
  }
}
