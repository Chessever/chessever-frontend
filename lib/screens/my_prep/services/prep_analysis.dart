import 'package:chessever2/screens/gamebase/services/player_opening_tree.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/player_profile/utils/twic_event_identity.dart';
import 'package:chessever2/services/game_tree/game_tree_codec.dart';
import 'package:chessever2/services/game_tree/game_tree_store.dart';
import 'package:chessever2/utils/eco_openings.dart';
import 'package:flutter/foundation.dart';

/// How deep the device-built opening tree reaches, as the server's does.
const int kPrepTreeMaxPly = kGameTreeMaxPly;

/// The outcome of one game from the prepared player's chair.
enum PrepOutcome { win, draw, loss, unknown }

/// One downloaded game, light enough to keep tens of thousands in memory.
/// Its PGN stays in the account's file; [PrepAnalysis.pgnOf] reads it.
@immutable
class PrepGame {
  const PrepGame({
    required this.index,
    required this.source,
    required this.white,
    required this.black,
    required this.result,
    required this.plies,
    this.rowId = 0,
    this.sourcePath = '',
    this.whiteElo,
    this.blackElo,
    this.date,
    this.speed,
    this.timeControlText,
    this.eco,
    this.opening,
    this.url,
    this.event,
    this.site,
    this.round,
    this.eventName,
    this.eventId,
    this.eventSlug,
    this.eventDate,
    this.playerIsWhite,
    this.online,
  });

  /// Position in the newest-first list.
  final int index;

  /// The game's row in the profile's opening index.
  final int rowId;
  final PrepSource source;
  final String white;
  final String black;

  /// `1-0`, `0-1`, `1/2-1/2` or `*`.
  final String result;
  final int plies;
  final int? whiteElo;
  final int? blackElo;
  final DateTime? date;
  final PrepTimeControl? speed;
  final String? timeControlText;
  final String? eco;
  final String? opening;
  final String? url;

  /// The `Event` tag as written, which a broadcast fills with its round.
  final String? event;

  /// The `Site` tag: a venue, or a server's link to the game.
  final String? site;
  final String? round;

  /// What a ChessEver broadcast calls its event, with the id and slug that
  /// open it; null for a game from anywhere else.
  final String? eventName;
  final String? eventId;
  final String? eventSlug;

  /// The event's first day.
  final DateTime? eventDate;

  /// Which side the prepared player had; null when neither name matched.
  final bool? playerIsWhite;

  /// Which account file a game came from (a profile can hold two accounts
  /// on one site).
  final String sourcePath;

  factory PrepGame.fromIndex(GameTreeGame g, int index) => PrepGame(
    index: index,
    rowId: g.id,
    sourcePath: g.sourcePath,
    source: PrepSource.tryParse(g.source) ?? PrepSource.lichess,
    white: g.white,
    black: g.black,
    result: treeResultText(g.result),
    plies: g.plies,
    whiteElo: g.whiteElo,
    blackElo: g.blackElo,
    date: treeDateTime(g.date),
    speed:
        g.speed == null ||
            g.speed! < 0 ||
            g.speed! >= PrepTimeControl.values.length
        ? null
        : PrepTimeControl.values[g.speed!],
    timeControlText: g.timeControl,
    eco: g.eco,
    opening: g.opening,
    url: g.url,
    event: g.event,
    site: g.site,
    round: g.round,
    eventName: g.eventName,
    eventId: g.eventId,
    eventSlug: g.eventSlug,
    eventDate: treeDateTime(g.eventDate),
    online: g.online,
    playerIsWhite: switch (g.side) {
      1 => true,
      2 => false,
      _ => null,
    },
  );

  String get opponent => playerIsWhite == false ? white : black;
  int? get opponentElo => playerIsWhite == false ? whiteElo : blackElo;
  int? get playerElo => playerIsWhite == false ? blackElo : whiteElo;

  double? get averageElo {
    final ratings = [whiteElo, blackElo].whereType<int>().where((r) => r > 0);
    return ratings.isEmpty
        ? null
        : ratings.reduce((a, b) => a + b) / ratings.length;
  }

  /// What the index read from the game's source and `Site`; null for a
  /// game built without the index.
  final bool? online;

  /// Played on a server rather than over the board (the Format filter).
  bool get isOnline =>
      online ?? treeGameIsOnline(sourceKind: source.name, link: url);

