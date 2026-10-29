import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/for_you/discovery/data/discovery_repository.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/models/report_game_type.dart';
import 'package:chessever2/screens/for_you/discovery/reports_screen.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_game_cards.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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

class _NoSpoilers extends EventNoSpoilersController {
  _NoSpoilers({required super.ref, required super.tourId});

  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(enabled: false, isLoading: false);
  }
}

class _ReportsRepository implements DiscoveryRepository {
  _ReportsRepository(this.page);

  final List<GamesTourModel> page;

  @override
  Future<AnalyzedGamesPage> fetchAnalyzedGamesPage({
    int pageSize = 30,
    AnalyzedGamesCursor? after,
    DateTime? since,
    ReportGameType? gameType,
  }) async => AnalyzedGamesPage(items: page);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected call');
}

/// 1. e4 e5 2. Nf3 Nc6, as the `fen` column writes it.
const _afterNc6 =
    'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3';

/// A saved report: an eval after every move, +1.36 after the last one.
const _reportPgn = '''
[Event "Test"]

1. e4 { [%eval 0.30] } 1... e5 { [%eval 0.25] } 2. Nf3 \$1 { [%eval 0.31] } 2... Nc6 { [%eval 1.36] } 1-0
''';

GamesTourModel _report() {
  PlayerCard player(String name) => PlayerCard(
    name: name,
    federation: 'IND',
    title: 'GM',
    rating: 2700,
    countryCode: 'IN',
    team: null,
  );
  return GamesTourModel(
    gameId: 'report',
    whitePlayer: player('White, Player'),
    blackPlayer: player('Black, Player'),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.whiteWins,
    roundId: 'round-1',
    tourId: 'tour-1',
    fen: _afterNc6,
    lastMove: 'b8c6',
    pgn: _reportPgn,
    lastMoveTime: DateTime.utc(2026, 10, 29),
  );
}

/// What the caches answer for every position: +0.40.
CloudEval _cached(String fen) => CloudEval(
  fen: fen,
  knodes: 0,
  depth: 20,
  pvs: [Pv(moves: 'e2e4', cp: 40)],
  requestedMultiPv: 1,
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget child,
  GamesListViewMode mode,
) async {
  const screen = Size(393, 852);
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      gamesListViewModeProvider.overrideWithValue(mode),
      boardSettingsProviderNew.overrideWith(_BoardSettings.new),
      engineSettingsProviderNew.overrideWith(_EngineSettings.new),
      playerPhotoProvider.overrideWith((ref, fideId) async => null),
      eventNoSpoilersProvider.overrideWith(
        (ref, tourId) => _NoSpoilers(ref: ref, tourId: tourId),
      ),
      gameCardEvalWithStockfishFallbackProvider.overrideWith(
        (ref, fen) async => _cached(fen),
      ),
      gameCardEvalCacheOnlyProvider.overrideWith(
        (ref, fen) async => _cached(fen),
      ),
      discoveryRepositoryProvider.overrideWithValue(
        _ReportsRepository([_report()]),
      ),
      premiumAccessProvider.overrideWithValue(true),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(body: child);
          },
        ),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  return container;
}

Future<void> _teardown(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
  container.dispose();
}

void main() {
  for (final mode in [
    GamesListViewMode.chessBoardGrid,
    GamesListViewMode.chessBoard,
  ]) {
    testWidgets('Reports cards show the eval the report recorded ($mode)', (
      tester,
    ) async {
      final container = await _pump(tester, const ReportsScreen(), mode);

      expect(find.byType(DiscoveryGameCard), findsOneWidget);
      expect(find.text('+1.4'), findsOneWidget);
      expect(find.text('+0.4'), findsNothing);
      expect(tester.takeException(), isNull);
      await _teardown(tester, container);
    });

    testWidgets('other lists keep asking the caches ($mode)', (tester) async {
      final container = await _pump(
        tester,
        SingleChildScrollView(
          child: DiscoveryGameList(games: [_report()], streamEnabled: false),
        ),
        mode,
      );

      expect(find.text('+0.4'), findsOneWidget);
      expect(find.text('+1.4'), findsNothing);
      expect(tester.takeException(), isNull);
      await _teardown(tester, container);
    });
  }
}
