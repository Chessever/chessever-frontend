import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/gamebase/gamebase_explorer_screen.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/explorer_eval_provider.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_explorer_state.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _FakeGamebaseRepository extends GamebaseRepository {
  _FakeGamebaseRepository({this.players = const []})
    : super(Dio(), baseUrl: 'http://localhost', apiKey: 'test');

  final List<GamebasePlayer> players;

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
  }) async {
    return const GamebaseResponse(
      status: 'success',
      data: GamebaseData(moves: []),
    );
  }

  @override
  Future<List<GamebasePlayer>> getPlayers({
    String? name,
    String? fideId,
    int pageNumber = 0,
    int pageSize = 20,
  }) async {
    final query = name?.trim().toLowerCase() ?? '';
    if (query.length < 2) {
      return const [];
    }

    return players
        .where((player) {
          return player.name.toLowerCase().contains(query) ||
              player.displayName.toLowerCase().contains(query) ||
              player.titleAndName.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }
}

class _TestSubscriptionNotifier extends SubscriptionNotifier {
  _TestSubscriptionNotifier({required bool isSubscribed}) : super() {
    state = SubscriptionState(isSubscribed: isSubscribed);
  }
}

class _TestEngineSettingsNotifier extends EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async {
    const settings = EngineSettings(showEngineAnalysis: false);
    state = const AsyncValue.data(settings);
    return settings;
  }
}

class _TestBoardSettingsNotifier extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async {
    const settings = BoardSettingsNew();
    state = const AsyncValue.data(settings);
    return settings;
  }
}

class _TestExplorerEvalNotifier extends ExplorerEvalNotifier {
  _TestExplorerEvalNotifier(super.ref);

  @override
  void setEngineEnabled({
    required bool enabled,
    required String fen,
    bool force = false,
  }) {
    state = state.copyWith(
      fen: fen,
      isEvaluating: false,
      depth: 0,
      pvLines: const [],
      clearEval: true,
      clearMate: true,
    );
  }

  @override
  void evaluatePosition(String fen, {bool force = false}) {
    state = state.copyWith(
      fen: fen,
      isEvaluating: false,
      depth: 0,
      pvLines: const [],
      clearEval: true,
      clearMate: true,
    );
  }
}

GamebasePlayer _magnus() {
  return const GamebasePlayer(
    id: 'player-1',
    fideId: '1503014',
    name: 'Carlsen, Magnus',
    gender: PlayerGender.male,
    fed: 'NOR',
    title: 'GM',
    ratingClassical: 2830,
    ratingRapid: 2818,
    ratingBlitz: 2883,
  );
}

ProviderContainer _createContainer({required bool isSubscribed}) {
  final magnus = _magnus();
  return ProviderContainer(
    overrides: [
      gamebaseRepositoryProvider.overrideWithValue(
        _FakeGamebaseRepository(players: [magnus]),
      ),
      subscriptionProvider.overrideWith(
        (ref) => _TestSubscriptionNotifier(isSubscribed: isSubscribed),
      ),
      engineSettingsProviderNew.overrideWith(_TestEngineSettingsNotifier.new),
      boardSettingsProviderNew.overrideWith(_TestBoardSettingsNotifier.new),
      explorerEvalProvider.overrideWith(
        (ref) => _TestExplorerEvalNotifier(ref),
      ),
    ],
  );
}

Future<void> _pumpExplorer(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return const GamebaseExplorerScreen();
          },
        ),
      ),
    ),
  );

  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> _openFilters(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Filters'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'unsubscribed users see a locked player field and applied filters drop player state',
    (tester) async {
      final container = _createContainer(isSubscribed: false);
      addTearDown(container.dispose);

      await _pumpExplorer(tester, container);

      final magnus = _magnus();
      container
          .read(gamebaseExplorerProvider.notifier)
          .updateFilters(
            GamebaseFilters(
              playerIds: [magnus.id],
              selectedPlayers: [magnus],
              playerColor: GamebasePlayerColor.white,
            ),
          );
      await tester.pumpAndSettle();

      await _openFilters(tester);

      final playerField = tester.widget<TextField>(find.byType(TextField));
      expect(playerField.readOnly, isTrue);

      await tester.ensureVisible(find.text('Apply'));
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      final filters = container.read(gamebaseExplorerProvider).filters;
      expect(filters.playerIds, isEmpty);
      expect(filters.selectedPlayers, isEmpty);
      expect(filters.playerColor, isNull);
    },
  );

  testWidgets(
    'subscribed users can search and apply a player filter from the explorer sheet',
    (tester) async {
      final container = _createContainer(isSubscribed: true);
      addTearDown(container.dispose);

      await _pumpExplorer(tester, container);
      await _openFilters(tester);

      final playerField = tester.widget<TextField>(find.byType(TextField));
      expect(playerField.readOnly, isFalse);

      await tester.enterText(find.byType(TextField), 'Magn');
      await tester.pumpAndSettle();

      expect(find.text('GM Magnus Carlsen'), findsOneWidget);

      await tester.tap(find.text('GM Magnus Carlsen'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Apply'));
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      final filters = container.read(gamebaseExplorerProvider).filters;
      expect(filters.playerIds, ['player-1']);
      expect(filters.selectedPlayers.map((player) => player.id), ['player-1']);
      expect(filters.playerColor, isNull);
    },
  );
}