  PrepOutcome get outcome {
    final white = playerIsWhite;
    if (white == null) return PrepOutcome.unknown;
    return switch (result) {
      '1-0' => white ? PrepOutcome.win : PrepOutcome.loss,
      '0-1' => white ? PrepOutcome.loss : PrepOutcome.win,
      '1/2-1/2' => PrepOutcome.draw,
      _ => PrepOutcome.unknown,
    };
  }

  /// The tournament this game was played in; null for a server's pool game,
  /// which belongs to none.
  String? get eventTitle =>
      prepEventTitle(broadcast: eventName, event: event, site: site);

  /// What a game card prints where its event goes: the tournament, else
  /// where and how fast the game was played (`Lichess · Blitz`).
  String get eventLabel =>
      eventTitle ??
      (speed == null
          ? source.label
          : '${source.label} · ${speed!.labelFor(source)}');

  /// Games sharing this belong under one event card. Null leaves a game
  /// out of any: an online account's games stay a plain dated list, where
  /// an arena played every hour would otherwise head a section each day.
  String? get eventKey {
    if (source.online) return null;
    final key = eventTitle?.toLowerCase().replaceAll(_notWord, ' ').trim();
    return key == null || key.isEmpty ? null : key;
  }

  /// The family name of the opening, without its variation.
  String get openingFamily {
    final name = opening;
    if (name == null || name.isEmpty) return eco ?? 'Unknown opening';
    return name.split(RegExp(r'[:,]')).first.trim();
  }
}

final RegExp _notWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// What a server writes as the `Event` of a game played in no tournament:
/// Lichess's `Rated Blitz game` (older exports end in the arena's link) and
/// Chess.com's `Live Chess` and `Let's Play!`.
final RegExp _poolGame = RegExp(
  r"^(?:(?:rated|casual|unrated)\s.*\b(?:game|https?://\S+)"
  r"|live chess|let'?s play!?|daily chess|online chess)$",
  caseSensitive: false,
);

/// The name of the tournament a game belongs to, from what its PGN says.
/// [broadcast] is a ChessEver broadcast's own name for it, which wins:
/// there the `Event` tag may carry a round's dates or pairing instead.
String? prepEventTitle({String? broadcast, String? event, String? site}) {
  final named = broadcast?.trim();
  if (named != null && named.isNotEmpty) return named;
  final raw = event?.trim();
  if (raw == null || raw.isEmpty || raw == '?' || _poolGame.hasMatch(raw)) {
    return null;
  }
  // `Round 7: Carlsen - Caruana` names a pairing; its broadcast link, when
  // the game has one, still names the tournament.
  if (isTwicRoundDisplayTitle(raw)) return eventTitleFromBroadcastSite(site);
  return raw;
}

/// Everything My Prep shows for a profile: the light games list in memory,
/// the tree and every PGN on disk behind [store].
@immutable
class PrepAnalysis {
  const PrepAnalysis({
    required this.profileId,
    required this.games,
    this.store,
  });

  final String profileId;

  /// Newest first.
  final List<PrepGame> games;

  /// The profile's opening index; null only for a profile with no games.
  final GameTreeStore? store;

  static PrepAnalysis empty(String profileId) =>
      PrepAnalysis(profileId: profileId, games: const []);

  PlayerOpeningTreeIndex get tree =>
      store?.tree ?? const PlayerOpeningTreeIndex.empty();

  /// The game's full PGN, read from its account's file.
  String? pgnOf(PrepGame game) => store?.pgn(game.rowId);

  String gameId(PrepGame game) => 'prep:$profileId:${game.rowId}';
}

/// The clock category of a game. Chess.com's own TimeClass is
/// authoritative; Lichess games use its estimated-duration bands.
PrepTimeControl? prepSpeedOf({
  required PrepSource source,
  String? timeControl,
  String? timeClass,
  String? event,
}) {
  final speed = classifyTreeSpeed(
    lichess: source == PrepSource.lichess,
    timeControl: timeControl,
    timeClass: timeClass,
    event: event,
    source: source.name,
  );
  return speed == null ? null : PrepTimeControl.values[speed];
}

/// The explorer's three clock filters, which fold the fast and slow ends in.
String? prepExplorerTimeControl(PrepTimeControl? speed) =>
    switch (TreeSpeed.explorerClock(speed?.index)) {
      1 => 'blitz',
      2 => 'rapid',
      3 => 'classical',
      _ => null,
    };

