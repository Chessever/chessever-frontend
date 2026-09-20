import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/team_standing_model.dart';

/// A complete official snapshot takes precedence over PGN-derived standings:
/// organizer tiebreaks, byes and adjudications are absent from board feeds.
/// Reject the whole snapshot if malformed; never mix its ranks with live totals.
List<TeamStandingModel>? buildOfficialTeamStandings({
  required TourInfo? info,
  required List<PlayerStandingModel> players,
}) {
  final snapshot = info?.officialTeamStandings;
  if (snapshot == null || snapshot['source'] != 'chess-results') return null;
  final round = _integer(snapshot['round']);
  final teams = snapshot['teams'];
  final fetchedAt = snapshot['fetchedAt'];
  final event = _eventId(info?.standings);
  if (round == null ||
      round < 1 ||
      round > 100 ||
      teams is! List ||
      teams.length < 2 ||
      fetchedAt is! String ||
      DateTime.tryParse(fetchedAt) == null ||
      event == null ||
      event != _eventId(snapshot['sourceUrl'])) {
    return null;
  }

  final playersByTeam = <String, List<PlayerStandingModel>>{};
  for (final player in players) {
    final key = player.team?.trim().toLowerCase();
    if (key != null && key.isNotEmpty) {
      playersByTeam.putIfAbsent(key, () => []).add(player);
    }
  }
  final rows = <TeamStandingModel>[];
  final names = <String>{};
  var lastRank = 0;
  for (final raw in teams) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final rank = _integer(raw['rank']);
    final mp = _integer(raw['matchPoints']);
    final gp = raw['gamePoints'];
    final played = _integer(raw['matchesPlayed']);
    final wins = _integer(raw['wins']);
    final draws = _integer(raw['draws']);
    final losses = _integer(raw['losses']);
    if (name is! String ||
        name.trim().isEmpty ||
        !names.add(name.toLowerCase()) ||
        rank == null ||
        rank < 1 ||
        rank < lastRank ||
        (rank != lastRank && rank != rows.length + 1) ||
        mp == null ||
        mp < 0 ||
        mp > 2 * round ||
        gp is! num ||
        !gp.isFinite ||
        gp < 0 ||
        played == null ||
        played < 0 ||
        played > round ||
        wins == null ||
        wins < 0 ||
        draws == null ||
        draws < 0 ||
        losses == null ||
        losses < 0 ||
        played != wins + draws + losses) {
      return null;
    }
    lastRank = rank;
    rows.add(
      TeamStandingModel(
        teamName: name,
        rank: rank,
        officialRound: round,
        matchPoints: mp,
        gamePoints: gp.toDouble(),
        matchesWon: wins,
        matchesDrawn: draws,
        matchesLost: losses,
        // The source counts matches; it does not certify played boards.
        boardsPlayed: 0,
        players: playersByTeam[name.toLowerCase()] ?? const [],
      ),
    );
  }
  return rows;
}

int? _integer(dynamic value) =>
    value is num && value.isFinite && value == value.roundToDouble()
        ? value.toInt()
        : null;

String? _eventId(dynamic value) {
  if (value is! String) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      !RegExp(
        r'^(?:s[1-9]\.)?chess-results\.com$',
        caseSensitive: false,
      ).hasMatch(uri.host)) {
    return null;
  }
  return RegExp(
    r'^/tnr(\d+)\.aspx$',
    caseSensitive: false,
  ).firstMatch(uri.path)?.group(1);
}
