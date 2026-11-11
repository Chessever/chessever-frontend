// iPhone Duo audit for My Space and Library: every in-scope surface in all
// four window states at 1.0x and 1.3x text, and across folded <-> unfolded
// transitions where the surface holds state.
import 'dart:async';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/providers/for_you_games_logic.dart'
    show ForYouEventGamesSnapshot;
import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/chessboard/widgets/save_analysis_sheet.dart';
import 'package:chessever2/screens/collections/collections_data.dart'
    show collectionsProvider;
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart'
    show discoverySmartEventMembersProvider;
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart'
    show smartEventSpaceDraft;
import 'package:chessever2/screens/library/providers/gamebase_database_games_provider.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/library/widgets/add_to_library_sheet.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_space_shortcut.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_watch_star.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/my_space_view.dart';
import 'package:chessever2/screens/my_space/providers/space_auto_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_hub_providers.dart';
import 'package:chessever2/screens/my_space/providers/space_players_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/space_add_fab.dart';
import 'package:chessever2/screens/my_space/widgets/space_edit_grid.dart';
import 'package:chessever2/screens/my_space/widgets/space_edit_tutorial.dart';
import 'package:chessever2/screens/my_space/widgets/space_section_screen.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/adaptive_window.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/event_context_menu.dart'
    show eventSpaceDraft;
import 'package:chessever2/widgets/event_card/event_image_provider.dart';
import 'package:chessever2/widgets/event_card/event_next_round_provider.dart';
import 'package:chessever2/widgets/event_card/smart_event_star.dart'
    show SmartEventStar;
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart'
    show playerPhotoProvider;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'fixtures/duo_window_matrix.dart';

// ---------------------------------------------------------------------------
// My Space doubles (same shape as test/my_space_view_test.dart's).
// ---------------------------------------------------------------------------

class _Store extends SpaceShortcutsNotifier {
  _Store(this._seed);

  final List<SpaceShortcut> _seed;

  List<SpaceShortcut> get _list => state.valueOrNull ?? const [];

  @override
  Future<List<SpaceShortcut>> build() async => _seed;

  @override
  Future<bool> add(SpaceShortcut draft) async {
    if (_list.any((s) => s.key == draft.key)) return false;
    state = AsyncData([draft.copyWith(sortIndex: 99), ..._list]);
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
    if (_list.any((s) => s.key == item.key)) return;
    state = AsyncData(SpaceShortcutsNotifier.inDisplayOrder([item, ..._list]));
  }

  @override
  Future<void> moveToFront(String id) async {}

  @override
  Future<void> moveWithinSection(String key, int toIndex) async {
    final plan = SpaceShortcutsNotifier.planSectionMove(_list, key, toIndex);
    if (plan != null) state = AsyncData(plan.list);
  }

  @override
  Future<void> moveWithinVisible(String key, List<String> visibleOrder) async {
    final plan = SpaceShortcutsNotifier.planVisibleMove(
      _list,
      key,
      visibleOrder,
    );
    if (plan != null) state = AsyncData(plan.list);
  }

  @override
  Future<void> markOpened(String id) async {}

  List<String> keysOf(SpaceSection section) => [
    for (final s in _list)
      if (s.section == section) s.key,
  ];
}

class _Tips extends SpaceEditTutorialStore {
  @override
  bool due() => false;
  @override
  bool playersShown() => true;
  @override
  void markShown() {}
  @override
  void markPlayersShown() {}
  @override
  void markSkipped() {}
}

class _NoLikes extends LikedGamesNotifier {
  @override
  Future<List<SavedAnalysis>> build() async => const [];
}

class _NoFavoriteEvents extends FavoriteEventsNotifier {
  @override
  Future<List<FavoriteEvent>> build() async => const [];
}

class _BoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

class _EngineSettings extends AsyncNotifier<EngineSettings>
    implements EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async => const EngineSettings();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Hidden extends SpaceHiddenAutoKeys {
  @override
  Set<String> build() => const <String>{};
  @override
  void hide(String key) => state = {...state, key};
  @override
  void unhide(String key) => state = {...state}..remove(key);
}

class _Favorites extends FavoritePlayersNotifierNew {
  @override
  Future<List<FavoritePlayer>> build() async => const [];
}

