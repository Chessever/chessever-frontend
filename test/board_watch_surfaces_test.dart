import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/providers/gamebase_overlay_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/repository/local_storage/local_eval/local_eval_cache.dart';
import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/game_stream_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report_store.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/feed/audio/feed_sfx.dart';
import 'package:chessever2/screens/feed/feed_screen.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:chessever2/screens/feed/providers/feed_eval_provider.dart';
import 'package:chessever2/screens/feed/providers/feed_provider.dart';
import 'package:chessever2/screens/feed/puzzles/feed_puzzle.dart';
import 'package:chessever2/screens/feed/widgets/feed_clip.dart';
import 'package:chessever2/screens/feed/widgets/feed_move_sound.dart';
import 'package:chessever2/screens/feed/widgets/feed_sfx_provider.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/board_feature_teaching_store.dart';

/// Watch, exercised from the real board for every kind of game a surface
/// opens it on: the board's 3-dot menu, Feed opening on the game as its
/// first post with Feed after it, the post offering what that board offers,
/// and Analyze going back to the same board.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // A viewer who has had the board's walkthroughs: no coachmark over it.
    SharedPreferences.setMockInitialValues({
      'swipable_walkthrough_dont_show': true,
      'board_pinch_coachmark_seen': true,
      'board_pinch_coachmark_dont_show': true,
    });
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      publishableKey: 'placeholder-anon-key',
    );
    GameAnalysisReportStore.debugSetInstance(GameAnalysisReportStore.memory());
  });

  tearDownAll(GameAnalysisReportStore.debugResetInstance);

  const finished =
      '[Event "Test Open 2026"]\n[White "White A"]\n[Black "Black B"]\n'
      '[Result "1-0"]\n\n'
      '1. e4 {[%eval 0.3]} e5 {[%eval 0.3]} 2. Bc4 {[%eval 0.2]} '
      'Nc6 {[%eval 0.3]} 3. Qh5 {[%eval 0.1]} Nf6 {[%eval 9.0]} '
      '4. Qxf7# 1-0';
  const live =
      '[Event "Test Open 2026"]\n[White "White A"]\n[Black "Black B"]\n'
      '[Result "*"]\n\n1. d4 d5 2. c4 e6 3. Nc3 *';
  const empty =
      '[Event "New Analysis"]\n[White "White"]\n[Black "Black"]\n'
      '[Result "*"]\n\n*';

  testWidgets('an event broadcast game, finished', (tester) async {
    final raw = _raw(id: 'b1', pgn: finished, status: '1-0');
    await _watch(
      tester,
      game: GamesTourModel.fromGame(raw),
      raws: [raw],
      want: const _Expect(plies: 7, like: true, save: true),
    );
  });

  testWidgets('a live broadcast game, up to the move it has reached', (
    tester,
  ) async {
    final raw = _raw(id: 'b2', pgn: live, status: '*');
    await _watch(
      tester,
      game: GamesTourModel.fromGame(raw),
      raws: [raw],
      want: const _Expect(plies: 5, like: true, save: true, result: false),
    );
  });

  testWidgets('a finished broadcast game under the event\'s No Spoilers', (
    tester,
  ) async {
    final raw = _raw(id: 'b3', pgn: finished, status: '1-0');
    await _watch(
      tester,
      game: GamesTourModel.fromGame(raw),
      raws: [raw],
      noSpoilers: true,
      want: const _Expect(
        plies: 7,
        like: true,
        save: true,
        hideEvaluation: true,
        hideResult: true,
      ),
    );
  });

  testWidgets('the same game on a tablet, through its overlay menu', (
    tester,
  ) async {
    final raw = _raw(id: 'b4', pgn: finished, status: '1-0');
    await _watch(
      tester,
      game: GamesTourModel.fromGame(raw),
      raws: [raw],
      tablet: true,
      want: const _Expect(plies: 7, like: true, save: true),
    );
  });

  for (final source in [GameSource.gamebase, GameSource.twic]) {
    testWidgets('an archive game (${source.name}): Database, profiles, '
        'miniatures', (tester) async {
      await _watch(
        tester,
        game: _model('a-${source.name}', source: source, pgn: finished),
        want: const _Expect(plies: 7, like: true, save: true),
      );
    });
  }

  testWidgets('an Opening Explorer game: no Like, as on its board', (
    tester,
  ) async {
    await _watch(
      tester,
      game: _model('x1', source: GameSource.openingExplorer, pgn: finished),
      want: const _Expect(plies: 7, like: false, save: true),
    );
  });

  testWidgets('a game from My Likes keeps its Like', (tester) async {
    final game = _model(
      'saved_analysis_like',
      source: GameSource.savedAnalysis,
      pgn: finished,
      sourceGameId: 'b1',
    );
    await _watch(
      tester,
      game: game,
      saved: _saved(game, finished, folderId: 'liked-folder'),
      want: const _Expect(plies: 7, like: true, save: true),
    );
  });

  testWidgets("a game from the viewer's own database: no Like, as on its "
      'board', (tester) async {
    final game = _model(
      'saved_analysis_own',
      source: GameSource.savedAnalysis,
      pgn: finished,
      sourceGameId: 'b1',
    );
    await _watch(
      tester,
      game: game,
      saved: _saved(game, finished, folderId: 'own-folder'),
      want: const _Expect(plies: 7, like: false, save: true),
    );
  });

  testWidgets('an imported, prep or editor game: no Like, Save stays', (
    tester,
  ) async {
    await _watch(
      tester,
      game: _model('imported_1', source: GameSource.boardEditor, pgn: finished),
      want: const _Expect(plies: 7, like: false, save: true),
    );
  });

  testWidgets('a licensed collection game: no Like and no Save', (
    tester,
  ) async {
    await _watch(
      tester,
      game: _model('coll_1', source: GameSource.boardEditor, pgn: finished),
      allowGameExport: false,
      want: const _Expect(plies: 7, like: false, save: false),
    );
  });

  testWidgets('an analysis board of the viewer\'s own moves', (tester) async {
    await _watch(
      tester,
      game: _model('local_1', source: GameSource.localAnalysis, pgn: live),
      hideEventInfo: true,
      want: const _Expect(plies: 5, like: false, save: true, result: false),
    );
  });

  testWidgets('a game with no move yet says so and opens nothing', (
    tester,
  ) async {
    await _watch(
      tester,
      game: _model('local_2', source: GameSource.localAnalysis, pgn: empty),
      hideEventInfo: true,
      want: const _Expect.nothing(),
    );
  });
}

