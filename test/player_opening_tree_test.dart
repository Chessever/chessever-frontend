import 'package:chessever2/screens/gamebase/services/player_opening_tree.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps backend tree snapshot moves by FEN key', () {
    final index = PlayerOpeningTreeIndex.fromSnapshot(
      PlayerOpeningTreeSnapshot.fromJson(_snapshotJson()),
    );

    final moves = index.movesForFen(Chess.initial.fen);

    expect(index.positionCount, 1);
    expect(moves, hasLength(2));
    expect(moves.first.uci, 'd2d4');
    expect(moves.first.white, 8);
    expect(moves.first.black, 3);
    expect(moves.first.draws, 4);
    expect(moves.first.total, 15);
    expect(moves.first.gameId, isNull);
    expect(moves.first.lastPlayed, DateTime.parse('2026-05-21'));
  });

  test('filters supported compact backend buckets locally', () {
    final index = PlayerOpeningTreeIndex.fromSnapshot(
      PlayerOpeningTreeSnapshot.fromJson(_snapshotJson()),
    );

    final moves = index.movesForFen(
      Chess.initial.fen,
      filters: const PlayerOpeningTreeFilterCriteria(
        playerId: 'player-uuid',
        color: 'white',
        timeControl: TimeControl.blitz,
        isOnline: true,
      ),
    );

    expect(moves, hasLength(1));
    expect(moves.single.uci, 'e2e4');
    expect(moves.single.white, 3);
    expect(moves.single.black, 0);
    expect(moves.single.draws, 0);
    expect(moves.single.total, 3);
  });

  test('returns no moves for positions missing from backend snapshot', () {
    final index = PlayerOpeningTreeIndex.fromSnapshot(
      PlayerOpeningTreeSnapshot.fromJson(_snapshotJson()),
    );

    expect(index.movesForFen('8/8/8/8/8/8/8/8 w - - 0 1'), isEmpty);
  });
}

Map<String, dynamic> _snapshotJson() {
  return {
    'tid': 'v4:player-uuid:24',
    'pid': 'player-uuid',
    'mp': 24,
    'r': 0,
    'g': '2026-06-12T00:00:00.000Z',
    'fk': ['rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -'],
    'n': [
      {
        'id': 0,
        'f': 0,
        'p': 0,
        'm': [
          {
            'u': 'e2e4',
            'c': 1,
            'w': 6,
            'b': 2,
            'd': 2,
            't': 10,
            'lp': '2026-05-20',
            'fb': [
              ['w', 'b', 1, 3, 3, 0, 0],
              ['b', 'r', 0, 2, 0, 2, 0],
            ],
          },
          {
            'u': 'd2d4',
            'c': 2,
            'w': 8,
            'b': 3,
            'd': 4,
            't': 15,
            'lp': '2026-05-21',
            'fb': [
              ['w', 'c', 0, 4, 0, 0, 4],
            ],
          },
        ],
      },
    ],
  };
}