// ------------------------------------------------------------------ stats

/// Wins, draws and losses for some slice of the games.
@immutable
class PrepTally {
  const PrepTally({this.wins = 0, this.draws = 0, this.losses = 0});

  final int wins;
  final int draws;
  final int losses;

  int get total => wins + draws + losses;

  /// Points per game, 0..1.
  double? get score => total == 0 ? null : (wins + draws / 2) / total;

  PrepTally operator +(PrepOutcome outcome) => switch (outcome) {
    PrepOutcome.win => PrepTally(wins: wins + 1, draws: draws, losses: losses),
    PrepOutcome.draw => PrepTally(wins: wins, draws: draws + 1, losses: losses),
    PrepOutcome.loss => PrepTally(wins: wins, draws: draws, losses: losses + 1),
    PrepOutcome.unknown => this,
  };
}

@immutable
class PrepOpeningLine {
  const PrepOpeningLine(this.name, this.eco, this.tally);
  final String name;
  final String? eco;
  final PrepTally tally;
}

@immutable
class PrepOpponentLine {
  const PrepOpponentLine(this.name, this.rating, this.tally);
  final String name;

  /// Their average rating across the games against them.
  final int? rating;
  final PrepTally tally;
}

/// One year of games: every game the player's side is known for, and the
/// results among them. The difference is the unfinished ones.
@immutable
class PrepYearLine {
  const PrepYearLine(this.year, this.total, this.tally);
  final int year;
  final int total;
  final PrepTally tally;
}

/// The About numbers for a slice of games, defined as the desktop app's
/// Prepare dashboard defines them. Only games whose side is known count.
@immutable
class PrepStats {
  const PrepStats({
    required this.games,
    required this.overall,
    required this.asWhite,
    required this.asBlack,
    required this.whiteOpenings,
    required this.blackOpenings,
    required this.opponents,
    required this.byYear,
    required this.lengths,
    this.clocks = const [],
    this.peakRating,
    this.currentRating,
    this.ratingSpeed,
    this.ratingSource,
    this.performance,
    this.averageOpponent,
    this.ratingHistory = const [],
  });

  /// Every game in the slice, including those left out of the results.
  final int games;
  final PrepTally overall;
  final PrepTally asWhite;
  final PrepTally asBlack;

  /// The ten most played ECO codes with each colour.
  final List<PrepOpeningLine> whiteOpenings;
  final List<PrepOpeningLine> blackOpenings;
  final List<PrepOpponentLine> opponents;
  final List<PrepYearLine> byYear;

  /// Games by length in moves: 0–20, 21–30, 31–40, 41–50, 50+.
  final List<int> lengths;
  static const lengthLabels = ['0–20', '21–30', '31–40', '41–50', '50+'];

  /// How the games divide by clock, most played first. Counted before the
  /// clock, result and colour scopes, so it stays whole while they narrow.
  final List<(PrepTimeControl?, int)> clocks;

  /// The highest and the latest point of [ratingHistory].
  final int? peakRating;
  final int? currentRating;

  /// The clock [ratingHistory] follows; null when it spans every clock.
  final PrepTimeControl? ratingSpeed;

  /// The provider whose scale [ratingHistory] is on.
  final PrepSource? ratingSource;
  final int? performance;
  final int? averageOpponent;
  final List<(DateTime, int)> ratingHistory;

  int get decisive => overall.wins + overall.losses;

  /// The share of decided games that had a winner, 0..1.
  double? get decisiveRate =>
      overall.total == 0 ? null : decisive / overall.total;

