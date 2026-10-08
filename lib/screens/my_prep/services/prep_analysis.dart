import 'package:chessever2/screens/gamebase/services/player_opening_tree.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/services/game_tree/game_tree_codec.dart';
import 'package:chessever2/services/game_tree/game_tree_store.dart';
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
    this.playerIsWhite,
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
    playerIsWhite: switch (g.side) {
      1 => true,
      2 => false,
      _ => null,
    },
  );

  String get opponent => playerIsWhite == false ? white : black;
  int? get opponentElo => playerIsWhite == false ? whiteElo : blackElo;
  int? get playerElo => playerIsWhite == false ? blackElo : whiteElo;

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

  /// The family name of the opening, without its variation.
  String get openingFamily {
    final name = opening;
    if (name == null || name.isEmpty) return eco ?? 'Unknown opening';
    return name.split(RegExp(r'[:,]')).first.trim();
  }
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
  final int? rating;
  final PrepTally tally;
}

/// The Overview numbers for a filtered set of games.
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
    this.peakRating,
    this.currentRating,
    this.performance,
    this.averageOpponent,
    this.ratingHistory = const [],
  });

  final int games;
  final PrepTally overall;
  final PrepTally asWhite;
  final PrepTally asBlack;
  final List<PrepOpeningLine> whiteOpenings;
  final List<PrepOpeningLine> blackOpenings;
  final List<PrepOpponentLine> opponents;
  final List<(int, PrepTally)> byYear;

  /// Games ending within each 20-move band: ≤20, 21–40, 41–60, 61–80, 80+.
  final List<int> lengths;
  final int? peakRating;
  final int? currentRating;
  final int? performance;
  final int? averageOpponent;
  final List<(DateTime, int)> ratingHistory;

  static PrepStats of(Iterable<PrepGame> games) {
    var overall = const PrepTally();
    var white = const PrepTally();
    var black = const PrepTally();
    final whiteOpenings = <String, (String?, PrepTally)>{};
    final blackOpenings = <String, (String?, PrepTally)>{};
    final opponents = <String, (String, int?, PrepTally)>{};
    final years = <int, PrepTally>{};
    final lengths = List<int>.filled(5, 0);
    final ratingsByMonth = <int, (DateTime, int)>{};
    final ratingTracks = <String>{};
    int? peak;
    int? current;
    var opponentSum = 0;
    var opponentCount = 0;
    var count = 0;
    for (final g in games) {
      count++;
      final outcome = g.outcome;
      overall += outcome;
      if (g.playerIsWhite == true) white += outcome;
      if (g.playerIsWhite == false) black += outcome;
      final table = g.playerIsWhite == false ? blackOpenings : whiteOpenings;
      if (g.playerIsWhite != null) {
        final name = g.openingFamily;
        final prior = table[name];
        table[name] = (
          prior?.$1 ?? g.eco,
          (prior?.$2 ?? const PrepTally()) + outcome,
        );
        final opp = g.opponent;
        final key = opp.toLowerCase();
        final seen = opponents[key];
        opponents[key] = (
          seen?.$1 ?? opp,
          seen?.$2 ?? g.opponentElo,
          (seen?.$3 ?? const PrepTally()) + outcome,
        );
        final mine = g.playerElo;
        if (mine != null && mine > 0) {
          ratingTracks.add('${g.source.name}|${g.sourcePath}|${g.speed?.name}');
          if (g.date case final date?) {
            ratingsByMonth.putIfAbsent(
              date.year * 12 + date.month,
              () => (date, mine),
            );
          }
          current ??= mine; // games are newest first
          if (peak == null || mine > peak) peak = mine;
        }
        final theirs = g.opponentElo;
        if (theirs != null && theirs > 0 && outcome != PrepOutcome.unknown) {
          opponentSum += theirs;
          opponentCount++;
        }
      }
      final year = g.date?.year;
      if (year != null) {
        years[year] = (years[year] ?? const PrepTally()) + outcome;
      }
      final moves = (g.plies + 1) ~/ 2;
      lengths[moves <= 20
          ? 0
          : moves <= 40
          ? 1
          : moves <= 60
          ? 2
          : moves <= 80
          ? 3
          : 4]++;
    }

    List<PrepOpeningLine> top(Map<String, (String?, PrepTally)> table) {
      final lines = [
        for (final e in table.entries)
          PrepOpeningLine(e.key, e.value.$1, e.value.$2),
      ]..sort((a, b) => b.tally.total.compareTo(a.tally.total));
      return lines.take(8).toList();
    }

    final average = opponentCount == 0 ? null : opponentSum / opponentCount;
    final decided = overall.total;
    final performance = average == null || decided == 0
        ? null
        : (average + 400 * (overall.wins - overall.losses) / decided).round();
    final opponentLines = [
      for (final o in opponents.values) PrepOpponentLine(o.$1, o.$2, o.$3),
    ]..sort((a, b) => b.tally.total.compareTo(a.tally.total));

    return PrepStats(
      games: count,
      overall: overall,
      asWhite: white,
      asBlack: black,
      whiteOpenings: top(whiteOpenings),
      blackOpenings: top(blackOpenings),
      opponents: opponentLines.take(8).toList(),
      byYear: [for (final y in years.keys.toList()..sort()) (y, years[y]!)],
      lengths: lengths,
      peakRating: peak,
      currentRating: current,
      performance: performance,
      averageOpponent: average?.round(),
      // Separate accounts, providers and clock ratings use separate scales.
      ratingHistory: ratingTracks.length == 1
          ? (ratingsByMonth.values.toList()
              ..sort((a, b) => a.$1.compareTo(b.$1)))
          : const [],
    );
  }
}