class _Visits extends SpacePlayerVisits {
  @override
  Map<String, int> build() => const {};
}

class _Feed extends StateNotifier<ForYouState> implements ForYouNotifier {
  _Feed(List<GroupEventCardModel> events)
    : super(ForYouState(events: events, hasMore: false));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoSpoilers extends EventNoSpoilersController {
  _NoSpoilers({required super.ref, required super.tourId});

  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(enabled: false, isLoading: false);
  }
}

CloudEval _eval(String fen) => CloudEval(
  fen: fen,
  knodes: 0,
  depth: 20,
  pvs: [Pv(moves: 'e2e4', cp: 40)],
  requestedMultiPv: 1,
);

GroupEventCardModel _event(String id, String title) => GroupEventCardModel(
  id: id,
  title: title,
  dates: 'Sep 18 - 29, 2026',
  maxAvgElo: 2750,
  timeUntilStart: '',
  tourEventCategory: TourEventCategory.live,
  timeControl: 'Standard',
  endDate: DateTime(2026, 9, 29),
  startDate: DateTime(2026, 9, 18),
);

final _feed = [
  _event('ev-a', 'Sinquefield Cup 2026'),
  _event('ev-b', 'FIDE Grand Swiss 2026'),
  _event('ev-c', 'Chennai Grand Masters 2026'),
  _event('ev-d', 'European Club Cup 2026'),
];

SpaceShortcut _pin(SpaceShortcut draft, String id, double sort) =>
    SpaceShortcut(
      id: id,
      kind: draft.kind,
      targetId: draft.targetId,
      title: draft.title,
      subtitle: draft.subtitle,
      params: draft.params,
      sortIndex: sort,
      createdAt: DateTime(2026, 9, 20),
    );

SpaceShortcut _folderPin(int i, double sort) => _pin(
  SpaceShortcut.draft(
    kind: SpaceShortcutKind.folder,
    targetId: 'db-$i',
    title: 'Saved database $i',
    subtitle: '${100 + i} games',
  ),
  'folder-$i',
  sort,
);

SpaceShortcut _smartDraft(int minElo) => smartEventSpaceDraft(
  SmartEventRequest(
    source: SmartEventSource.forYou,
    tierLabel: '$minElo+',
    titleSuffix: 'Games',
    minElo: minElo,
    maxElo: 3200,
    caption: 'From your $minElo+ filter',
    countSingular: 'event',
    countPlural: 'events',
    events: const [],
    savedAt: DateTime(2026, 9, 24, 10),
  ),
);

final _prepProfile = PrepProfile(
  id: 'prep-duo',
  kind: PrepKind.opponent,
  name: 'Long named opponent preparation profile',
  createdAtMs: 1,
  accounts: const [
    PrepAccount(source: PrepSource.lichess, username: 'clubplayer'),
  ],
);

List<Override> _spaceOverrides(_Store store) => [
  spaceShortcutsProvider.overrideWith(() => store),
  playerPhotoProvider.overrideWith((ref, fideId) async => null),
  currentUserProvider.overrideWithValue(null),
  likedGamesProvider.overrideWith(_NoLikes.new),
  favoriteEventsProvider.overrideWith(_NoFavoriteEvents.new),
  spaceHiddenAutoKeysProvider.overrideWith(_Hidden.new),
  favoritePlayersProviderNew.overrideWith(_Favorites.new),
  spacePlayerVisitsProvider.overrideWith(_Visits.new),
  forYouEventsProvider.overrideWith((ref) => _Feed(_feed)),
  libraryFolderAuthenticatedUserIdProvider.overrideWith((ref) => null),
  twicDatabaseTotalGamesProvider.overrideWith((ref) async => 9812345),
  liveGroupBroadcastIdsProvider.overrideWith(
    (ref) => Stream.value(const <String>[]),
  ),
  liveRoundsIdProvider.overrideWith((ref) => Stream.value(const <String>[])),
  spaceEventBroadcastsProvider.overrideWith(
    (ref, ids) async => const <GroupBroadcast>[],
  ),
  spacePlayersLiveGamesProvider.overrideWith(
    (ref, ids) async => const <GamesTourModel>[],
  ),
  spaceLiveEventGamesProvider.overrideWith(
    (ref, ids) async => SpaceLiveEventGames(
      byEvent: const <String, ForYouEventGamesSnapshot>{},
    ),
  ),
  eventNoSpoilersProvider.overrideWith(
    (ref, tourId) => _NoSpoilers(ref: ref, tourId: tourId),
  ),
  gameCardEvalWithStockfishFallbackProvider.overrideWith(
    (ref, fen) async => _eval(fen),
  ),
  gameCardEvalCacheOnlyProvider.overrideWith((ref, fen) async => _eval(fen)),
  boardSettingsProviderNew.overrideWith(_BoardSettings.new),
  engineSettingsProviderNew.overrideWith(_EngineSettings.new),
  gamesListViewModeProvider.overrideWithValue(GamesListViewMode.chessBoardGrid),
  eventImageProvider.overrideWith((ref, id) async => const EventImageData()),
  eventNextRoundProvider.overrideWith((ref, id) async => null),
  discoverySmartEventMembersProvider.overrideWith(
    (ref, criteria) async => const <GroupEventCardModel>[],
  ),
  collectionsProvider.overrideWith((ref) async => []),
  spaceEditTutorialStoreProvider.overrideWithValue(_Tips()),
  prepProfileProvider(_prepProfile.id).overrideWithValue(_prepProfile),
];