  /// [games] is the scoped slice. [clockGames] is the same slice before its
  /// clock, result and colour scopes. [speed] is the clock scope, and
  /// [preferredRating] the ladder the rating history follows without one.
  static PrepStats of(
    Iterable<PrepGame> games, {
    Iterable<PrepGame>? clockGames,
    PrepTimeControl? speed,
    PrepTimeControl preferredRating = PrepTimeControl.classical,
  }) {
    var white = const PrepTally();
    var black = const PrepTally();
    final whiteOpenings = <String, (String?, PrepTally)>{};
    final blackOpenings = <String, (String?, PrepTally)>{};
    final opponents = <String, _Opponent>{};
    final years = <int, (int, PrepTally)>{};
    final lengths = List<int>.filled(5, 0);
    final rated = <PrepGame>[];
    var opponentSum = 0;
    var opponentCount = 0;
    var count = 0;
    for (final g in games) {
      count++;
      final isWhite = g.playerIsWhite;
      if (isWhite == null) continue;
      final outcome = g.outcome;
      if (isWhite) {
        white += outcome;
      } else {
        black += outcome;
      }
      final eco = g.eco?.trim().toUpperCase() ?? '';
      if (eco.isNotEmpty && outcome != PrepOutcome.unknown) {
        final table = isWhite ? whiteOpenings : blackOpenings;
        final prior = table[eco];
        table[eco] = (
          prior?.$1 ?? _openingName(g.opening),
          (prior?.$2 ?? const PrepTally()) + outcome,
        );
      }
      final theirs = g.opponentElo ?? 0;
      final opp = g.opponent.trim();
      if (opp.isNotEmpty && opp != '?') {
        final line = opponents.putIfAbsent(
          opp.toLowerCase(),
          () => _Opponent(opp),
        );
        line.tally += outcome;
        if (theirs > 0) {
          line.ratingSum += theirs;
          line.ratingCount++;
        }
      }
      if (theirs > 0) {
        opponentSum += theirs;
        opponentCount++;
      }
      if ((g.playerElo ?? 0) > 0 && g.date != null) rated.add(g);
      final year = g.date?.year;
      if (year != null) {
        final prior = years[year];
        years[year] = (
          (prior?.$1 ?? 0) + 1,
          (prior?.$2 ?? const PrepTally()) + outcome,
        );
      }
      if (g.plies > 0) {
        lengths[g.plies <= 40
            ? 0
            : g.plies <= 60
            ? 1
            : g.plies <= 80
            ? 2
            : g.plies <= 100
            ? 3
            : 4]++;
      }
    }

    List<PrepOpeningLine> top(Map<String, (String?, PrepTally)> table) {
      final lines =
          [
            for (final e in table.entries)
              PrepOpeningLine(
                // The game's own opening name, else the code's catalogue name.
                e.value.$1 ?? EcoOpenings.codeToName[e.key] ?? e.key,
                e.key,
                e.value.$2,
              ),
          ]..sort((a, b) {
            final byGames = b.tally.total.compareTo(a.tally.total);
            return byGames != 0 ? byGames : a.eco!.compareTo(b.eco!);
          });
      return lines.take(10).toList();
    }

    final overall = PrepTally(
      wins: white.wins + black.wins,
      draws: white.draws + black.draws,
      losses: white.losses + black.losses,
    );
    final average = opponentCount == 0
        ? null
        : (opponentSum / opponentCount).round();
    final opponentLines =
        [
          for (final o in opponents.values)
            if (o.tally.total > 0)
              PrepOpponentLine(
                o.name,
                o.ratingCount == 0
                    ? null
                    : (o.ratingSum / o.ratingCount).round(),
                o.tally,
              ),
        ]..sort((a, b) {
          final byGames = b.tally.total.compareTo(a.tally.total);
          return byGames != 0 ? byGames : b.tally.wins.compareTo(a.tally.wins);
        });

    final clockCounts = <PrepTimeControl?, int>{};
    for (final g in clockGames ?? games) {
      if (g.playerIsWhite == null) continue;
      clockCounts[g.speed] = (clockCounts[g.speed] ?? 0) + 1;
    }
    final rating = _ratingSeries(
      rated,
      scoped: speed,
      preferred: preferredRating,
    );

    return PrepStats(
      games: count,
      overall: overall,
      asWhite: white,
      asBlack: black,
      whiteOpenings: top(whiteOpenings),
      blackOpenings: top(blackOpenings),
      opponents: opponentLines.take(10).toList(),
      byYear: [
        for (final y in years.keys.toList()..sort())
          PrepYearLine(y, years[y]!.$1, years[y]!.$2),
      ],
      lengths: lengths,
      clocks: clockCounts.entries.map((e) => (e.key, e.value)).toList()
        ..sort((a, b) => b.$2.compareTo(a.$2)),
      peakRating: rating.$1.isEmpty
          ? null
          : rating.$1.map((p) => p.$2).reduce((a, b) => a > b ? a : b),
      currentRating: rating.$1.isEmpty ? null : rating.$1.last.$2,
      ratingSpeed: rating.$2,
      ratingSource: rating.$3,
      performance: average == null || overall.total == 0
          ? null
          : average + _fideDp[(overall.score! * 100).round().clamp(0, 100)],
      averageOpponent: average,
      ratingHistory: rating.$1,
    );
  }

