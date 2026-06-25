import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/chess_title_utils.dart';

/// A full event view synthesized server-side from gamebase games for events
/// that have no broadcast page in the cloud Supabase. Returned by
/// `GET /api/event` and rendered by `DatabaseEventScreen`.
class GamebaseEventView {
  const GamebaseEventView({
    required this.event,
    required this.site,
    required this.image,
    required this.format,
    required this.formatLabel,
    required this.truncated,
    required this.about,
    required this.rounds,
    required this.standings,
    required this.games,
  });

  final String event;
  final String? site;
  final String? image;

  /// 'regular' | 'team' | 'knockout'
  final String format;
  final String? formatLabel;
  final bool truncated;
  final GamebaseEventAbout about;
  final List<GamebaseEventRound> rounds;
  final GamebaseEventStandings standings;
  final List<GamebaseEventGame> games;

  bool get isTeam => format == 'team';
  bool get isKnockout => format == 'knockout';

  factory GamebaseEventView.fromData(Map<String, dynamic> data) {
    final roundsRaw = (data['rounds'] as List?) ?? const [];
    final gamesRaw = (data['games'] as List?) ?? const [];
    return GamebaseEventView(
      event: (data['event'] ?? '').toString(),
      site: _stringOrNull(data['site']),
      image: _stringOrNull(data['image']),
      format: (data['format'] ?? 'regular').toString(),
      formatLabel: _stringOrNull(data['formatLabel']),
      truncated: data['truncated'] == true,
      about: GamebaseEventAbout.fromJson(
        (data['about'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      rounds: roundsRaw
          .whereType<Map>()
          .map((r) => GamebaseEventRound.fromJson(r.cast<String, dynamic>()))
          .toList(growable: false),
      standings: GamebaseEventStandings.fromJson(
        (data['standings'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      games: gamesRaw
          .whereType<Map>()
          .map((g) => GamebaseEventGame.fromJson(g.cast<String, dynamic>()))
          .toList(growable: false),
    );
  }
}

class GamebaseEventAbout {
  const GamebaseEventAbout({
    required this.gameCount,
    required this.playerCount,
    required this.teamCount,
    required this.roundCount,
    required this.startDate,
    required this.endDate,
    required this.timeControl,
    required this.avgElo,
    required this.maxElo,
    required this.site,
    required this.image,
  });

  final int gameCount;
  final int playerCount;
  final int? teamCount;
  final int roundCount;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? timeControl;
  final int? avgElo;
  final int? maxElo;
  final String? site;
  final String? image;

  factory GamebaseEventAbout.fromJson(Map<String, dynamic> json) {
    return GamebaseEventAbout(
      gameCount: _intOrZero(json['gameCount']),
      playerCount: _intOrZero(json['playerCount']),
      teamCount: _intOrNull(json['teamCount']),
      roundCount: _intOrZero(json['roundCount']),
      startDate: _dateOrNull(json['startDate']),
      endDate: _dateOrNull(json['endDate']),
      timeControl: _stringOrNull(json['timeControl']),
      avgElo: _intOrNull(json['avgElo']),
      maxElo: _intOrNull(json['maxElo']),
      site: _stringOrNull(json['site']),
      image: _stringOrNull(json['image']),
    );
  }
}

class GamebaseEventRound {
  const GamebaseEventRound({
    required this.label,
    required this.sortKey,
    required this.date,
    required this.games,
  });

  final String label;
  final int sortKey;
  final DateTime? date;
  final List<GamebaseEventGame> games;

  /// Human label for the round header ("Round 7", or the raw label if not numeric).
  String get displayLabel {
    if (label == '?') return 'Unrated round';
    return int.tryParse(label) != null ? 'Round $label' : label;
  }

  factory GamebaseEventRound.fromJson(Map<String, dynamic> json) {
    final gamesRaw = (json['games'] as List?) ?? const [];
    return GamebaseEventRound(
      label: (json['label'] ?? '?').toString(),
      sortKey: _intOrZero(json['sortKey']),
      date: _dateOrNull(json['date']),
      games: gamesRaw
          .whereType<Map>()
          .map((g) => GamebaseEventGame.fromJson(g.cast<String, dynamic>()))
          .toList(growable: false),
    );
  }
}

class GamebaseEventGame {
  const GamebaseEventGame({
    required this.id,
    required this.round,
    required this.board,
    required this.white,
    required this.black,
    required this.result,
    required this.date,
    required this.eco,
    required this.opening,
  });

  final String id;
  final String? round;
  final int? board;
  final GamebaseEventPlayerRef white;
  final GamebaseEventPlayerRef black;
  final String result; // "1-0" | "0-1" | "1/2-1/2" | "*"
  final DateTime? date;
  final String? eco;
  final String? opening;

  factory GamebaseEventGame.fromJson(Map<String, dynamic> json) {
    return GamebaseEventGame(
      id: (json['id'] ?? '').toString(),
      round: _stringOrNull(json['round']),
      board: _intOrNull(json['board']),
      white: GamebaseEventPlayerRef.fromJson(
        (json['white'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      black: GamebaseEventPlayerRef.fromJson(
        (json['black'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      result: (json['result'] ?? '*').toString(),
      date: _dateOrNull(json['date']),
      eco: _stringOrNull(json['eco']),
      opening: _stringOrNull(json['opening']),
    );
  }

  /// Convert to a [GamesTourModel] so the standard gamebase game card can render
  /// it and open the board. The PGN is header-only on purpose — the card
  /// re-fetches the full game by [id] (gamebase UUID) on tap, exactly like
  /// gamebase search results.
  GamesTourModel toGamesTourModel({required String eventName, String? site}) {
    final status = GameStatus.fromString(result);
    final pgn = buildHeaderOnlyPgn(
      whiteName: white.name ?? 'White',
      blackName: black.name ?? 'Black',
      result: result,
      event: eventName,
      site: site,
      date: date,
      eco: eco,
      opening: opening,
    );

    return GamesTourModel(
      gameId: id,
      source: GameSource.gamebase,
      whitePlayer: white.toPlayerCard(),
      blackPlayer: black.toPlayerCard(),
      whiteTimeDisplay: '--:--',
      blackTimeDisplay: '--:--',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: status,
      roundId: 'gamebase',
      roundSlug: (eco != null && eco!.isNotEmpty) ? eco : null,
      tourId: eventName,
      tourSlug: eventName,
      boardNr: board,
      pgn: pgn,
      lastMoveTime: date,
      eco: (eco != null && eco!.isNotEmpty) ? eco : null,
      openingName: (opening != null && opening!.isNotEmpty) ? opening : null,
    );
  }
}

class GamebaseEventPlayerRef {
  const GamebaseEventPlayerRef({
    required this.name,
    required this.fideId,
    required this.title,
    required this.elo,
    required this.fed,
    required this.team,
  });

  final String? name;
  final String? fideId;
  final String? title;
  final int? elo;
  final String? fed;
  final String? team;

  factory GamebaseEventPlayerRef.fromJson(Map<String, dynamic> json) {
    return GamebaseEventPlayerRef(
      name: _stringOrNull(json['name']),
      fideId: _stringOrNull(json['fideId']),
      title: _stringOrNull(json['title']),
      elo: _intOrNull(json['elo']),
      fed: _stringOrNull(json['fed']),
      team: _stringOrNull(json['team']),
    );
  }

  PlayerCard toPlayerCard() {
    final fed = this.fed ?? '';
    return PlayerCard(
      name: name ?? 'Unknown',
      federation: fed,
      title: ChessTitleUtils.normalize((title ?? '').trim()),
      rating: elo ?? 0,
      countryCode: fed,
      team: team,
      fideId: int.tryParse(fideId ?? ''),
    );
  }
}

class GamebaseEventStandings {
  const GamebaseEventStandings({
    required this.kind,
    required this.players,
    required this.teams,
  });

  /// 'player' | 'team'
  final String kind;
  final List<GamebaseEventPlayerStanding> players;
  final List<GamebaseEventTeamStanding> teams;

  bool get isTeam => kind == 'team';

  factory GamebaseEventStandings.fromJson(Map<String, dynamic> json) {
    final playersRaw = (json['players'] as List?) ?? const [];
    final teamsRaw = (json['teams'] as List?) ?? const [];
    return GamebaseEventStandings(
      kind: (json['kind'] ?? 'player').toString(),
      players: playersRaw
          .whereType<Map>()
          .map(
            (p) =>
                GamebaseEventPlayerStanding.fromJson(p.cast<String, dynamic>()),
          )
          .toList(growable: false),
      teams: teamsRaw
          .whereType<Map>()
          .map(
            (t) =>
                GamebaseEventTeamStanding.fromJson(t.cast<String, dynamic>()),
          )
          .toList(growable: false),
    );
  }
}

class GamebaseEventPlayerStanding {
  const GamebaseEventPlayerStanding({
    required this.rank,
    required this.name,
    required this.fideId,
    required this.title,
    required this.fed,
    required this.elo,
    required this.played,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.points,
  });

  final int rank;
  final String? name;
  final String? fideId;
  final String? title;
  final String? fed;
  final int? elo;
  final int played;
  final int wins;
  final int draws;
  final int losses;
  final double points;

  factory GamebaseEventPlayerStanding.fromJson(Map<String, dynamic> json) {
    return GamebaseEventPlayerStanding(
      rank: _intOrZero(json['rank']),
      name: _stringOrNull(json['name']),
      fideId: _stringOrNull(json['fideId']),
      title: _stringOrNull(json['title']),
      fed: _stringOrNull(json['fed']),
      elo: _intOrNull(json['elo']),
      played: _intOrZero(json['played']),
      wins: _intOrZero(json['wins']),
      draws: _intOrZero(json['draws']),
      losses: _intOrZero(json['losses']),
      points: _doubleOrZero(json['points']),
    );
  }
}

class GamebaseEventTeamStanding {
  const GamebaseEventTeamStanding({
    required this.rank,
    required this.team,
    required this.played,
    required this.matchPoints,
    required this.gamePoints,
    required this.wins,
    required this.draws,
    required this.losses,
  });

  final int rank;
  final String team;
  final int played;
  final double matchPoints;
  final double gamePoints;
  final int wins;
  final int draws;
  final int losses;

  factory GamebaseEventTeamStanding.fromJson(Map<String, dynamic> json) {
    return GamebaseEventTeamStanding(
      rank: _intOrZero(json['rank']),
      team: (json['team'] ?? '').toString(),
      played: _intOrZero(json['played']),
      matchPoints: _doubleOrZero(json['matchPoints']),
      gamePoints: _doubleOrZero(json['gamePoints']),
      wins: _intOrZero(json['wins']),
      draws: _intOrZero(json['draws']),
      losses: _intOrZero(json['losses']),
    );
  }
}

// --- JSON coercion helpers ---------------------------------------------------

String? _stringOrNull(Object? value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isEmpty ? null : s;
}

int _intOrZero(Object? value) => _intOrNull(value) ?? 0;

int? _intOrNull(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

double _doubleOrZero(Object? value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

DateTime? _dateOrNull(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}
