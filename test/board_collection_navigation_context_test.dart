import 'dart:io';

import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('collection board views explicitly preserve their navigation list', () {
    expect(ChessboardView.favorites.preservesNavigationCollection, isTrue);
    expect(ChessboardView.countryman.preservesNavigationCollection, isTrue);
    expect(ChessboardView.smartEvent.preservesNavigationCollection, isTrue);

    expect(ChessboardView.forYou.preservesNavigationCollection, isFalse);
    expect(ChessboardView.tour.preservesNavigationCollection, isFalse);

    expect(ChessboardView.forYou.usesNavigationGamesAsPrimarySource, isTrue);
    expect(ChessboardView.favorites.usesNavigationGamesAsPrimarySource, isTrue);
    expect(
      ChessboardView.smartEvent.usesNavigationGamesAsPrimarySource,
      isTrue,
    );
    expect(
      ChessboardView.countryman.usesNavigationGamesAsPrimarySource,
      isFalse,
    );

    expect(ChessboardView.forYou.usesEventScopedScorecardContext, isTrue);
    expect(ChessboardView.favorites.usesEventScopedScorecardContext, isTrue);
    expect(ChessboardView.smartEvent.usesEventScopedScorecardContext, isFalse);
  });

  test('Favorites and Smart Events pass their dedicated board contexts', () {
    final favoritesSource =
        File(
          'lib/screens/favorites/tabs/favorites_games_tab.dart',
        ).readAsStringSync();
    final smartEventSource =
        File(
          'lib/screens/group_event/smart_event/smart_event_screen.dart',
        ).readAsStringSync();

    expect(
      RegExp(
        r'viewSource:\s*ChessboardView\.favorites',
      ).allMatches(favoritesSource),
      hasLength(1),
    );
    expect(
      favoritesSource,
      isNot(contains('viewSource: ChessboardView.forYou')),
    );

    expect(
      RegExp(
        r'viewSource:\s*ChessboardView\.smartEvent',
      ).allMatches(smartEventSource),
      hasLength(2),
    );
    expect(
      smartEventSource,
      isNot(contains('viewSource: ChessboardView.tour')),
    );
  });
}
