// Miniature rows come off `/api/miniatures`, which returns metadata only — no
// FEN, no moves. The card path therefore has exactly one way to reach the final
// position: the Gamebase preview fetch, which is gated on the row's round-id
// marker. These tests pin that contract (Trello #1013 — miniature cards were
// stuck on the start position, so their eval bars rated the start position).
import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/screens/chessboard/utils/gamebase_preview_game.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/live_game_position_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

GamebaseMiniature _miniature() {
  return GamebaseMiniature.fromJson(<String, dynamic>{
    'gameId': '41082016-ec4f-5e69-a9b7-b320e6b9b017',
    'avgRating': 3236,
    'plyCount': 43,
    'finalMoveNumber': 22,
    'result': 'W',
    'timeControl': 'BLITZ',
    'isOnline': false,
    'date': '2025-11-14T00:00:00.000Z',
    'event': '2025 Speed Chess Championship',
    'whiteName': 'Lazavik, Denis',
    'blackName': 'Niemann, Hans Moke',
    'whiteElo': 3239,
    'blackElo': 3233,
  });
}

void main() {
  test('a miniature row carries no position of its own', () {
    final game = _miniature().toGamesTourModel();

    expect(game.fen, isNull);
    expect(game.lastMove, isNull);
    expect(pgnHasMoves(game.pgn), isFalse);
    expect(
      resolveFreshestGameFen(
        fen: game.fen,
        pgn: game.pgn,
        lastMove: game.lastMove,
      ),
      isNull,
      reason: 'nothing on the model resolves to the final position',
    );
  });

  // Trello #1228: the index stores a broadcast game's PGN `Event` verbatim,
  // which Lichess fills with the pairing. Row copied from production.
  test('a pairing label never becomes the miniature\'s event', () {
    final game = GamebaseMiniature.fromJson(<String, dynamic>{
      'gameId': '018a297a-b637-59a2-b2be-b77c77735812',
      'plyCount': 49,
      'finalMoveNumber': 25,
      'result': 'B',
      'timeControl': 'CLASSICAL',
      'isOnline': false,
      'date': '2026-10-12T00:00:00.000Z',
      'event': 'Round 6: Del Rio Baena, Dani - Garcia Canals, Gerard',
      'whiteName': 'Del Rio Baena, Dani',
      'blackName': 'Garcia Canals, Gerard',
    }).toGamesTourModel();

    expect(game.tourId, 'Miniatures');
    expect(game.tourSlug, 'Miniatures');
    expect(game.pgn, isNot(contains('Round 6')));
  });

  test('a real event name reaches the card untouched', () {
    final game = _miniature().toGamesTourModel();

    expect(game.tourId, '2025 Speed Chess Championship');
  });

  test('miniature cards are eligible for the Gamebase preview fetch', () {
    expect(isGamebasePreviewGame(_miniature().toGamesTourModel()), isTrue);
  });

  test('the other archive markers stay eligible', () {
    final base = _miniature().toGamesTourModel();
    for (final marker in const [
      'gamebase_search',
      'twic_profile',
      'twic_event',
    ]) {
      expect(
        isGamebasePreviewGame(base.copyWith(roundId: marker)),
        isTrue,
        reason: marker,
      );
    }
  });

  test('broadcast rounds are not preview games', () {
    final base = _miniature().toGamesTourModel();
    expect(isGamebasePreviewGame(base.copyWith(roundId: 'mrqvQ9VS')), isFalse);
  });
}