/// The real root scopes' text and window handling, at dpr 3.
Widget _app({
  required double scale,
  required List<Override> overrides,
  required Widget home,
}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    theme: AppTheme.darkTheme,
    builder: (_, child) => MediaQuery.withClampedTextScaling(
      minScaleFactor: scale,
      maxScaleFactor: scale,
      child: AdaptiveWindowScope(child: child!),
    ),
    home: home,
  ),
);

void _duo(WidgetTester tester, DuoWindowCase window) {
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  applyDuoWindow(tester, window);
}

Future<void> _settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _drain(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(minutes: 6));
}

/// The first vertical scrollable under [of].
Finder _verticalScroll(Finder of) => find
    .descendant(
      of: of,
      matching: find.byWidgetPredicate(
        (w) =>
            w is Scrollable &&
            axisDirectionToAxis(w.axisDirection) == Axis.vertical,
      ),
    )
    .first;

/// Scrolls [target] into the viewport and proves a tap would land on it.
Future<void> _reach(WidgetTester tester, Finder target, Finder list) async {
  await tester.scrollUntilVisible(
    target,
    120,
    scrollable: list,
    maxScrolls: 200,
  );
  await _settle(tester, 4);
  await tester.ensureVisible(target);
  await _settle(tester, 4);
  expect(target.hitTestable(), findsWidgets);
}

// The home: two events, a smart event, a prep profile and ten databases,
// so the last card sits well below every Duo fold.
final _homeEvents = [
  _pin(eventSpaceDraft(_feed[0]), 'e0', 40),
  _pin(eventSpaceDraft(_feed[1]), 'e1', 39),
];
final _homeSmart = _pin(_smartDraft(2700), 'se', 38);
final _homePrep = _pin(prepProfileSpaceDraft(_prepProfile), 'prep', 37);
final _homeFolders = [for (var i = 0; i < 10; i++) _folderPin(i, 30.0 - i)];

Widget _homeScaffold() => Builder(
  builder: (context) {
    ResponsiveHelper.init(context);
    return const Scaffold(
      body: SafeArea(bottom: false, child: MySpaceView()),
      floatingActionButton: SpaceAddFab(),
    );
  },
);

// ---------------------------------------------------------------------------
// Library doubles: the save-to-library sheet (Save Analysis).
// ---------------------------------------------------------------------------

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

