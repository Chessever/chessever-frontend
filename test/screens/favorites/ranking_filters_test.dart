import 'package:chessever2/screens/favorites/provider/favorites_mode_provider.dart';
import 'package:chessever2/screens/favorites/rankings/ranking_filters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rankings default to active classical overall', () {
    expect(RankingFilters.defaults.activity, RankingActivity.active);
    expect(RankingFilters.defaults.timeControl, RankingTimeControl.classical);
    expect(RankingFilters.defaults.category, RankingCategory.overall);
  });

  test('third Favorites mode is labelled Rankings', () {
    expect(favoritesModeNames[FavoritesScreenMode.players], 'Rankings');
  });

  test('time controls map to canonical chess_players rating columns', () {
    expect(RankingTimeControl.classical.ratingColumn, 'rating');
    expect(RankingTimeControl.rapid.ratingColumn, 'rapid_rating');
    expect(RankingTimeControl.blitz.ratingColumn, 'blitz_rating');
  });

  test('ranking categories expose canonical eligibility requirements', () {
    expect(RankingCategory.overall.requiresFemale, isFalse);
    expect(RankingCategory.women.requiresFemale, isTrue);
    expect(RankingCategory.juniors.requiresJunior, isTrue);
    expect(RankingCategory.girls.requiresFemale, isTrue);
    expect(RankingCategory.girls.requiresJunior, isTrue);
  });

  test('FIDE inactive flags include combined flags containing i', () {
    expect(isFideInactiveFlag(null), isFalse);
    expect(isFideInactiveFlag(''), isFalse);
    expect(isFideInactiveFlag('w'), isFalse);
    expect(isFideInactiveFlag('i'), isTrue);
    expect(isFideInactiveFlag('wi'), isTrue);
    expect(isFideInactiveFlag('I'), isTrue);
  });
}
