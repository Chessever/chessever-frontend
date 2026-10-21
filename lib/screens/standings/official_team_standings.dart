import 'package:chessever2/repository/supabase/tour/published_tiebreak.dart';
import 'package:chessever2/repository/supabase/tour/info64_source.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/standings/official_team_feed_link.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/team_standing_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';

/// A complete official snapshot takes precedence over PGN-derived standings:
/// organizer tiebreaks, byes and adjudications are absent from board feeds.
/// Reject the whole snapshot if malformed; never mix its ranks with live totals.
List<TeamStandingModel>? buildOfficialTeamStandings({
  required TourInfo? info,
  required List<PlayerStandingModel> players,
  String? selectedSectionId,
}) {
  final snapshot = info?.officialTeamStandings;
  final sections = snapshot?['sections'];
  if (sections != null) {
    if (snapshot?['source'] != 'chess-results' ||
        _eventId(snapshot?['sourceUrl']) != _eventId(info?.standings)) {
      return null;
    }
    if (sections is! List || sections.length < 2 || sections.length > 32) {
      return null;
    }
    final definitions = info?.playerStandingSections ?? const [];
    if (definitions.length != sections.length) return null;
    final ids = <String>{};
    List<TeamStandingModel>? selected;
    List<TeamStandingModel>? first;
    for (final raw in sections) {
      if (raw is! Map || raw['id'] is! String || !ids.add(raw['id'])) {
        return null;
      }
      final matches = definitions.where((s) => s.id == raw['id']).toList();
      if (matches.length != 1 ||
          matches.single.name != raw['name'] ||
          _eventId(matches.single.sourceUrl) != _eventId(raw['sourceUrl'])) {
        return null;
      }
      final rows = _buildOfficialTeamSnapshot(
        Map<String, dynamic>.from(raw),
        matches.single.sourceUrl,
        matches.single.players.map(PlayerStandingModel.fromPlayer).toList(),
      );
      if (rows == null) return null;
      first ??= rows;
      if (raw['id'] == selectedSectionId) selected = rows;
    }
    return selected ?? first;
  }
  return _buildOfficialTeamSnapshot(snapshot, info?.standings, players);
}

List<TeamStandingModel>? _buildOfficialTeamSnapshot(
  Map<String, dynamic>? snapshot,
  String? standingsUrl,
  List<PlayerStandingModel> players,
) {
  if (snapshot == null ||
      !['chess-results', 'info64'].contains(snapshot['source'])) {
    return null;
  }
  final round = _integer(snapshot['round']);
  final teams = snapshot['teams'];
  final fetchedAt = snapshot['fetchedAt'];
  final event = _eventId(standingsUrl, source: snapshot['source']);
  if (round == null ||
      round < 1 ||
      round > 100 ||
      teams is! List ||
      teams.length < 2 ||
      fetchedAt is! String ||
      DateTime.tryParse(fetchedAt) == null ||
      event == null ||
      event != _eventId(snapshot['sourceUrl'], source: snapshot['source'])) {
    return null;
  }

  // Older snapshots used 2/1/0. New snapshots carry the organizer's scale.
  final scoring = snapshot['matchScoring'];
  final winPoints = scoring == null
      ? 2
      : scoring is Map
      ? _points(scoring['win'])
      : null;
  final drawPoints = scoring == null
      ? 1
      : scoring is Map
      ? _points(scoring['draw'])
      : null;
  final lossPoints = scoring == null
      ? 0
      : scoring is Map
      ? _points(scoring['loss'])
      : null;
  if (winPoints == null ||
      drawPoints == null ||
      lossPoints == null ||
      winPoints <= drawPoints ||
      drawPoints < lossPoints ||
      lossPoints < 0) {
    return null;
  }

  final rows = <TeamStandingModel>[];
  final names = <String>{};
  // Published knockout ranks can skip places; preserve their order rather
  // than impose competition-ranking ordinals on the organizer table.
  var lastRank = 0;
  for (final raw in teams) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final rank = _integer(raw['rank']);
    final mp = _points(raw['matchPoints']);
    final gp = raw['gamePoints'];
    final played = _integer(raw['matchesPlayed']);
    final wins = _integer(raw['wins']);
    final draws = _integer(raw['draws']);
    final losses = _integer(raw['losses']);
    if (name is! String ||
        name.trim().isEmpty ||
        !names.add(name.trim().toLowerCase()) ||
        rank == null ||
        rank < 1 ||
        rank < lastRank ||
        (rows.isEmpty && rank != 1) ||
        rank > teams.length ||
        mp == null ||
        mp < 0 ||
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
        tiebreaks: PublishedTiebreak.parse(raw['tiebreaks']),
        matchPoints: mp,
        gamePoints: gp.toDouble(),
        matchesWon: wins,
        matchesDrawn: draws,
        matchesLost: losses,
        // The source counts matches; it does not certify played boards.
        boardsPlayed: 0,
        players: const [],
      ),
    );
  }
  return _attachFeedTeams(rows, teams.cast<Map>(), players);
}

/// Fills each official row's players and [TeamStandingModel.feedLink] from
/// the broadcast roster, whose labels can differ from the organizer's names.
List<TeamStandingModel> _attachFeedTeams(
  List<TeamStandingModel> rows,
  List<Map> raw,
  List<PlayerStandingModel> players,
) {
  final links = linkOfficialTeamsToFeed(
    official: [
      for (var i = 0; i < rows.length; i++)
        (
          name: rows[i].teamName,
          members: officialTeamMembers(raw[i]['members']),
        ),
    ],
    feedPlayers: [
      for (final p in players) (team: p.team, fideId: p.fideId, name: p.name),
    ],
  );
  return [
    for (final row in rows)
      TeamStandingModel(
        teamName: row.teamName,
        rank: row.rank,
        officialRound: row.officialRound,
        tiebreaks: row.tiebreaks,
        matchPoints: row.matchPoints,
        gamePoints: row.gamePoints,
        matchesWon: row.matchesWon,
        matchesDrawn: row.matchesDrawn,
        matchesLost: row.matchesLost,
        boardsPlayed: row.boardsPlayed,
        feedLink: links[row.teamName],
        players: [
          for (final p in players)
            if (links[row.teamName]?.includes(
                  team: p.team,
                  fideId: p.fideId,
                  name: p.name,
                ) ??
                false)
              p,
        ],
      ),
  ];
}

/// Names a board's opponent by its official row when exactly one row's
/// [TeamStandingModel.feedLink] claims that player; otherwise null, and the
/// caller keeps the broadcast label.
String? Function(PlayerCard opponent)? officialTeamOpponentNamer(
  List<TeamStandingModel>? standings,
) {
  final linked = [
    for (final t in standings ?? const <TeamStandingModel>[])
      if (t.feedLink != null) t,
  ];
  if (linked.isEmpty) return null;
  return (card) {
    String? hit;
    for (final t in linked) {
      if (!t.feedLink!.includes(
        team: card.team,
        fideId: card.fideId,
        name: card.name,
      )) {
        continue;
      }
      if (hit != null) return null;
      hit = t.teamName;
    }
    return hit;
  };
}

num? _points(dynamic value) => value is num && value.isFinite && value >= 0
    ? (value % 1 == 0 ? value.toInt() : value)
    : null;

int? _integer(dynamic value) =>
    value is num && value.isFinite && value == value.roundToDouble()
    ? value.toInt()
    : null;

String? _eventId(dynamic value, {dynamic source = 'chess-results'}) {
  if (source == 'info64') return info64EventUrl(value, team: true);
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
