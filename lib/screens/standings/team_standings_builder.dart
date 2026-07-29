import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/team_standing_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';

/// Pure team-standings computation for team events, following the chess
/// team-event standard:
///
/// - **Board points (GP):** sum of finished board results (1 / ½ / 0). Ongoing
///   or unknown games are excluded.
/// - **Match:** the set of games in one round between one unordered team pair,
///   keyed by `(roundId, sorted team pair)`.
/// - **Match points (MP):** counted only for a *completed* match (every present
///   board finished): more board points → 2, equal → 1, fewer → 0. A match with
///   any ongoing board contributes GP but no MP yet — provisional-safe and
///   aligned with how chess-results / lichess post team results.
/// - **Rank:** MP desc → GP desc → team name asc.
///
/// Byes are not credited (v1): a round with no game for a team simply adds
/// nothing.
List<TeamStandingModel> buildTeamStandings({
  required List<GamesTourModel> games,
  required List<PlayerStandingModel> playerStandings,
}) {
  // 1. Group games into matches keyed by (round, unordered team pair).
  final matches = <String, Map<String, _MatchSide>>{};
  for (final g in games) {
    final wTeam = g.whitePlayer.team?.trim();
    final bTeam = g.blackPlayer.team?.trim();
    if (wTeam == null || wTeam.isEmpty || bTeam == null || bTeam.isEmpty) {
      continue;
    }
    final pair = ([wTeam, bTeam]..sort()).join('');
    final key = '${g.roundId}$pair';
    final sides = matches.putIfAbsent(key, () => <String, _MatchSide>{});
    final wSide = sides.putIfAbsent(wTeam, () => _MatchSide());
    final bSide = sides.putIfAbsent(bTeam, () => _MatchSide());
    wSide.total++;
    bSide.total++;

    final status = g.gameStatus;
    if (!status.isFinished) continue; // ongoing/unknown: no GP, no board count
    wSide.finished++;
    bSide.finished++;
    switch (status) {
      case GameStatus.whiteWins:
        wSide.points += 1.0;
        break;
      case GameStatus.blackWins:
        bSide.points += 1.0;
        break;
      case GameStatus.draw:
        wSide.points += 0.5;
        bSide.points += 0.5;
        break;
      default:
        break;
    }
  }

  // 2. Fold matches into per-team aggregates.
  final agg = <String, _TeamAgg>{};
  for (final sides in matches.values) {
    if (sides.length != 2) continue; // defensive: skip malformed groups
    final entries = sides.entries.toList();
    final aName = entries[0].key, bName = entries[1].key;
    final a = entries[0].value, b = entries[1].value;

    agg.putIfAbsent(aName, () => _TeamAgg())
      ..gamePoints += a.points
      ..boardsPlayed += a.finished;
    agg.putIfAbsent(bName, () => _TeamAgg())
      ..gamePoints += b.points
      ..boardsPlayed += b.finished;

    // Match points only when the match is fully decided.
    final complete =
        a.total > 0 && a.finished == a.total && b.finished == b.total;
    if (!complete) continue;
    final aAgg = agg[aName]!, bAgg = agg[bName]!;
    if (a.points > b.points) {
      aAgg
        ..mp += 2
        ..won += 1;
      bAgg.lost += 1;
    } else if (a.points < b.points) {
      bAgg
        ..mp += 2
        ..won += 1;
      aAgg.lost += 1;
    } else {
      aAgg
        ..mp += 1
        ..drawn += 1;
      bAgg
        ..mp += 1
        ..drawn += 1;
    }
  }

  // 3. Players per team (from the already-ranked individual standings).
  final playersByTeam = <String, List<PlayerStandingModel>>{};
  for (final p in playerStandings) {
    final t = p.team?.trim();
    if (t == null || t.isEmpty) continue;
    playersByTeam.putIfAbsent(t, () => <PlayerStandingModel>[]).add(p);
  }

  // 4. Build rows for the union of teams seen in games and in the roster.
  final teamNames = <String>{...agg.keys, ...playersByTeam.keys};
  final rows =
      teamNames.map((name) {
        final a = agg[name] ?? _TeamAgg();
        return TeamStandingModel(
          teamName: name,
          rank: 0,
          matchPoints: a.mp,
          gamePoints: a.gamePoints,
          matchesWon: a.won,
          matchesDrawn: a.drawn,
          matchesLost: a.lost,
          boardsPlayed: a.boardsPlayed,
          players: playersByTeam[name] ?? const <PlayerStandingModel>[],
        );
      }).toList();

  rows.sort((x, y) {
    if (x.matchPoints != y.matchPoints) {
      return y.matchPoints.compareTo(x.matchPoints);
    }
    if (x.gamePoints != y.gamePoints) {
      return y.gamePoints.compareTo(x.gamePoints);
    }
    return x.teamName.compareTo(y.teamName);
  });

  // 5. Assign 1-based ranks.
  return <TeamStandingModel>[
    for (var i = 0; i < rows.length; i++)
      TeamStandingModel(
        teamName: rows[i].teamName,
        rank: i + 1,
        matchPoints: rows[i].matchPoints,
        gamePoints: rows[i].gamePoints,
        matchesWon: rows[i].matchesWon,
        matchesDrawn: rows[i].matchesDrawn,
        matchesLost: rows[i].matchesLost,
        boardsPlayed: rows[i].boardsPlayed,
        players: rows[i].players,
      ),
  ];
}