class _Library implements LibraryRepository {
  @override
  Future<List<LibraryFolder>> getFolders() async => [
    for (var i = 0; i < 12; i++)
      LibraryFolder(
        id: 'db-$i',
        userId: 'duo-user',
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

Future<void> _openSaveSheet(WidgetTester tester, double scale) async {
  final game = GamesTourModel(
    gameId: 'duo-game',
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
    _app(
      scale: scale,
      overrides: [
        chessBoardScreenProviderNew(
          params,
        ).overrideWith((ref) => _Board(state)),
        likedGamesProvider.overrideWith(_NoLikes.new),
        likedGamePendingTagsProvider(
          game.likeId,
        ).overrideWith((ref) => const <String>[]),
        libraryRepositoryProvider.overrideWithValue(_Library()),
        folderAnalysisCountProvider.overrideWith((ref, folderId) async => 1),
      ],
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => unawaited(
                  showSaveAnalysisSheet(
                    context: context,
                    state: state,
                    params: params,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _expectReachable(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
}

const _scales = [1.0, 1.3];

/// folded <-> unfolded, both directions, every orientation pairing.
Iterable<DuoWindowTransition> get _foldTransitions =>
    duoWindowTransitions.where((t) => t.from.unfolded != t.to.unfolded);

void main() {
  // -------------------------------------------------------------------------
  // My Space home: card grid, stars, last-card scroll, add button.
  // -------------------------------------------------------------------------
  for (final window in duoWindowCases) {
    for (final scale in _scales) {
      testWidgets('My Space home fits ${window.name} at ${scale}x: stars and '
          'the last card are reachable, + stays hittable', (tester) async {
        _duo(tester, window);
        final store = _Store([
          ..._homeEvents,
          _homeSmart,
          _homePrep,
          ..._homeFolders,
        ]);
        await tester.pumpWidget(
          _app(
            scale: scale,
            overrides: _spaceOverrides(store),
            home: _homeScaffold(),
          ),
        );
        await _settle(tester);
        expect(tester.takeException(), isNull);
        expect(find.byType(SpaceAddFab).hitTestable(), findsOneWidget);

        final list = _verticalScroll(find.byType(MySpaceView));
        // The smart event's own star and the Prep profile's star.
        await _reach(
          tester,
          find.descendant(
            of: find.byKey(ValueKey<String>('space_smart_${_homeSmart.key}')),
            matching: find.byType(SmartEventStar),
          ),
          list,
        );
        await _reach(tester, find.byType(PrepWatchStar), list);
        // The last-card scroll fix: the final database clears the bottom.
        await _reach(tester, find.text(_homeFolders.last.title), list);
        final last = tester.getRect(find.text(_homeFolders.last.title));
        final fab = tester.getRect(find.byType(SpaceAddFab));
        expect(
          last.bottom <= fab.top || last.right <= fab.left,
          isTrue,
          reason: 'last card $last sits under the + at $fab',
        );
        expect(tester.takeException(), isNull);
        await _drain(tester);
      });

      testWidgets('My Space hold menu removes a database in ${window.name} at '
          '${scale}x, and Undo is reachable', (tester) async {
        _duo(tester, window);
        final store = _Store([..._homeEvents, ..._homeFolders.take(3)]);
        await tester.pumpWidget(
          _app(
            scale: scale,
            overrides: _spaceOverrides(store),
            home: _homeScaffold(),
          ),
        );
        await _settle(tester);
        final target = _homeFolders[2];
        final list = _verticalScroll(find.byType(MySpaceView));
        await _reach(tester, find.text(target.title), list);
        await tester.longPress(find.text(target.title));
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull);
        await _expectReachable(tester, find.text('Remove from My Space'));
        await tester.tap(find.text('Remove from My Space'));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(store.keysOf(SpaceSection.library), isNot(contains(target.key)));
        expect(find.text(target.title), findsNothing);
        expect(find.text('Undo').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Undo'));
        await _settle(tester);
        expect(store.keysOf(SpaceSection.library), contains(target.key));
        expect(tester.takeException(), isNull);
        await _drain(tester);
      });

      testWidgets('My Space home Edit opens, selects and saves in '
          '${window.name} at ${scale}x', (tester) async {
        _duo(tester, window);
        final store = _Store([..._homeEvents, ..._homeFolders.take(4)]);
        await tester.pumpWidget(
          _app(
            scale: scale,
            overrides: _spaceOverrides(store),
            home: _homeScaffold(),
          ),
        );
        await _settle(tester);
        await tester.tap(find.byType(SpaceAddFab));
        await _settle(tester);
        expect(tester.takeException(), isNull);
        await _expectReachable(tester, find.bySemanticsLabel('Edit'));
        await tester.tap(find.bySemanticsLabel('Edit'));
        await _settle(tester);
        final check = find.byKey(
          ValueKey<String>('space_edit_check_${_homeFolders[3].key}'),
        );
        final edit = _verticalScroll(find.byType(SpaceEditGrid));
        await _reach(tester, check, edit);
        await tester.tap(check);
        await _settle(tester);
        expect(tester.widget<SpaceEditCheck>(check).selected, isTrue);
        final save = find.byKey(const ValueKey<String>('popover_fab_save'));
        expect(save.hitTestable(), findsOneWidget);
        await tester.tap(find.byType(SpaceAddFab));
        await _settle(tester);
        expect(find.byType(SpaceEditCheck), findsNothing);
        expect(tester.takeException(), isNull);
        await _drain(tester);
      });

      // ---------------------------------------------------------------------
      // See all (SpaceSectionScreen) Edit: select and Remove.
      // ---------------------------------------------------------------------
      testWidgets('My Space See all Edit selects and removes events in '
          '${window.name} at ${scale}x', (tester) async {
        _duo(tester, window);
        final events = [
          for (final (i, e) in _feed.indexed)
            _pin(eventSpaceDraft(e), 'e$i', 20.0 - i),
        ];
        final store = _Store(events);
        await tester.pumpWidget(
          _app(
            scale: scale,
            overrides: _spaceOverrides(store),
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return const SpaceSectionScreen(
                  section: SpaceSection.events,
                  pinsOnly: true,
                );
              },
            ),
          ),
        );
        await _settle(tester);
        expect(tester.takeException(), isNull);
        final editButton = find.byKey(const ValueKey<String>('space_edit'));
        expect(editButton.hitTestable(), findsOneWidget);
        await tester.tap(editButton);
        await _settle(tester);
        final list = _verticalScroll(find.byType(SpaceSectionScreen));
        final last = find.byKey(
          ValueKey<String>('space_edit_check_${events.last.key}'),
        );
        await _reach(tester, last, list);
        await tester.tap(last);
        await _settle(tester);
        expect(tester.widget<SpaceEditCheck>(last).selected, isTrue);
        final remove = find.byKey(const ValueKey<String>('space_edit_remove'));
        await _expectReachable(tester, remove);
        await tester.tap(remove);
        await _settle(tester);
        expect(
          store.keysOf(SpaceSection.events),
          isNot(contains(events.last.key)),
        );
        expect(tester.takeException(), isNull);
        await _drain(tester);
      });
    }
  }

  // Edit selection survives folding and unfolding.
  for (final t in _foldTransitions) {
    testWidgets('My Space See all Edit keeps its selection '
        '${t.from.name} -> ${t.to.name}', (tester) async {
      _duo(tester, t.from);
      final events = [
        for (final (i, e) in _feed.indexed)
          _pin(eventSpaceDraft(e), 'e$i', 20.0 - i),
      ];
      final store = _Store(events);
      await tester.pumpWidget(
        _app(
          scale: 1.3,
          overrides: _spaceOverrides(store),
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return const SpaceSectionScreen(
                section: SpaceSection.events,
                pinsOnly: true,
              );
            },
          ),
        ),
      );
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey<String>('space_edit')));
      await _settle(tester);
      final first = find.text(_feed.first.title);
      await tester.tap(first);
      await _settle(tester);
      final check = find.byKey(
        ValueKey<String>('space_edit_check_${events.first.key}'),
      );
      expect(tester.widget<SpaceEditCheck>(check).selected, isTrue);
      final screen = tester.state(find.byType(SpaceSectionScreen));

      applyDuoWindow(tester, t.to, mirrorInsets: true);
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: t.to.name);
      expect(tester.state(find.byType(SpaceSectionScreen)), same(screen));
      expect(tester.widget<SpaceEditCheck>(check).selected, isTrue);
      final remove = find.byKey(const ValueKey<String>('space_edit_remove'));
      await _expectReachable(tester, remove);

      applyDuoWindow(tester, t.from);
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: t.from.name);
      expect(tester.widget<SpaceEditCheck>(check).selected, isTrue);
      await tester.tap(remove);
      await _settle(tester);
      expect(
        store.keysOf(SpaceSection.events),
        isNot(contains(events.first.key)),
      );
      expect(tester.takeException(), isNull);
      await _drain(tester);
    });
  }

