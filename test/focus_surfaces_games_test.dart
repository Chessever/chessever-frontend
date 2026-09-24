import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/widgets/board_focus_menus.dart';
import 'package:chessever2/screens/gamebase/utils/space_position_draft.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/library/widgets/book_saved_game_card.dart';
import 'package:chessever2/screens/library/widgets/folder_card.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:chessever2/widgets/space_shortcut_drafts.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Game surfaces on the shared focus menu: a game card lifts itself and keeps
/// its old rows, library cards grow a 3-dot that opens the same menu as the
/// long-press, a Feed player name answers its own long-press, and the board's
/// position / round / event / opening pins carry what their openers need.

/// My Space store double: in memory, never touches SQLite or Supabase.
class _MemorySpaceShortcuts extends SpaceShortcutsNotifier {
  List<SpaceShortcut> get _list => state.valueOrNull ?? const [];

  @override
  Future<List<SpaceShortcut>> build() async => const [];

  @override
  Future<bool> add(SpaceShortcut draft) async {
    if (_list.any((s) => s.key == draft.key)) return false;
    state = AsyncData([draft, ..._list]);
    return true;
  }

  @override
  Future<SpaceShortcut?> removeTarget(
    SpaceShortcutKind kind,
    String targetId,
  ) async {
    final key = SpaceShortcut.keyFor(kind, targetId);
    SpaceShortcut? hit;
    for (final s in _list) {
      if (s.key == key) hit = s;
    }
    state = AsyncData([
      for (final s in _list)
        if (s.key != key) s,
    ]);
    return hit;
  }

  @override
  Future<void> restore(SpaceShortcut item) async {
    state = AsyncData([item, ..._list]);
  }
}

/// Keeps the real settings load (and its sqlite timers) out of the tests.
class _FakeEngineSettings extends AsyncNotifier<EngineSettings>
    implements EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async => const EngineSettings();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Widget _host({required Widget child, List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: [
      spaceShortcutsProvider.overrideWith(_MemorySpaceShortcuts.new),
      engineSettingsProviderNew.overrideWith(_FakeEngineSettings.new),
      ...overrides,
    ],
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: MediaQuery(
        data: const MediaQueryData(size: Size(390, 844), devicePixelRatio: 3),
        child: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            // Cards sit in lists, so their height is unbounded here too.
            return Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: 358,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [child],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

List<SpaceShortcut> _stored(WidgetTester tester) {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(Scaffold).first),
  );
  return container.read(spaceShortcutsProvider).valueOrNull ?? const [];
}

/// Settles the menu's springs without pumpAndSettle, which some card
/// providers never let finish.
Future<void> _settleMenu(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 800));
}

/// Lets the snack the My Space row raises time out, so no timer outlives the
/// test.
Future<void> _drainSnack(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pump(const Duration(seconds: 1));
}

PlayerCard _player(String name, {int? fideId}) => PlayerCard(
  name: name,
  federation: '',
  title: 'GM',
  rating: 2750,
  countryCode: '',
  team: null,
  fideId: fideId,
);

GamesTourModel _game({
  GameSource source = GameSource.gamebase,
  String tourId = 'Paris Opera',
  String roundId = 'gamebase-miniatures',
  String? roundSlug,
}) {
  return GamesTourModel(
    gameId: 'game-1',
    source: source,
    whitePlayer: _player('Morphy'),
    blackPlayer: _player('Isouard'),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.whiteWins,
    roundId: roundId,
    roundSlug: roundSlug,
    tourId: tourId,
    eco: 'C41',
  );
}

const _finishedPgn = '''
[Event "Paris Opera"]
[Site "Paris"]
[Date "1858.11.02"]
[Round "1"]
[White "Morphy, Paul"]
[Black "Isouard, Count"]
[Result "1-0"]

1. e4 e5 2. Nf3 d6 1-0
''';