/// What Watch should give for a board.
class _Expect {
  const _Expect({
    required this.plies,
    required this.like,
    required this.save,
    this.result = true,
    this.hideEvaluation = false,
    this.hideResult = false,
  }) : opens = true;

  const _Expect.nothing()
    : opens = false,
      plies = 0,
      like = false,
      save = false,
      result = false,
      hideEvaluation = false,
      hideResult = false;

  final bool opens;
  final int plies;
  final bool like;
  final bool save;

  /// The game has a result the post shows (unless [hideResult]).
  final bool result;
  final bool hideEvaluation;
  final bool hideResult;
}

/// Opens [game] on the real board, taps 3-dot > Watch, checks the Feed it
/// opens against [want], then Analyze on the post and checks the board is
/// back.
Future<void> _watch(
  WidgetTester tester, {
  required GamesTourModel game,
  required _Expect want,
  List<Games> raws = const [],
  SavedAnalysisData? saved,
  bool allowGameExport = true,
  bool hideEventInfo = false,
  bool noSpoilers = false,
  bool tablet = false,
}) async {
  final defaultOnError = FlutterError.onError;
  // The explorer cards overflow under the test font; that layout noise is not
  // what this test covers.
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    defaultOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = defaultOnError);
  tester.view.physicalSize = tablet
      ? const Size(1024 * 2, 1366 * 2)
      : const Size(393 * 3, 852 * 3);
  tester.view.devicePixelRatio = tablet ? 2 : 3;
  addTearDown(tester.view.reset);

  final feed = _FakeFeed([_feedPost('f1'), _feedPost('f2')]);
  final sfx = _QuietSfx();
  final container = ProviderContainer(
    overrides: [
      boardFeatureTeachingTrackerProvider.overrideWith(
        (_) => BoardFeatureTeachingTracker(QuietBoardTeachingStore()),
      ),
      effectiveCountryProvider.overrideWithValue(const AsyncValue.loading()),
      gamesLocalStorage.overrideWith(
        (ref) => _CachedGames(ref, {'tour-1': raws}),
      ),
      gameRepositoryProvider.overrideWithValue(
        _Games({for (final g in raws) g.id: g}),
      ),
      gamebaseRepositoryProvider.overrideWithValue(_Gamebase()),
      gameStreamRepositoryProvider.overrideWithValue(_NoStream()),
      localEvalCacheProvider.overrideWith(_NoEvalCache.new),
      engineSettingsProviderNew.overrideWith(_EngineOff.new),
      gamebaseOverlayEnabledProvider.overrideWith(_OverlayOff.new),
      eventNoSpoilersProvider.overrideWith(
        (ref, tourId) =>
            _NoSpoilers(ref: ref, tourId: tourId, enabled: noSpoilers),
      ),
      chessBoardPersistenceEnabledProvider.overrideWithValue(false),
      likedGamesFolderProvider.overrideWith(
        (ref) async => LibraryFolder(
          id: 'liked-folder',
          userId: 'u1',
          name: 'Liked Games',
          color: '',
          icon: '',
          orderIndex: 0,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          isLikedGames: true,
        ),
      ),
      feedProvider.overrideWith(() => feed),
      feedPuzzlesProvider.overrideWith((ref) async => const <FeedPuzzle>[]),
      feedNewsProvider.overrideWith((ref) async => const <FeedNews>[]),
      feedSfxProvider.overrideWithValue(sfx),
      feedMoveSoundProvider.overrideWithValue(_QuietMoveSound(sfx)),
      boardSettingsProviderNew.overrideWith(_TestBoardSettings.new),
      likedGamesProvider.overrideWith(_NoLikes.new),
      spaceShortcutsProvider.overrideWith(_NoShortcuts.new),
      currentUserProvider.overrideWithValue(null),
      subscriptionProvider.overrideWith((ref) => _Subscribed()),
      feedCachedEvalProvider.overrideWith((ref, fen) async => null),
      feedEngineProvider.overrideWithValue(_NoFeedEngine()),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [AppColors.dark]),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return ChessBoardScreenNew(
              currentIndex: 0,
              games: [game],
              viewSource: ChessboardView.tour,
              savedAnalysisData: saved,
              allowGameExport: allowGameExport,
              hideEventInfo: hideEventInfo,
            );
          },
        ),
      ),
    ),
  );
  await _frames(tester, 20);
  expect(find.byType(ChessBoardScreenNew), findsOneWidget);
  // The Liked Games folder is known, as it is once the app has loaded it:
  // a game from it keeps its Like, one from another database does not.
  await container.read(likedGamesFolderProvider.future);

  // 3-dot > Watch.
  await tester.tap(find.byIcon(Icons.more_vert).first);
  await _frames(tester, 6);
  expect(find.text('Watch'), findsOneWidget);
  expect(find.byIcon(Icons.smart_display_outlined), findsOneWidget);
  await tester.tap(find.text('Watch'));
  await _frames(tester, 20);

  if (!want.opens) {
    expect(find.byType(FeedScreen), findsNothing);
    expect(find.text('No moves to watch yet'), findsOneWidget);
    await _close(tester, container);
    return;
  }

  // Feed, on this game, with Feed's own posts after it.
  expect(find.byType(FeedScreen), findsOneWidget);
  final lead = find.byKey(
    ValueKey('watch:game:${game.gameId}'),
    skipOffstage: false,
  );
  expect(lead, findsOneWidget);
  final clip = tester.widget<FeedClip>(lead);
  expect(clip.isCurrent, isTrue);
  expect(clip.item.plyCount, want.plies);
  expect(
    find.byKey(const ValueKey('game:f1'), skipOffstage: false),
    findsOneWidget,
  );

  // What the board offers, and nothing it does not.
  Finder onLead(String key) => find.descendant(
    of: lead,
    matching: find.byKey(ValueKey(key), skipOffstage: false),
    skipOffstage: false,
  );
  expect(onLead('feed_like_button'), want.like ? findsOneWidget : findsNothing);
  expect(onLead('feed_save_button'), want.save ? findsOneWidget : findsNothing);
  expect(onLead('feed_share_button'), findsOneWidget);
  expect(clip.item.hideEvaluation, want.hideEvaluation);
  expect(clip.item.hideResult, want.hideResult);
  expect(
    onLead('feed_eval_bar'),
    want.hideEvaluation ? findsNothing : findsOneWidget,
  );
  if (want.hideResult || !want.result) {
    expect(clip.item.result, isNull);
  } else {
    expect(clip.item.result, isNotNull);
  }

  // Analyze: back to this same board.
  await tester.tap(onLead('feed_analyze_button'));
  await _frames(tester, 20);
  expect(find.byType(FeedScreen), findsNothing);
  expect(find.byType(ChessBoardScreenNew), findsOneWidget);

  await _close(tester, container);
}