  // Home scroll position and Edit survive folding.
  for (final t in _foldTransitions) {
    testWidgets('My Space home Edit and selection survive '
        '${t.from.name} -> ${t.to.name}', (tester) async {
      _duo(tester, t.from);
      final store = _Store([..._homeEvents, ..._homeFolders.take(6)]);
      await tester.pumpWidget(
        _app(
          scale: 1.0,
          overrides: _spaceOverrides(store),
          home: _homeScaffold(),
        ),
      );
      await _settle(tester);
      await tester.tap(find.byType(SpaceAddFab));
      await _settle(tester);
      await tester.tap(find.bySemanticsLabel('Edit'));
      await _settle(tester);
      final target = _homeFolders[5];
      final check = find.byKey(
        ValueKey<String>('space_edit_check_${target.key}'),
      );
      await _reach(tester, check, _verticalScroll(find.byType(SpaceEditGrid)));
      await tester.tap(check);
      await _settle(tester);
      final view = tester.state(find.byType(MySpaceView));
      for (final w in [t.to, t.from]) {
        applyDuoWindow(tester, w, mirrorInsets: w == t.to);
        await _settle(tester);
        expect(tester.takeException(), isNull, reason: w.name);
        expect(tester.state(find.byType(MySpaceView)), same(view));
        expect(find.byType(SpaceEditGrid), findsOneWidget, reason: w.name);
        await _reach(
          tester,
          check,
          _verticalScroll(find.byType(SpaceEditGrid)),
        );
        expect(
          tester.widget<SpaceEditCheck>(check).selected,
          isTrue,
          reason: w.name,
        );
        expect(
          find.byKey(const ValueKey<String>('popover_fab_save')).hitTestable(),
          findsOneWidget,
          reason: w.name,
        );
      }
      await _drain(tester);
    });
  }