  static String? _openingName(String? raw) {
    final name = raw?.trim();
    return switch (name?.toLowerCase()) {
      null || '' || '?' || '-' || 'unknown' || 'unknown opening' => null,
      _ => name,
    };
  }

  /// One rating per day on a single ladder: the scoped clock, else the
  /// preferred one when it was played, else the most played of classical,
  /// rapid and blitz. A classical preference follows every rated game when
  /// the rated history begins before the classical games do.
  ///
  /// Ratings from two accounts or providers are separate scales and are
  /// never drawn as one line.
  static (List<(DateTime, int)>, PrepTimeControl?, PrepSource?) _ratingSeries(
    List<PrepGame> rated, {
    required PrepTimeControl? scoped,
    required PrepTimeControl preferred,
  }) {
    if (rated.isEmpty) return (const [], null, null);
    var candidates = rated;
    var selected = scoped;
    if (scoped == null) {
      const order = [
        PrepTimeControl.classical,
        PrepTimeControl.rapid,
        PrepTimeControl.blitz,
      ];
      final counts = <PrepTimeControl, int>{};
      for (final g in rated) {
        final speed = g.speed;
        if (speed != null && order.contains(speed)) {
          counts[speed] = (counts[speed] ?? 0) + 1;
        }
      }
      if (counts.containsKey(preferred)) {
        selected = preferred;
      } else if (counts.isNotEmpty) {
        selected = order
            .where(counts.containsKey)
            .reduce((a, b) => counts[a]! >= counts[b]! ? a : b);
      }
      if (selected != null) {
        final own = [
          for (final g in rated)
            if (g.speed == selected) g,
        ];
        DateTime first(List<PrepGame> list) =>
            list.map((g) => g.date!).reduce((a, b) => a.isBefore(b) ? a : b);
        if (preferred == PrepTimeControl.classical &&
            own.isNotEmpty &&
            first(rated).isBefore(first(own))) {
          selected = null;
        } else {
          candidates = own;
        }
      }
    }
    // Each account rates on its own scale: follow the one with most games.
    final tracks = <String, List<PrepGame>>{};
    for (final g in candidates) {
      (tracks['${g.source.name}|${g.sourcePath}'] ??= []).add(g);
    }
    candidates = tracks.values.reduce((a, b) => b.length > a.length ? b : a);
    final source = candidates.first.source;
    // Games arrive newest first, so the first seen on a day is its last.
    final byDay = <int, (DateTime, int)>{};
    for (final g in candidates) {
      final date = g.date!;
      byDay.putIfAbsent(
        date.year * 10000 + date.month * 100 + date.day,
        () => (date, g.playerElo!),
      );
    }
    final spots = byDay.values.toList()..sort((a, b) => a.$1.compareTo(b.$1));
    const most = 400;
    if (spots.length <= most) return (spots, selected, source);
    final step = spots.length / most;
    final out = [for (var i = 0; i < most; i++) spots[(i * step).floor()]];
    if (out.last != spots.last) out.add(spots.last);
    return (out, selected, source);
  }
}

class _Opponent {
  _Opponent(this.name);
  final String name;
  PrepTally tally = const PrepTally();
  int ratingSum = 0;
  int ratingCount = 0;
}

/// FIDE's rating difference for a score percentage, 0..100.
const List<int> _fideDp = [
  -800, -677, -589, -538, -501, -470, -444, -422, -401, -383, -366, -351, //
  -336, -322, -309, -296, -284, -273, -262, -251, -240, -230, -220, -211, //
  -202, -193, -184, -175, -166, -158, -149, -141, -133, -125, -117, -110, //
  -102, -95, -87, -80, -72, -65, -57, -50, -43, -36, -29, -21, -14, -7, 0, //
  7, 14, 21, 29, 36, 43, 50, 57, 65, 72, 80, 87, 95, 102, 110, 117, 125, 133, //
  141, 149, 158, 166, 175, 184, 193, 202, 211, 220, 230, 240, 251, 262, 273, //
  284, 296, 309, 322, 336, 351, 366, 383, 401, 422, 444, 470, 501, 538, 589, //
  677, 800,
];
