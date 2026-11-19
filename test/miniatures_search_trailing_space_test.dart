import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/screens/library/miniatures_screen.dart';
import 'package:chessever2/screens/library/providers/miniatures_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
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

class _IdlePlayers extends StateNotifier<MiniaturePlayersState>
    implements MiniaturePlayersNotifier {
  _IdlePlayers() : super(const MiniaturePlayersState(hasMore: false));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Frames enough for the search's spring to land; the search's own progress
/// line runs forever, so never pumpAndSettle while a read is out.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
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
          miniaturePlayersPaginatedProvider.overrideWith(
            (ref) => _IdlePlayers(),
          ),
          spaceShortcutExistsProvider.overrideWith((ref, key) => false),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return const MiniaturesScreen();
            },
          ),
        ),
      ),
    );
    await _frames(tester);

    // The search opens from the floating button, in the header's place.
    await tester.tap(find.byKey(const ValueKey('miniatures_search_fab')));
    await _frames(tester);
    final field = find.byKey(const ValueKey('miniatures_games_search'));
    expect(field, findsOneWidget);

    await tester.enterText(field, 'carlsen');
    await tester.pump(const Duration(milliseconds: 400));
    await _frames(tester);
    expect(repo.searches, contains('carlsen'));
    final fetched = repo.searches.length;

    await tester.enterText(field, 'carlsen ');
    await tester.pump(const Duration(milliseconds: 400));
    await _frames(tester);

    expect(repo.searches.length, fetched);

    // Closing clears what was searched: the full list is read again.
    await tester.tap(find.byKey(const ValueKey('miniatures_search_close')));
    await _frames(tester);
    expect(field, findsNothing);
    expect(repo.searches.last, isNull);
    expect(tester.takeException(), isNull);
  });
}
