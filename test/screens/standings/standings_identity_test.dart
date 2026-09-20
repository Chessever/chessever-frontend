import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/standings/standings_builder.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

PlayerCard card(String name, int? id, {String? team}) => PlayerCard(
  name: name,
  fideId: id,
  federation: '',
  title: '',
  rating: 0,
  countryCode: '',
  team: team,
);

GamesTourModel game(String id, PlayerCard white, PlayerCard black) =>
    GamesTourModel(
      gameId: id,
      whitePlayer: white,
      blackPlayer: black,
      whiteTimeDisplay: '',
      blackTimeDisplay: '',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: GameStatus.whiteWins,
      roundId: id,
      tourId: 'identity-regression',
    );

void main() {
  late SupabaseClient client;
  setUp(() {
    client = SupabaseClient(
      'https://example.test',
      'placeholder',
      httpClient: MockClient(
        (request) async => http.Response(
          '[]',
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
  });
  tearDown(() => client.dispose());

  test('same FIDE player keeps results across name variants', () async {
    final rows = await buildStandingsFromData(
      supabase: client,
      tournamentPlayers: const [],
      gamesTourModels: [
        game(
          'r1',
          card('Terao, Juliana Sayumi', 2109220),
          card('Opponent One', 1),
        ),
        game(
          'r2',
          card('Juliana Sayumi Terao', 2109220),
          card('Opponent Two', 2),
        ),
      ],
    );
    expect(rows.where((p) => p.fideId == 2109220), hasLength(1));
    expect(rows.singleWhere((p) => p.fideId == 2109220).matchScore, '2 / 2');
  });

  test('homonyms with different FIDE IDs do not share results', () async {
    final rows = await buildStandingsFromData(
      supabase: client,
      tournamentPlayers: const [],
      gamesTourModels: [
        game('r1', card('Same Name', 101), card('Opponent One', 1)),
        game('r2', card('Opponent Two', 2), card('Same Name', 202)),
      ],
    );
    expect(rows.singleWhere((p) => p.fideId == 101).matchScore, '1 / 1');
    expect(rows.singleWhere((p) => p.fideId == 202).matchScore, '0 / 1');
  });

  test(
    'roster ID enrichment prevents a later spelling creating a duplicate',
    () {
      final rows = mergeTournamentRosterWithGamePlayers(
        tournamentPlayers: [
          TournamentPlayer(name: 'Terao, Juliana Sayumi', played: 2),
          TournamentPlayer(
            name: 'Terao, Juliana Sayumi',
            fideId: 2109220,
            played: 2,
          ),
        ],
        gamesTourModels: [
          game(
            'r1',
            card('Juliana Sayumi Terao', 2109220),
            card('Opponent One', 1),
          ),
        ],
      );
      expect(rows, hasLength(2));
      expect(rows.where((p) => p.fideId == 2109220), hasLength(1));
    },
  );

  test('missing IDs resolve within a team regardless of input order', () async {
    final games = [
      game('r1', card('Same Name', null, team: 'A'), card('Opponent One', 1)),
      game('r2', card('Same Name', 101, team: 'A'), card('Opponent Two', 2)),
      game('r3', card('Opponent Three', 3), card('Same Name', 202, team: 'B')),
    ];
    for (final ordered in [games, games.reversed.toList()]) {
      final rows = await buildStandingsFromData(
        supabase: client,
        tournamentPlayers: const [],
        gamesTourModels: ordered,
      );
      expect(rows.where((p) => p.name == 'Same Name'), hasLength(2));
      expect(rows.singleWhere((p) => p.fideId == 101).matchScore, '2 / 2');
      expect(rows.singleWhere((p) => p.fideId == 202).matchScore, '0 / 1');
    }
  });

  test('ambiguous name is not assigned to a known homonym', () async {
    final rows = await buildStandingsFromData(
      supabase: client,
      tournamentPlayers: const [],
      gamesTourModels: [
        game('r1', card('Same Name', null), card('Opponent One', 1)),
        game('r2', card('Same Name', 101), card('Opponent Two', 2)),
        game('r3', card('Opponent Three', 3), card('Same Name', 202)),
      ],
    );
    expect(rows.singleWhere((p) => p.fideId == 101).matchScore, '1 / 1');
    expect(rows.singleWhere((p) => p.fideId == 202).matchScore, '0 / 1');
  });

  test(
    'a teamless roster cannot merge homonyms from different teams',
    () async {
      final rows = await buildStandingsFromData(
        supabase: client,
        tournamentPlayers: [
          TournamentPlayer(name: 'Same Name', fideId: 101, played: 0),
        ],
        gamesTourModels: [
          game(
            'r1',
            card('Same Name', 101, team: 'A'),
            card('Opponent One', 1),
          ),
          game(
            'r2',
            card('Opponent Two', 2),
            card('Same Name', null, team: 'B'),
          ),
        ],
      );
      expect(rows.where((p) => p.name == 'Same Name'), hasLength(2));
      expect(rows.singleWhere((p) => p.fideId == 101).matchScore, '1 / 1');
      expect(rows.singleWhere((p) => p.team == 'B').matchScore, '0 / 1');
    },
  );

  test(
    'external standings without rank numbers retain official order',
    () async {
      final rows = await buildStandingsFromData(
        supabase: client,
        useExternalOrder: true,
        tournamentPlayers: [
          TournamentPlayer(
            name: 'Official Winner',
            played: 4,
            score: 3,
            rating: 2000,
          ),
          TournamentPlayer(
            name: 'Official Second',
            played: 4,
            score: 3,
            rating: 2400,
          ),
        ],
        gamesTourModels: const [],
      );
      expect(rows.map((p) => p.name), ['Official Winner', 'Official Second']);
    },
  );

  test(
    'unidentified homonyms on different teams keep separate results',
    () async {
      final rows = await buildStandingsFromData(
        supabase: client,
        tournamentPlayers: const [],
        gamesTourModels: [
          game(
            'r1',
            card('Same Name', null, team: 'A'),
            card('Opponent One', 1),
          ),
          game(
            'r2',
            card('Opponent Two', 2),
            card('Same Name', null, team: 'B'),
          ),
        ],
      );
      expect(rows.singleWhere((p) => p.team == 'A').matchScore, '1 / 1');
      expect(rows.singleWhere((p) => p.team == 'B').matchScore, '0 / 1');
    },
  );

  test(
    'official rank and custom score remain authoritative after identity merge',
    () async {
      final rows = await buildStandingsFromData(
        supabase: client,
        tournamentPlayers: [
          TournamentPlayer(
            name: 'Official Second',
            fideId: 2,
            played: 4,
            score: 7,
            rank: 2,
          ),
          TournamentPlayer(
            name: 'Official First',
            fideId: 1,
            played: 4,
            score: 7,
            rank: 1,
          ),
        ],
        gamesTourModels: [
          game('r1', card('First Alias', 1), card('Second Alias', 2)),
        ],
      );
      expect(rows.map((p) => p.fideId), [1, 2]);
      expect(rows.map((p) => p.matchScore), ['7 / 4', '7 / 4']);
    },
  );
}
