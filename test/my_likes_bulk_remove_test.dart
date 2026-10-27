import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/my_likes/my_likes_screen.dart';
import 'package:chessever2/screens/my_likes/provider/my_likes_provider.dart';
import 'package:chessever2/screens/my_likes/widgets/my_likes_selectable_card.dart';
import 'package:chessever2/screens/my_likes/widgets/my_likes_selection_bar.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _pgn = '''
[Event "Test"]
[Site "?"]
[Date "2026.01.01"]
[Round "1"]
[White "White"]
[Black "Black"]
[Result "1-0"]

1. e4 e5 1-0
''';

final _base = DateTime.utc(2026, 9, 1, 12);

SavedAnalysis _like(int n) {
  final at = _base.add(Duration(minutes: n));
  return SavedAnalysis(
    id: 'like-${n.toString().padLeft(3, '0')}',
    userId: 'user-1',
    folderId: 'liked-folder',
    title: 'Game $n',
    sourceGameId: 'game-$n',
    chessGame: ChessGame.fromPgn('game-$n', _pgn),
    analysisState: const {},
    variationComments: const {},
    lastViewedPosition: -1,
    tags: const [],
    isFavorite: false,
    createdAt: at,
    updatedAt: at,
  );
}

List<SavedAnalysis> _likes(int count) => [
  for (var n = count; n >= 1; n--) _like(n),
];

class _Likes extends LikedGamesNotifier {
  _Likes(this.seed);

  final List<SavedAnalysis> seed;
  final List<List<String>> removed = <List<String>>[];

  @override
  Future<List<SavedAnalysis>> build() async => seed;

  @override
  Future<bool> removeAnalyses(Iterable<SavedAnalysis> analyses) async {
    final ids = [for (final a in analyses) a.id]..sort();
    removed.add(ids);
    state = AsyncValue.data([
      for (final a in state.valueOrNull ?? const <SavedAnalysis>[])
        if (!ids.contains(a.id)) a,
    ]);
    return true;
  }
}

class _NoShortcuts extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];
}

Future<_Likes> _pump(
  WidgetTester tester, {
  required List<SavedAnalysis> likes,
  Set<String>? window,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final notifier = _Likes(likes);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        likedGamesProvider.overrideWith(() => notifier),
        myLikesViewProvider.overrideWith((ref) async {
          final current = await ref.watch(likedGamesProvider.future);
          return buildMyLikesData(
            matches: current,
            totalLiked: current.length,
            window: window == null
                ? null
                : {
                    for (final id in window)
                      if (current.any((a) => a.id == id)) id,
                  },
          );
        }),
        myLikesTagCountsProvider.overrideWith((ref) async => const {}),
        spaceShortcutsProvider.overrideWith(_NoShortcuts.new),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: const MyLikesScreen(),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return notifier;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

final _toggle = find.byKey(const ValueKey('my_likes_select_toggle'));
final _selectAll = find.byKey(const ValueKey('my_likes_select_all'));
final _remove = find.byKey(const ValueKey('my_likes_remove_selected'));

void main() {
  testWidgets('choose likes, confirm, and only those leave', (tester) async {
    final likes = _likes(3);
    final notifier = await _pump(tester, likes: likes);

    expect(find.byType(MyLikesSelectionBar), findsNothing);
    await tester.tap(_toggle);
    await tester.pump();
    expect(find.byType(MyLikesSelectionBar), findsOneWidget);
    expect(find.text('None selected'), findsOneWidget);
    expect(find.byType(MyLikesSelectableCard), findsNWidgets(3));

    // Nothing chosen: Remove does nothing.
    await tester.tap(_remove);
    await _settle(tester);
    expect(find.text('Remove 1 like?'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mylikes_select_like-003')));
    await tester.tap(find.byKey(const ValueKey('mylikes_select_like-001')));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    // A second tap un-chooses.
    await tester.tap(find.byKey(const ValueKey('mylikes_select_like-001')));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mylikes_select_like-002')));
    await tester.pump();

    await tester.tap(_remove);
    await _settle(tester);
    expect(find.text('Remove 2 likes?'), findsOneWidget);
    expect(
      find.text("These 2 games will leave My Likes. This can't be undone."),
      findsOneWidget,
    );

    // Cancel keeps everything.
    await tester.tap(find.text('Cancel'));
    await _settle(tester);
    expect(notifier.removed, isEmpty);
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(_remove);
    await _settle(tester);
    await tester.tap(find.text('Remove').last);
    await _settle(tester);

    expect(notifier.removed, [
      ['like-002', 'like-003'],
    ]);
    // Selection ends; the kept like is back to a normal card.
    expect(find.byType(MyLikesSelectionBar), findsNothing);
    expect(find.byType(MyLikesSelectableCard), findsNothing);
    expect(find.text('Removed 2 likes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('select all reaches the archived likes too, and says so', (
    tester,
  ) async {
    final likes = _likes(25);
    final notifier = await _pump(
      tester,
      likes: likes,
      window: freeVisibleLikeIds(likes),
    );

    await tester.tap(_toggle);
    await tester.pump();
    await tester.tap(_selectAll);
    await tester.pump();
    expect(find.text('25 selected'), findsOneWidget);
    expect(find.text('Deselect all'), findsOneWidget);

    await tester.tap(_remove);
    await _settle(tester);
    expect(find.text('Remove all likes?'), findsOneWidget);
    expect(
      find.text(
        'These 25 games will leave My Likes. This includes 5 older likes '
        "kept past your free window. This can't be undone.",
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Remove all'));
    await _settle(tester);

    expect(notifier.removed.single, hasLength(25));
    expect(find.text('No likes yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deselect all clears, and the toggle leaves selection', (
    tester,
  ) async {
    await _pump(tester, likes: _likes(3));
    await tester.tap(_toggle);
    await tester.pump();
    await tester.tap(_selectAll);
    await tester.pump();
    expect(find.text('3 selected'), findsOneWidget);
    await tester.tap(_selectAll);
    await tester.pump();
    expect(find.text('None selected'), findsOneWidget);

    await tester.tap(_toggle);
    await tester.pump();
    expect(find.byType(MyLikesSelectionBar), findsNothing);
    expect(find.byType(MyLikesSelectableCard), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
