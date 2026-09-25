import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/providers/gamebase_overlay_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/local_storage/local_eval/local_eval_cache.dart';
import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/game_stream_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report_store.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/contrast_audit.dart';

/// The live board screen in light mode, audited as the user sees it: every
/// text run and icon glyph against the surface it is painted on, then the
/// game switcher opened and audited the same way.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The walkthrough overlays sit on their own dark scrim in both themes;
    // they are kept out so the audit reads the board chrome itself.
    SharedPreferences.setMockInitialValues({
      'swipable_walkthrough_dont_show': true,
      'explorer_panel_walkthrough_dont_show': true,
      'like_walkthrough_dont_show': true,
    });
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      publishableKey: 'placeholder-anon-key',
    );
    GameAnalysisReportStore.debugSetInstance(GameAnalysisReportStore.memory());
  });

  tearDownAll(GameAnalysisReportStore.debugResetInstance);

  testWidgets('board screen and its game switcher read on paper', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final raws = List<Games>.generate(
      4,
      (i) => _rawGame(id: 'game-$i', tourId: 'tour-1', board: i + 1),
    );
    final games = raws.map(GamesTourModel.fromGame).toList();

    final container = ProviderContainer(
      overrides: [
        effectiveCountryProvider.overrideWithValue(const AsyncValue.loading()),
        gamesLocalStorage.overrideWith(
          (ref) => _FullCacheGamesLocalStorage(ref, {'tour-1': raws}),
        ),
        gameRepositoryProvider.overrideWithValue(
          _ImmediateGameRepository({for (final g in raws) g.id: g}),
        ),
        gamebaseRepositoryProvider.overrideWithValue(_FakeGamebaseRepository()),
        gameStreamRepositoryProvider.overrideWithValue(
          _FakeGameStreamRepository(),
        ),
        localEvalCacheProvider.overrideWith(_FakeLocalEvalCache.new),
        engineSettingsProviderNew.overrideWith(_FakeEngineSettingsNotifier.new),
        gamebaseOverlayEnabledProvider.overrideWith(
          _FakeGamebaseOverlayNotifier.new,
        ),
        eventNoSpoilersProvider.overrideWith(
          (ref, tourId) =>
              _FakeEventNoSpoilersController(ref: ref, tourId: tourId),
        ),
        chessBoardPersistenceEnabledProvider.overrideWithValue(false),
        spaceShortcutsProvider.overrideWith(_NoShortcuts.new),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return ChessBoardScreenNew(
                currentIndex: 0,
                games: games,
                viewSource: ChessboardView.tour,
              );
            },
          ),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.textContaining('game-0'), findsWidgets);
    expectNoContrastMisses(
      auditTextContrast(tester, fallbackGround: AppColors.light.background),
      where: 'ChessBoardScreenNew',
    );

    final selector = find.byKey(e2eKey(E2eIds.boardGameSelector)).first;
    final selectorTap = find.descendant(
      of: selector,
      matching: find.byType(GestureDetector),
    );
    tester.widget<GestureDetector>(selectorTap.first).onTap!();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(boardGameDropdownContentTestKey), findsOneWidget);
    expectNoContrastMisses(
      auditTextContrast(tester, fallbackGround: AppColors.light.background),
      where: 'board game switcher',
    );

    // Close the switcher, then walk the notation's long-press surfaces.
    await tester.tapAt(const Offset(8, 840));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final move = find.textContaining('e4');
    expect(move, findsWidgets);
    await tester.longPress(move.first);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Comment'), findsOneWidget);
    expectNoContrastMisses(
      auditTextContrast(tester, fallbackGround: AppColors.light.background),
      where: 'notation move actions',
    );

    await tester.tap(find.text('Annotate (!? ± ∞ =)'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('QUALITY'), findsOneWidget);
    expectNoContrastMisses(
      auditTextContrast(tester, fallbackGround: AppColors.light.background),
      where: 'NAG picker',
    );

    // Pick one: the active chip and the SAN badge take their filled inks.
    await tester.tap(find.text('!?').first);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expectNoContrastMisses(
      auditTextContrast(tester, fallbackGround: AppColors.light.background),
      where: 'NAG picker with an active annotation',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
  });
}

