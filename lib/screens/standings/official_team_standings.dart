import 'package:chessever2/repository/supabase/tour/published_tiebreak.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/team_standing_model.dart';

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
  if (snapshot == null || snapshot['source'] != 'chess-results') return null;
  final round = _integer(snapshot['round']);
  final teams = snapshot['teams'];
  final fetchedAt = snapshot['fetchedAt'];
  final event = _eventId(standingsUrl);
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

  final playersByTeam = <String, List<PlayerStandingModel>>{};
  for (final player in players) {
    final key = player.team?.trim().toLowerCase();
    if (key != null && key.isNotEmpty) {
      playersByTeam.putIfAbsent(key, () => []).add(player);
    }
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
        players: playersByTeam[name.trim().toLowerCase()] ?? const [],
      ),
    );
  }
  return rows;
}

num? _points(dynamic value) => value is num && value.isFinite && value >= 0
    ? (value % 1 == 0 ? value.toInt() : value)
    : null;

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