Future<void> _frames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Unmounts inside the fake clock and runs out the timers the board and Feed
/// leave behind (debounced writes, nudges).
Future<void> _close(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  container.dispose();
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(seconds: 10));
  }
}

Games _raw({required String id, required String pgn, required String status}) {
  return Games(
    id: id,
    roundId: 'round-1',
    roundSlug: 'round-1',
    tourId: 'tour-1',
    tourSlug: 'test-open-2026',
    players: [
      _player(name: 'White A', fideId: 1),
      _player(name: 'Black B', fideId: 2),
    ],
    boardNr: 1,
    status: status,
    lastMove: 'e1e2',
    pgn: pgn,
  );
}

Player _player({required String name, required int fideId}) => Player(
  name: name,
  title: 'GM',
  rating: 2700,
  fideId: fideId,
  fed: 'USA',
  clock: 0,
  team: '',
);

GamesTourModel _model(
  String id, {
  required GameSource source,
  required String pgn,
  String? sourceGameId,
}) {
  PlayerCard card(String name) => PlayerCard(
    name: name,
    federation: '',
    title: '',
    rating: 0,
    countryCode: '',
    team: null,
  );
  return GamesTourModel(
    gameId: id,
    sourceGameId: sourceGameId,
    source: source,
    whitePlayer: card('White A'),
    blackPlayer: card('Black B'),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: pgn.contains('1-0') ? GameStatus.whiteWins : GameStatus.unknown,
    tourId: 'Test Open 2026',
    roundId: 'round-1',
    pgn: pgn,
  );
}

