import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:flutter_test/flutter_test.dart';

GamebaseMiniature _miniature({
  required String id,
  required DateTime date,
  int? whiteElo,
  int? blackElo,
}) {
  return GamebaseMiniature(
    gameId: id,
    avgRating: null,
    plyCount: 20,
    finalMoveNumber: 10,
    result: 'W',
    timeControl: 'CLASSICAL',
    isOnline: false,
    date: date,
    whiteElo: whiteElo,
    blackElo: blackElo,
  );
}

void main() {
  test('missing Miniatures ratings use 1800 in the effective average', () {
    final oneMissing = _miniature(
      id: 'one-missing',
      date: DateTime.utc(2026, 7, 22),
      whiteElo: 2400,
    );
    final bothMissing = _miniature(
      id: 'both-missing',
      date: DateTime.utc(2026, 7, 22),
    );

    expect(oneMissing.effectiveAverageRating, 2100);
    expect(bothMissing.effectiveAverageRating, 1800);
    expect(oneMissing.toGamesTourModel().avgElo, 2100);
    expect(bothMissing.toGamesTourModel().avgElo, 1800);
  });

  test(
    'Miniatures stay newest-day first and strongest-first within each day',
    () {
      final today = DateTime.utc(2026, 7, 22);
      final yesterday = DateTime.utc(2026, 7, 21);
      final games = <GamebaseMiniature>[
        _miniature(id: 'today-both-missing', date: today),
        _miniature(
          id: 'yesterday-strongest',
          date: yesterday,
          whiteElo: 2800,
          blackElo: 2800,
        ),
        _miniature(
          id: 'today-strongest',
          date: today,
          whiteElo: 2500,
          blackElo: 2500,
        ),
        _miniature(id: 'today-one-missing', date: today, whiteElo: 2400),
      ];

      final ordered = orderMiniaturesByDayAndAverageRating(games);

      expect(ordered.map((game) => game.gameId), <String>[
        'today-strongest',
        'today-one-missing',
        'today-both-missing',
        'yesterday-strongest',
      ]);
    },
  );
}
