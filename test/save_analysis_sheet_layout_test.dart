import 'dart:async';

import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/chessboard/widgets/save_analysis_sheet.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  for (final size in [const Size(320, 568), const Size(393, 852)]) {
    testWidgets('actions are visible without scrolling at $size', (
      tester,
    ) async {
      await _open(tester, size: size);
      expect(find.text('Opening'), findsNothing);
      _expectVisibleActions(tester);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );

      // The first destination is immediately reachable with tags collapsed.
      await tester.tap(find.text('Database 0'));
      await tester.pumpAndSettle();
      expect(find.text('Save Analysis'), findsNWidgets(2));
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      _expectVisibleActions(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(FilledButton), findsNothing);
    });
  }

  testWidgets('expanded tags and details never scroll actions away', (
    tester,
  ) async {
    await _open(tester, size: const Size(320, 568));
    final initial = tester.getRect(find.byType(FilledButton));
    await tester.tap(find.text('Tags'));
    await tester.pumpAndSettle();
    expect(find.text('Opening'), findsOneWidget);
    _expectVisibleActions(tester);
    expect(tester.getRect(find.byType(FilledButton)), initial);

    await tester.tap(find.text('Opening'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.text('Tags'));
    await tester.pumpAndSettle();
    expect(find.text('Opening'), findsNothing);
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.text('Game Details'));
    await tester.pumpAndSettle();
    _expectVisibleActions(tester);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    _expectVisibleActions(tester);
    expect(tester.getRect(find.byType(FilledButton)), initial);
    expect(tester.takeException(), isNull);
  });

  testWidgets('actions stay above keyboard while naming a database', (
    tester,
  ) async {
    await _open(tester, size: const Size(393, 852));
    await tester.tap(find.text('New Database'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Study');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    _expectVisibleActions(tester, keyboard: 300);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
    testWidgets(
      'action labels fit at larger text sizes in ${theme.brightness}',
      (tester) async {
        await _open(
          tester,
          size: const Size(320, 568),
          textScale: 1.8,
          theme: theme,
          initialTags: const ['Opening', 'Endgame'],
        );
        expect(find.text('2 selected'), findsOneWidget);
        expect(find.text('Opening'), findsNothing);
        _expectVisibleActions(tester);
        final button = tester.getRect(find.byType(FilledButton));
        final label = tester.getRect(find.text('Select a Database'));
        expect(button.contains(label.topLeft), isTrue);
        expect(button.contains(label.bottomRight), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

void _expectVisibleActions(WidgetTester tester, {double keyboard = 0}) {
  final height = tester.view.physicalSize.height;
  final safeBottom = keyboard > 0 ? 0 : tester.view.padding.bottom;
  for (final finder in [
    find.byType(FilledButton),
    find.widgetWithText(TextButton, 'Cancel'),
  ]) {
    final rect = tester.getRect(finder);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(height - keyboard - safeBottom));
    expect(rect.height, greaterThanOrEqualTo(44));
    expect(finder.hitTestable(), findsOneWidget);
  }
}

Future<void> _open(
  WidgetTester tester, {
  required Size size,
  double textScale = 1,
  ThemeData? theme,
  List<String> initialTags = const [],
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 44, bottom: 34);
  addTearDown(tester.view.reset);

  final game = GamesTourModel(
    gameId: 'layout-game',
    source: GameSource.localAnalysis,
    whitePlayer: _player('White'),
    blackPlayer: _player('Black'),
    whiteTimeDisplay: '',
    blackTimeDisplay: '',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.unknown,
    roundId: '',
    tourId: '',
  );
  final state = ChessBoardStateNew(game: game);
  final params = ChessBoardProviderParams(game: game, index: 0);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chessBoardScreenProviderNew(
          params,
        ).overrideWith((ref) => _Board(state)),
        likedGamesProvider.overrideWith(_NoLikes.new),
        likedGamePendingTagsProvider(game.likeId).overrideWith(
          (ref) => initialTags,
        ),
        libraryRepositoryProvider.overrideWithValue(_Library()),
        folderAnalysisCountProvider.overrideWith((ref, folderId) async => 1),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.darkTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: TextButton(
                onPressed: () => unawaited(
                  showSaveAnalysisSheet(
                    context: context,
                    state: state,
                    params: params,
                  ),
                ),
                child: const Text('Open'),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

PlayerCard _player(String name) => PlayerCard(
  name: name,
  federation: '',
  title: '',
  rating: 0,
  countryCode: '',
  team: null,
);

class _Board extends StateNotifier<AsyncValue<ChessBoardStateNew>>
    implements ChessBoardScreenNotifierNew {
  _Board(ChessBoardStateNew initial) : super(AsyncData(initial));

  @override
  SavedAnalysisData? get savedAnalysisData => null;

  @override
  void updateSavedAnalysisTagsSnapshot(List<String> tags) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoLikes extends LikedGamesNotifier {
  @override
  Future<List<SavedAnalysis>> build() async => [];
}

class _Library implements LibraryRepository {
  @override
  Future<List<LibraryFolder>> getFolders() async => [
    for (var i = 0; i < 12; i++)
      LibraryFolder(
        id: 'db-$i',
        userId: 'layout-user',
        name: 'Database $i',
        color: '#0FB4E5',
        icon: 'database',
        orderIndex: i,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
  ];

  @override
  Future<List<SavedAnalysis>> getSavedAnalysesBySourceGame({
    required String sourceGameId,
  }) async => [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
