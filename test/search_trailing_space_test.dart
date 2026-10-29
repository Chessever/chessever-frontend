import 'package:chessever2/repository/gamebase/collections/collection_search_query.dart';
import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/screens/my_likes/provider/my_likes_provider.dart';
import 'package:flutter_test/flutter_test.dart';

// A trailing space is not a new search: each surface below used to treat it as
// one and reload (Collections jumped to the top, Miniatures re-skeletoned, My
// Likes re-ran its queries).
void main() {
  test('collection query text is trimmed, so a trailing space is equal', () {
    const base = CollectionSearchQuery(eco: 'B90');
    final typed = base.withText('sicilian');
    final spaced = base.withText('sicilian ');

    expect(spaced.text, 'sicilian');
    expect(spaced, typed);
    expect(spaced.hashCode, typed.hashCode);
  });

  test('miniatures filter rebuilt with the same search compares equal', () {
    // The search screens trim before copyWith and skip the write when equal.
    final current = MiniatureGamesFilter.defaultFilter.copyWith(
      search: 'carlsen',
    );

    expect(current.copyWith(search: 'carlsen'), current);
    expect(current.copyWith(search: 'carlsen'), isNot(same(current)));
  });

  test('my likes ignores a search that only adds whitespace', () {
    final notifier = MyLikesFilterNotifier();
    addTearDown(notifier.dispose);

    notifier.searchGames('carlsen');
    final afterFirst = notifier.state;
    expect(afterFirst.searchQuery, 'carlsen');

    notifier.searchGames('carlsen ');
    expect(identical(notifier.state, afterFirst), isTrue);

    notifier.clearSearch();
    expect(notifier.state.searchQuery, '');
  });
}