SavedAnalysisData _saved(
  GamesTourModel game,
  String pgn, {
  required String folderId,
}) => SavedAnalysisData(
  analysisId: 'analysis-${game.gameId}',
  sourceGameId: game.sourceGameId,
  chessGame: ChessGame.fromPgn(game.gameId, pgn),
  variationComments: const {},
  isBoardFlipped: false,
  lastViewedPosition: 0,
  folderId: folderId,
);

FeedItem _feedPost(String id) => feedWatchItem(
  GamesTourModel(
    gameId: id,
    whitePlayer: PlayerCard(
      name: 'Carlsen, Magnus',
      federation: '',
      title: 'GM',
      rating: 2830,
      countryCode: '',
      team: null,
    ),
    blackPlayer: PlayerCard(
      name: 'Nakamura, Hikaru',
      federation: '',
      title: 'GM',
      rating: 2802,
      countryCode: '',
      team: null,
    ),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.blackWins,
    tourId: 'tour-9',
    roundId: 'round-9',
  ),
  '[Event "Feed Open"]\n[Result "0-1"]\n\n'
  '1. f3 e5 2. g4 Qh4# 0-1',
)!;

class _FakeFeed extends FeedNotifier {
  _FakeFeed(this._items);

  final List<FeedItem> _items;