enum TeamMatchResult { win, draw, loss, ongoing }

/// One individual board within a team match, from the selected team's side.
class TeamBoardGame {
  final int? boardNr;
  final String ourName;
  final String? ourTitle;
  final bool ourIsWhite;
  final String opponentName;
  final String? opponentTitle;
  final int? opponentRating;
  final TeamMatchResult result; // our player's outcome
  final GamesTourModel game; // for opening the board in the chessboard

  const TeamBoardGame({
    required this.boardNr,
    required this.ourName,
    required this.ourTitle,
    required this.ourIsWhite,
    required this.opponentName,
    required this.opponentTitle,
    required this.opponentRating,
    required this.result,
    required this.game,
  });
}

/// One round's match for a given team: the opponent, the board-point split, and
/// the individual board games.
class TeamMatch {
  final String roundId;
  final String? roundSlug;
  final String roundLabel;
  final String opponentTeam;
  final double ourPoints;
  final double opponentPoints;
  final int boards;
  final bool complete;
  final List<TeamBoardGame> boardGames;

  const TeamMatch({
    required this.roundId,
    required this.roundSlug,
    required this.roundLabel,
    required this.opponentTeam,
    required this.ourPoints,
    required this.opponentPoints,
    required this.boards,
    required this.complete,
    required this.boardGames,
  });

  TeamMatchResult get result {
    if (!complete) return TeamMatchResult.ongoing;
    if (ourPoints > opponentPoints) return TeamMatchResult.win;
    if (ourPoints < opponentPoints) return TeamMatchResult.loss;
    return TeamMatchResult.draw;
  }

  int get matchPoints {
    switch (result) {
      case TeamMatchResult.win:
        return 2;
      case TeamMatchResult.draw:
        return 1;
      case TeamMatchResult.loss:
      case TeamMatchResult.ongoing:
        return 0;
    }
  }

  /// Board-point split like "5½ – 4½" (our side first).
  String get scoreLabel => '${_half(ourPoints)} – ${_half(opponentPoints)}';

  /// The team's own earned board points this match, e.g. "5" or "4½".
  String get ourPointsLabel => _half(ourPoints);

  /// Opponent board points this match, e.g. "4" or "4½".
  String get opponentPointsLabel => _half(opponentPoints);
}

