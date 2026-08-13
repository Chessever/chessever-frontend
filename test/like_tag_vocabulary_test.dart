import 'package:chessever2/screens/chessboard/models/like_tag.dart';
import 'package:flutter_test/flutter_test.dart';

/// The tag vocabulary is a persisted, cross-user taxonomy: labels are written
/// verbatim into `user_saved_analyses.tags`, and order drives every picker and
/// filter row. These pin the contract so a future addition can't quietly
/// reshuffle stored data or collapse two tags into one look.
void main() {
  test('game phases lead the canonical vocabulary', () {
    final labels = kLikeTags.map((tag) => tag.label).toList();

    expect(labels.take(3), ['Opening', 'Middlegame', 'Endgame']);
    expect(
      labels.indexOf('Maneuver'),
      labels.indexOf('Positional Masterpiece') + 1,
    );
    expect(labels, hasLength(14));
    expect(labels.toSet(), hasLength(labels.length));
  });

  test('every tag is visually distinct', () {
    // Colour and glyph are the secondary encoding on library card pills, the
    // filter chips and the AppBar chip face — two tags sharing either one read
    // as the same tag when they sit side by side.
    final colors = kLikeTags.map((tag) => tag.color.toARGB32()).toList();
    expect(colors.toSet(), hasLength(colors.length));

    final icons = kLikeTags.map((tag) => tag.icon.codePoint).toList();
    expect(icons.toSet(), hasLength(icons.length));
  });

  test('added tags stay resolvable and legacy labels stay tolerated', () {
    for (final label in ['Opening', 'Middlegame', 'Endgame', 'Maneuver']) {
      expect(likeTagByLabel(label)?.label, label);
    }
    // Unknown labels from older likes must survive untouched, not be dropped.
    expect(likeTagByLabel('Some Retired Tag'), isNull);
    expect(normalizeLikeTagLabels(['Some Retired Tag', 'Opening', 'Opening']), [
      'Some Retired Tag',
      'Opening',
    ]);
  });
}