  @override
  Future<List<FeedItem>> build() async => _items;

  @override
  Future<void> loadMore() async {}

  @override
  void onVisible(int index) {}

  @override
  FeedMore get more => FeedMore.exhausted;
}

class _Games extends GameRepository {
  _Games(this.games);

  final Map<String, Games> games;

  @override
  Future<Games> getGameWithPGN(String gameId) async => games[gameId]!;

  @override
  Future<String?> getGamePgn(String gameId) async => games[gameId]?.pgn;
}

class _CachedGames extends GamesLocalStorage {
  _CachedGames(super.ref, this.byTour);

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

class _Gamebase extends GamebaseRepository {
  _Gamebase() : super(Dio(), baseUrl: 'http://localhost', apiKey: 'test');

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

class _NoStream extends GameStreamRepository {
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

class _EngineOff extends AsyncNotifier<EngineSettings>
    implements EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async =>
      const EngineSettings(showEngineAnalysis: false, showEngineGauge: false);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _OverlayOff extends GamebaseOverlayEnabledNotifier {
  @override
  Future<bool> build() async => false;

  @override
  Future<void> setEnabled(bool enabled) async {
    state = AsyncValue.data(enabled);
  }

  @override
  Future<void> toggle() => setEnabled(!(state.valueOrNull ?? false));
}

class _NoSpoilers extends EventNoSpoilersController {
  _NoSpoilers({
    required super.ref,
    required super.tourId,
    required this.enabled,
  });

  final bool enabled;

  @override
  Future<void> load() async {
    state = EventNoSpoilersState(enabled: enabled, isLoading: false);
  }
}

class _NoEvalCache extends LocalEvalCache {
  _NoEvalCache(super.ref);

  @override
  Future<CloudEval?> fetch(
    String fen, {
    int? multiPV,
    int minDepth = 0,
  }) async => null;

  @override
  Future<void> save(String fen, CloudEval eval, {int? multiPV}) async {}
}

class _QuietSfx implements FeedSfx {
  @override
  bool muted = false;

  @override
  bool boardSoundEnabled = true;

  @override
  Future<void> warmUp() async {}

  @override
  void playSwipe() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _QuietMoveSound extends FeedMoveSound {
  _QuietMoveSound(super.sfx);

  @override
  void play({required String san, MoveClass? moveClass, bool fast = false}) {}
}

class _NoFeedEngine extends FeedEngine {
  @override
  Future<CloudEval?> evaluate(
    String fen, {
    required void Function(List<Pv> pvs, int depth) onUpdate,
  }) async => null;

  @override
  Future<void> cancel() async {}
}

class _TestBoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

class _NoLikes extends LikedGamesNotifier {
  @override
  Future<List<SavedAnalysis>> build() async => const [];
}

class _NoShortcuts extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];
}

class _Subscribed extends SubscriptionNotifier {
  _Subscribed() : super() {
    state = SubscriptionState(isSubscribed: true, isLoading: false);
  }

  @override
  set state(SubscriptionState value) =>
      super.state = value.copyWith(isSubscribed: true, isLoading: false);
}
