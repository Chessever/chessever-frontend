import 'package:chessever2/screens/feed/models/feed_models.dart';

// Adapted from lichess-org/scalachess Divider.scala.
// Copyright (c) 2012-2014 Thibault Duplessis
//
// The MIT license
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is furnished
// to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

/// Lichess phase boundaries, indexed like Feed: 0 is the initial position.
/// A game need not reach every phase. A direct opening-to-endgame transition
/// has no middlegame marker.
class FeedGameDivision {
  const FeedGameDivision({this.middle, this.end});

  final int? middle;
  final int? end;

  List<(int, String)> get markers => [
    if (middle != null && middle! > 0) (0, 'Opening'),
    if (middle case final at?) (at, 'Middlegame'),
    if (end case final at?) (at, 'Endgame'),
  ];

  static final _cache = Expando<FeedGameDivision>();

  static FeedGameDivision of(FeedItem item) =>
      _cache[item] ??= fromPlies(item.plies);

  static FeedGameDivision fromPlies(List<FeedPly> plies) {
    int? middle;
    int? end;
    for (var i = 0; i < plies.length; i++) {
      final board = _readBoard(plies[i].fen);
      // Invalid replay cannot establish phase boundaries.
      if (board == null) return const FeedGameDivision();
      final pieces = board.where((p) => p != null).cast<String>().toList();
      final majorsAndMinors = pieces
          .where((p) => !['p', 'k'].contains(p.toLowerCase()))
          .length;
      final whiteBackrank = board.take(8).where(_isWhite).length;
      final blackBackrank = board.skip(56).where(_isBlack).length;
      if (middle == null &&
          (majorsAndMinors <= 10 ||
              whiteBackrank < 4 ||
              blackBackrank < 4 ||
              _mixedness(board) > 150)) {
        middle = i;
      }
      if (end == null && majorsAndMinors <= 6) end = i;
    }
    if (middle == null) return const FeedGameDivision();
    return FeedGameDivision(
      middle: end == null || middle < end ? middle : null,
      end: end,
    );
  }

  /// a1..h8, matching Scalachess's bitboard rank order.
  static List<String?>? _readBoard(String fen) {
    final ranks = fen.split(' ').first.split('/');
    if (ranks.length != 8) return null;
    final board = <String?>[];
    for (final rank in ranks.reversed) {
      final start = board.length;
      for (final piece in rank.split('')) {
        final empty = int.tryParse(piece);
        if (empty != null && empty >= 1 && empty <= 8) {
          board.addAll(List<String?>.filled(empty, null));
        } else if ('pnbrqkPNBRQK'.contains(piece)) {
          board.add(piece);
        } else {
          return null;
        }
      }
      if (board.length - start != 8) return null;
    }
    return board;
  }

  static bool _isWhite(String? p) => p != null && p == p.toUpperCase();
  static bool _isBlack(String? p) => p != null && p == p.toLowerCase();

  static int _mixedness(List<String?> board) {
    var total = 0;
    for (var rank = 0; rank < 7; rank++) {
      for (var file = 0; file < 7; file++) {
        final region = [
          board[rank * 8 + file],
          board[rank * 8 + file + 1],
          board[(rank + 1) * 8 + file],
          board[(rank + 1) * 8 + file + 1],
        ];
        total += _score(
          rank + 1,
          region.where(_isWhite).length,
          region.where(_isBlack).length,
        );
      }
    }
    return total;
  }

  static int _score(int y, int white, int black) => switch ((white, black)) {
    (0, 1) => 1 + y,
    (0, 2) => y < 6 ? 8 - y : 0,
    (0, 3) || (0, 4) => y < 7 ? 10 - y : 0,
    (1, 0) => 9 - y,
    (1, 1) => 5 + (4 - y).abs(),
    (1, 2) => 11 - y,
    (1, 3) => 12 - y,
    (2, 0) => y > 2 ? y : 0,
    (2, 1) => 3 + y,
    (2, 2) => 7,
    (3, 0) || (4, 0) => y > 1 ? 2 + y : 0,
    (3, 1) => 4 + y,
    _ => 0,
  };
}
