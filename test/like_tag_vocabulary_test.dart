import 'package:chessever2/screens/chessboard/models/like_tag.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('game phases lead the canonical like-tag vocabulary', () {
    final labels = kLikeTags.map((tag) => tag.label).toList();

    expect(labels.take(3), ['Opening', 'Middlegame', 'Endgame']);
    expect(labels, contains('Maneuver'));
    expect(
      labels.indexOf('Maneuver'),
      greaterThan(labels.indexOf('Positional Masterpiece')),
    );
    expect(labels, hasLength(14));
    expect(labels.toSet(), hasLength(labels.length));
  });
}