Games _rawGame({
  required String id,
  required String tourId,
  required int board,
}) {
  return Games(
    id: id,
    roundId: 'round-1',
    roundSlug: 'round-1',
    tourId: tourId,
    tourSlug: tourId,
    players: [
      _player(name: 'White $id', fideId: board * 2 + 1),
      _player(name: 'Black $id', fideId: board * 2 + 2),
    ],
    boardNr: board,
    status: '1-0',
    lastMove: 'e7e5',
    pgn:
        '''
[Event "Dropdown jump"]
[White "White $id"]
[Black "Black $id"]
[Result "1-0"]

1. e4 e5 1-0
''',
  );
}

Player _player({required String name, required int fideId}) {
  return Player(
    name: name,
    title: 'GM',
    rating: 2700,
    fideId: fideId,
    fed: 'USA',
    clock: 0,
    team: '',
  );
}

class _ImmediateGameRepository extends GameRepository {
  _ImmediateGameRepository(this.games);

  final Map<String, Games> games;

  @override
  Future<Games> getGameWithPGN(String gameId) async => games[gameId]!;

  @override
  Future<String?> getGamePgn(String gameId) async => games[gameId]?.pgn;
}

class _FullCacheGamesLocalStorage extends GamesLocalStorage {
  _FullCacheGamesLocalStorage(super.ref, this.byTour);

  final Map<String, List<Games>> byTour;

  @override
  Future<List<Games>> getCachedGames(String tourId) async =>
      byTour[tourId] ?? const [];

  @override
  Future<List<Games>> fetchAndSaveGames(
    String tourId, {
    bool forceRefresh = false,
    String? priorityRoundId,
    void Function(List<Games>)? onPriorityRound,
    Future<void> Function()? afterPriorityRound,
    bool rethrowErrors = false,
  }) async => byTour[tourId] ?? const [];
}

class _FakeGamebaseRepository extends GamebaseRepository {
  _FakeGamebaseRepository()
    : super(Dio(), baseUrl: 'http://localhost', apiKey: 'test');

  @override
  Future<GamebaseGameWithPgn?> getGameWithPgn(String id) async => null;

  @override
  Future<CloudEval?> getEvalByFen(String fen) async => null;

  @override
  Future<GamebaseResponse> getMoveAggregates({
    required String fen,
    List<String> moves = const [],
    String? playerId,
    TimeControl? timeControl,
    int? minRating,
    int? maxRating,
    String? color,
    String? result,
    int? yearFrom,
    int? yearTo,
    bool? isOnline,
  }) async => const GamebaseResponse(
    status: 'success',
    data: GamebaseData(moves: []),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeGameStreamRepository extends GameStreamRepository {
  @override
  Stream<Map<String, dynamic>?> subscribeToGameUpdates(String gameId) =>
      const Stream.empty();

  @override
  Stream<String?> subscribeToPgn(String gameId) => const Stream.empty();

  @override
  Stream<String?> subscribeToLastMove(String gameId) => const Stream.empty();

  @override
  Stream<String?> subscribeToFen(String gameId) => const Stream.empty();

  @override
  Stream<String?> subscribeToStatus(String gameId) => const Stream.empty();
}

class _FakeEngineSettingsNotifier extends AsyncNotifier<EngineSettings>
    implements EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async =>
      const EngineSettings(showEngineAnalysis: false, showEngineGauge: false);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeGamebaseOverlayNotifier extends GamebaseOverlayEnabledNotifier {
  @override
  Future<bool> build() async => false;

  @override
  Future<void> setEnabled(bool enabled) async {
    state = AsyncValue.data(enabled);
  }

  @override
  Future<void> toggle() => setEnabled(!(state.valueOrNull ?? false));
}

class _FakeEventNoSpoilersController extends EventNoSpoilersController {
  _FakeEventNoSpoilersController({required super.ref, required super.tourId});

  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(enabled: false, isLoading: false);
  }
}

class _FakeLocalEvalCache extends LocalEvalCache {
  _FakeLocalEvalCache(super.ref);

  @override
  Future<CloudEval?> fetch(
    String fen, {
    int? multiPV,
    int minDepth = 0,
  }) async => null;

  @override
  Future<void> save(String fen, CloudEval eval, {int? multiPV}) async {}
}

class _NoShortcuts extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];
}