  // -------------------------------------------------------------------------
  // Library: Save Analysis (save-to-library guard) and Add to Library sheet.
  // -------------------------------------------------------------------------
  for (final window in duoWindowCases) {
    for (final scale in _scales) {
      testWidgets('Save Analysis guards Save until a database is picked in '
          '${window.name} at ${scale}x', (tester) async {
        _duo(tester, window);
        await _openSaveSheet(tester, scale);
        expect(tester.takeException(), isNull);
        final save = find.byType(FilledButton);
        expect(tester.widget<FilledButton>(save).onPressed, isNull);
        await _expectReachable(tester, find.text('Database 0'));
        await tester.tap(find.text('Database 0'));
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
        await _expectReachable(tester, save);
        await _expectReachable(
          tester,
          find.widgetWithText(TextButton, 'Cancel'),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();
        expect(find.byType(FilledButton), findsNothing);
      });

      testWidgets('Add to Library sheet offers every source in '
          '${window.name} at ${scale}x', (tester) async {
        _duo(tester, window);
        AddToLibraryChoice? picked;
        await tester.pumpWidget(
          _app(
            scale: scale,
            overrides: const [],
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () async =>
                          picked = await showAddToLibrarySheet(context),
                      child: const Text('Open'),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final label in [
          'Create Database',
          'Import PGN',
          'Import PGN file',
        ]) {
          await _expectReachable(tester, find.text(label));
        }
        await tester.tap(find.text('Import PGN file'));
        await tester.pumpAndSettle();
        expect(picked, AddToLibraryChoice.pickPgnFile);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final t in _foldTransitions) {
    testWidgets('Save Analysis keeps the picked database '
        '${t.from.name} -> ${t.to.name}', (tester) async {
      _duo(tester, t.from);
      await _openSaveSheet(tester, 1.3);
      await _expectReachable(tester, find.text('Database 0'));
      await tester.tap(find.text('Database 0'));
      await tester.pumpAndSettle();
      final save = find.byType(FilledButton);
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      for (final w in [t.to, t.from]) {
        applyDuoWindow(tester, w, mirrorInsets: w == t.to);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: w.name);
        expect(
          tester.widget<FilledButton>(save).onPressed,
          isNotNull,
          reason: w.name,
        );
        await _expectReachable(tester, save);
      }
    });
  }
}
