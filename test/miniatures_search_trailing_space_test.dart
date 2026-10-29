import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_games_tab.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _CountingRepo extends GamebaseRepository {
  _CountingRepo() : super(Dio(), apiKey: 'test');

  final searches = <String?>[];

  @override
  Future<GamebaseMiniaturesPage> getMiniatures({
    MiniatureGamesFilter filter = MiniatureGamesFilter.defaultFilter,
    int limit = 50,
    int offset = 0,
  }) async {
    searches.add(filter.search);
    return GamebaseMiniaturesPage(
      items: const [],
      total: 0,
      limit: limit,
      offset: offset,
    );
  }
}

// Miniatures: search "carlsen", then add a trailing space. That used to
// rebuild the filter, recreate the list and refetch behind a skeleton.
void main() {
  testWidgets('a trailing space does not refetch Miniatures games', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = _CountingRepo();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gamebaseRepositoryProvider.overrideWithValue(repo),
          gamesListViewModeProvider.overrideWithValue(
            GamesListViewMode.gamesCard,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: MiniaturesGamesTab(now: DateTime.utc(2026, 10, 29)),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final field = find.byType(TextField).first;
    await tester.enterText(field, 'carlsen');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(repo.searches, contains('carlsen'));
    final fetched = repo.searches.length;

    await tester.enterText(field, 'carlsen ');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(repo.searches.length, fetched);
  });
}