/// The list of matches a team has played, most recent round first. Powers the
/// team score card (mirrors the player score card's per-game list).
List<TeamMatch> buildTeamMatches({
  required List<GamesTourModel> games,
  required String teamName,
}) {
  final target = teamName.trim();
  // Per (round, opponent) side accumulators for this team.
  final byRoundOpp = <String, _MatchSide>{};
  final oppByRoundOpp = <String, _MatchSide>{};
  final roundOf = <String, String>{};
  final slugOf = <String, String?>{};
  final oppOf = <String, String>{};
  final boardsOf = <String, List<TeamBoardGame>>{};

  for (final g in games) {
    final wTeam = g.whitePlayer.team?.trim();
    final bTeam = g.blackPlayer.team?.trim();
    if (wTeam == null || wTeam.isEmpty || bTeam == null || bTeam.isEmpty) {
      continue;
    }
    if (wTeam != target && bTeam != target) continue;

    final isWhiteOurs = wTeam == target;
    final opp = isWhiteOurs ? bTeam : wTeam;
    final key = '${g.roundId} $opp';
    roundOf[key] = g.roundId;
    slugOf[key] = g.roundSlug;
    oppOf[key] = opp;
    final ours = byRoundOpp.putIfAbsent(key, () => _MatchSide());
    final theirs = oppByRoundOpp.putIfAbsent(key, () => _MatchSide());
    ours.total++;
    theirs.total++;

    final ourCard = isWhiteOurs ? g.whitePlayer : g.blackPlayer;
    final oppCard = isWhiteOurs ? g.blackPlayer : g.whitePlayer;
    final status = g.gameStatus;
    final boardResult = _boardResultFor(status, isWhiteOurs);
    boardsOf.putIfAbsent(key, () => <TeamBoardGame>[]).add(
      TeamBoardGame(
        boardNr: g.boardNr,
        ourName: ourCard.name,
        ourTitle: ourCard.title.isNotEmpty ? ourCard.title : null,
        ourIsWhite: isWhiteOurs,
        opponentName: oppCard.name,
        opponentTitle: oppCard.title.isNotEmpty ? oppCard.title : null,
        opponentRating: oppCard.rating > 0 ? oppCard.rating : null,
        result: boardResult,
        game: g,
      ),
    );

    if (!status.isFinished) continue;
    ours.finished++;
    theirs.finished++;
    double ourPts;
    switch (status) {
      case GameStatus.whiteWins:
        ourPts = isWhiteOurs ? 1.0 : 0.0;
        break;
      case GameStatus.blackWins:
        ourPts = isWhiteOurs ? 0.0 : 1.0;
        break;
      case GameStatus.draw:
        ourPts = 0.5;
        break;
      default:
        ourPts = 0.0;
    }
    ours.points += ourPts;
    theirs.points += 1.0 - ourPts;
  }

  final matches = <TeamMatch>[];
  for (final key in byRoundOpp.keys) {
    final ours = byRoundOpp[key]!;
    final theirs = oppByRoundOpp[key]!;
    final boardGames = boardsOf[key] ?? <TeamBoardGame>[];
    boardGames.sort((a, b) => (a.boardNr ?? 1 << 30).compareTo(b.boardNr ?? 1 << 30));
    matches.add(
      TeamMatch(
        roundId: roundOf[key]!,
        roundSlug: slugOf[key],
        roundLabel: _roundLabel(slugOf[key] ?? roundOf[key]!),
        opponentTeam: oppOf[key]!,
        ourPoints: ours.points,
        opponentPoints: theirs.points,
        boards: ours.finished,
        complete: ours.total > 0 && ours.finished == ours.total,
        boardGames: boardGames,
      ),
    );
  }

  // Latest round first; unparseable round ids sink to the bottom.
  matches.sort((a, b) {
    final ar = _roundNumber(a.roundSlug ?? a.roundId);
    final br = _roundNumber(b.roundSlug ?? b.roundId);
    if (ar == null && br == null) return 0;
    if (ar == null) return 1;
    if (br == null) return -1;
    return br.compareTo(ar);
  });
  return matches;
}

/// Whether any match has a parseable round number (round robin / swiss style).
/// Knockout-style events often only have stage names, so this is false.
bool teamMatchesHaveRoundInfo(Iterable<TeamMatch> matches) {
  for (final m in matches) {
    if (_roundNumber(m.roundSlug ?? m.roundId) != null) return true;
  }
  return false;
}

/// Section heading for the team matches block on the score card / share image.
///
/// Returns `'MATCHES'` when no usable round numbers exist (e.g. team knockout).
/// Returns `null` when callers should use per-match [TeamMatch.roundLabel]
/// instead of a static heading.
String? teamMatchesSectionHeading(Iterable<TeamMatch> matches) {
  if (teamMatchesHaveRoundInfo(matches)) return null;
  return 'MATCHES';
}

/// Whether this match has a numeric round suitable for a "1." / "6." label.
bool teamMatchHasRoundNumber(TeamMatch match) =>
    _roundNumber(match.roundSlug ?? match.roundId) != null;

TeamMatchResult _boardResultFor(GameStatus status, bool ourIsWhite) {
  switch (status) {
    case GameStatus.whiteWins:
      return ourIsWhite ? TeamMatchResult.win : TeamMatchResult.loss;
    case GameStatus.blackWins:
      return ourIsWhite ? TeamMatchResult.loss : TeamMatchResult.win;
    case GameStatus.draw:
      return TeamMatchResult.draw;
    default:
      return TeamMatchResult.ongoing;
  }
}

int? _roundNumber(String roundId) {
  final m = RegExp(r'(\d+)').firstMatch(roundId);
  return m == null ? null : int.tryParse(m.group(1)!);
}

String _roundLabel(String roundId) {
  final n = _roundNumber(roundId);
  return n != null ? '$n.' : roundId;
}

String _half(double v) =>
    v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);

class _TeamAgg {
  double gamePoints = 0;
  int boardsPlayed = 0;
  int mp = 0;
  int won = 0;
  int drawn = 0;
  int lost = 0;
}

class _MatchSide {
  double points = 0; // finished-board points for this team in this match
  int finished = 0; // finished boards
  int total = 0; // present boards
}