SavedAnalysis _savedGame() {
  final at = DateTime.utc(2026, 9, 1);
  return SavedAnalysis(
    id: 'analysis-1',
    userId: 'user-1',
    folderId: 'db-1',
    title: 'Opera game',
    sourceGameId: 'source-game-1',
    chessGame: ChessGame.fromPgn('analysis-1', _finishedPgn),
    analysisState: const {},
    variationComments: const {},
    lastViewedPosition: -1,
    tags: const [],
    isFavorite: false,
    createdAt: at,
    updatedAt: at,
  );
}

LibraryFolder _database({String? shareToken}) {
  final at = DateTime.utc(2026, 9, 1);
  return LibraryFolder(
    id: 'db-1',
    userId: 'user-1',
    name: 'Openings prep',
    color: '#0FB4E5',
    icon: 'folder',
    orderIndex: 0,
    createdAt: at,
    updatedAt: at,
    shareToken: shareToken,
  );
}

void main() {
  group('game card focus menu', () {
    testWidgets('lifts the card itself and keeps Pin, Share and My Space', (
      tester,
    ) async {
      var opened = 0;
      await tester.pumpWidget(
        _host(
          child: GameCard(
            matchComparison: MatchWithComparison(
              game: _game(),
              comparison: MatchComparison.sameOrder,
            ),
            pinnedIds: const [],
            onPinToggle: (_) {},
            onTap: () => opened++,
          ),
        ),
      );
      await tester.pump();

      await tester.longPress(find.byType(GameCard));
      await _settleMenu(tester);

      // The card is its own preview: its names rise a second time.
      expect(find.text('Morphy'), findsNWidgets(2));
      expect(find.text('Pin'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Add to My Space'), findsOneWidget);

      await tester.tap(find.text('Add to My Space'));
      await _settleMenu(tester);
      final pin = _stored(tester).single;
      expect(pin.kind, SpaceShortcutKind.game);
      expect(pin.targetId, 'game-1');
      expect(pin.params['source'], 'gamebase');
      expect(opened, 0);
      await _drainSnack(tester);
    });

    testWidgets('archive hosts drop the Pin row', (tester) async {
      await tester.pumpWidget(
        _host(
          child: GameCard(
            matchComparison: MatchWithComparison(
              game: _game(),
              comparison: MatchComparison.sameOrder,
            ),
            pinnedIds: const [],
            onPinToggle: (_) {},
            onTap: () {},
            showPin: false,
          ),
        ),
      );
      await tester.pump();

      await tester.longPress(find.byType(GameCard));
      await _settleMenu(tester);
      expect(find.text('Pin'), findsNothing);
      expect(find.text('Share'), findsOneWidget);
    });
  });

  group('library cards: 3-dot opens the long-press menu', () {
    testWidgets('database card keeps every overlay action behind a 44dp dot', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          overrides: [
            folderAnalysisCountProvider.overrideWith((ref, id) async => 12),
          ],
          child: FolderCard(folder: _database(), isExpanded: true),
        ),
      );
      await tester.pump();

      final dot = find.byType(CardMoreButton);
      expect(dot, findsOneWidget);
      final size = tester.getSize(dot);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));

      await tester.tap(dot);
      await _settleMenu(tester);
      // Same labels, same order as the old overlay (My Space before Delete).
      for (final label in ['Share', 'Rename', 'Add to My Space', 'Delete']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // The whole card lifts, not just the button.
      expect(find.text('Openings prep'), findsNWidgets(2));

      await tester.tap(find.text('Add to My Space'));
      await _settleMenu(tester);
      final pin = _stored(tester).single;
      expect(pin.kind, SpaceShortcutKind.folder);
      expect(pin.targetId, 'db-1');
      await _drainSnack(tester);

      // Long-press raises the same menu, now reading live state.
      await tester.longPress(find.byType(FolderCard));
      await _settleMenu(tester);
      expect(find.text('Remove from My Space'), findsOneWidget);
      expect(find.text('Rename'), findsOneWidget);
    });

    testWidgets('shared database keeps Copy Link and Stop Sharing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          overrides: [
            folderAnalysisCountProvider.overrideWith((ref, id) async => 3),
          ],
          child: FolderCard(
            folder: _database(shareToken: 'token-1'),
            isExpanded: true,
          ),
        ),
      );
      await tester.pump();

      await tester.longPress(find.byType(FolderCard));
      await _settleMenu(tester);
      for (final label in [
        'Copy Link',
        'Stop Sharing',
        'Rename',
        'Add to My Space',
        'Delete',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('saved game card: 3-dot opens the saved-game menu', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(child: BookSavedGameCard(analysis: _savedGame(), onTap: () {})),
      );
      await tester.pump();

      await tester.tap(find.byType(CardMoreButton));
      await _settleMenu(tester);
      for (final label in [
        'Open game',
        'Edit & annotate',
        'Share game',
        'Copy PGN',
        'Copy FEN',
        'Move to database',
        'Add to My Space',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // No host remove handler: no destructive row.
      expect(find.text('Delete game'), findsNothing);
    });
  });

  group('board pins', () {
    test('a notation move pins the same position the explorer does', () {
      final game = ChessGame.fromPgn('g', _finishedPgn);
      // Pointer [2] is 2. Nf3 on the mainline.
      final draft = boardNotationPositionDraft(game: game, pointer: [2])!;

      var position = Chess.initial as Position;
      for (final san in ['e4', 'e5', 'Nf3']) {
        position = position.play(position.parseSan(san)!);
      }
      expect(draft.kind, SpaceShortcutKind.position);
      expect(draft.targetId, position.fen);
      expect(draft.params['moves'], ['e2e4', 'e7e5', 'g1f3']);

      final explorer = spacePositionDraft(
        fen: position.fen,
        ucis: const ['e2e4', 'e7e5', 'g1f3'],
      )!;
      expect(draft.key, explorer.key);
      expect(draft.title, explorer.title);
    });

    test('a round pin is offered for live broadcast games only', () {
      final live = boardRoundSpaceDraft(
        game: _game(
          source: GameSource.supabase,
          tourId: 'tour-1',
          roundId: 'round-5',
          roundSlug: 'round-5',
        ),
        groupBroadcastId: 'group-1',
        eventName: 'Sinquefield Cup 2026',
      )!;
      expect(live.kind, SpaceShortcutKind.round);
      expect(live.targetId, 'round-5');
      expect(live.params['tourId'], 'tour-1');
      expect(live.params['groupBroadcastId'], 'group-1');
      expect(live.params['eventName'], 'Sinquefield Cup 2026');

      // Archive rows carry a sentinel round, and virtual events cannot open.
      expect(boardRoundSpaceDraft(game: _game()), isNull);
      expect(
        boardRoundSpaceDraft(
          game: _game(
            source: GameSource.supabase,
            tourId: 'gamebase::Paris Opera',
            roundId: 'round-1',
          ),
        ),
        isNull,
      );
    });

    test('event and opening pins skip what cannot reopen', () {
      final event = boardEventSpaceDraft(
        eventName: 'Sinquefield Cup 2026',
        groupBroadcastId: 'group-1',
        tourId: 'tour-1',
      )!;
      expect(event.key, SpaceShortcut.keyFor(SpaceShortcutKind.event, 'group-1'));
      expect(event.params['tourId'], 'tour-1');
      expect(
        boardEventSpaceDraft(eventName: 'Opera', tourId: 'gamebase::Opera'),
        isNull,
      );

      final opening = boardOpeningSpaceDraft(eco: 'c41', openingName: 'Philidor')!;
      expect(opening.kind, SpaceShortcutKind.opening);
      expect(opening.targetId, 'C41');
      expect(opening.params['ecoCode'], 'C41');
      expect(boardOpeningSpaceDraft(eco: '?'), isNull);
      expect(boardOpeningSpaceDraft(eco: 'Unknown'), isNull);
    });

    test('a ChessEver Database event pins as a filtered folder', () {
      final draft = spaceTwicEventDraft(
        eventName: '  Tata Steel Masters 2026 ',
      );
      expect(draft.kind, SpaceShortcutKind.folder);
      expect(draft.targetId, '$kTwicBookId:Tata Steel Masters 2026');
      expect(draft.params['event'], 'Tata Steel Masters 2026');
    });
  });
}
