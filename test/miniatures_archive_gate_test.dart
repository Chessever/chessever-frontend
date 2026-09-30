import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_access.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_games_tab.dart';
import 'package:chessever2/screens/library/miniatures/widgets/miniatures_archive_gate.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Subscription double without RevenueCat's constructor side effects.
class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription(bool subscribed)
    : super(SubscriptionState(isSubscribed: subscribed));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Settings doubles, so game cards never open SQLite.
class _EngineSettings extends EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async =>
      const EngineSettings(showEngineAnalysis: false);
}

class _BoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

/// Serves one fixed page and counts how often the list asks for more.
class _FakeGamebase extends GamebaseRepository {
  _FakeGamebase(this.page) : super(Dio(), apiKey: 'test-key');

  final GamebaseMiniaturesPage page;
  int calls = 0;

  @override
  Future<GamebaseMiniaturesPage> getMiniatures({
    MiniatureGamesFilter filter = MiniatureGamesFilter.defaultFilter,
    int limit = 50,
    int offset = 0,
  }) async {
    calls++;
    return page;
  }
}

GamebaseMiniature _mini(String id, DateTime date) => GamebaseMiniature(
  gameId: id,
  plyCount: 30,
  finalMoveNumber: 15,
  result: 'W',
  timeControl: 'CLASSICAL',
  isOnline: false,
  date: date,
  whiteName: 'White $id',
  blackName: 'Black $id',
);

/// Wed 23 Sep 2026, mid-afternoon local.
final _now = DateTime(2026, 9, 23, 15);

Widget _app(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(body: child);
        },
      ),
    ),
  );
}

void main() {
  group('MiniaturesDateControl', () {
    testWidgets('reads Today, steps back through the gate, never forward', (
      tester,
    ) async {
      var earlier = 0;
      await tester.pumpWidget(
        _app(MiniaturesDateControl(now: _now, onEarlier: () => earlier++)),
      );

      expect(
        find.text('Today  ·  Wed 23 Sep', findRichText: true),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('Premium')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('miniatures_date_earlier')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(earlier, 1);

      // The next day does not exist yet: the chevron is not a control.
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pump(const Duration(milliseconds: 300));
      expect(earlier, 1);
    });

    testWidgets('the earlier-day step is a full 44dp target', (tester) async {
      await tester.pumpWidget(
        _app(MiniaturesDateControl(now: _now, onEarlier: () {})),
      );

      final size = tester.getSize(
        find.byKey(const ValueKey('miniatures_date_earlier')),
      );
      expect(size.height, greaterThanOrEqualTo(44));
    });
  });

  group('MiniaturesArchiveBoundary', () {
    testWidgets('names the outcome and opens the gate', (tester) async {
      var explored = 0;
      await tester.pumpWidget(
        _app(MiniaturesArchiveBoundary(onExplore: () => explored++)),
      );

      expect(find.text(kMiniaturesArchiveCta), findsOneWidget);
      expect(find.text('No miniatures yet today'), findsNothing);

      await tester.tap(find.text(kMiniaturesArchiveCta));
      await tester.pump(const Duration(milliseconds: 300));
      expect(explored, 1);
    });

    testWidgets('leads with an empty Today when there is nothing yet', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(MiniaturesArchiveBoundary(todayEmpty: true, onExplore: () {})),
      );

      expect(find.text('No miniatures yet today'), findsOneWidget);
      expect(find.text(kMiniaturesArchiveCta), findsOneWidget);
    });
  });

  group('MiniaturesGamesTab', () {
    /// Only earlier days loaded, with plenty more on the server.
    final archiveOnly = GamebaseMiniaturesPage(
      items: [
        _mini('yesterday', DateTime.utc(2026, 9, 22)),
        _mini('last-week', DateTime.utc(2026, 9, 16)),
      ],
      total: 500,
      limit: 50,
      offset: 0,
    );

    Future<_FakeGamebase> pumpTab(
      WidgetTester tester, {
      required bool subscribed,
    }) async {
      final gamebase = _FakeGamebase(archiveOnly);
      await tester.pumpWidget(
        _app(
          MiniaturesGamesTab(now: _now),
          overrides: [
            gamebaseRepositoryProvider.overrideWithValue(gamebase),
            subscriptionProvider.overrideWith(
              (ref) => _Subscription(subscribed),
            ),
            gamesListViewModeProvider.overrideWithValue(
              GamesListViewMode.gamesCard,
            ),
            engineSettingsProviderNew.overrideWith(_EngineSettings.new),
            boardSettingsProviderNew.overrideWith(_BoardSettings.new),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();
      return gamebase;
    }

    testWidgets(
      'a free account sees Today, the date control and the archive boundary',
      (tester) async {
        final gamebase = await pumpTab(tester, subscribed: false);

        expect(
          find.byKey(const ValueKey('miniatures_date_earlier')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('miniatures_archive_boundary')),
          findsOneWidget,
        );
        expect(find.text('No miniatures yet today'), findsOneWidget);
        expect(find.text(kMiniaturesArchiveCta), findsOneWidget);
        // Earlier days are not browsable, and the empty Today is not passed
        // off as "no miniatures at all".
        expect(find.textContaining('White yesterday'), findsNothing);
        expect(find.text('No miniatures found'), findsNothing);

        // Paging stopped at the boundary: more pages would only be hidden.
        await tester.pump(const Duration(milliseconds: 500));
        expect(gamebase.calls, 1);
      },
    );

    /// Game cards start short animations; let them finish before teardown.
    Future<void> drain(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    }

    testWidgets('a subscriber browses every day with no boundary', (
      tester,
    ) async {
      await pumpTab(tester, subscribed: true);

      expect(
        find.byKey(const ValueKey('miniatures_date_earlier')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('miniatures_archive_boundary')),
        findsNothing,
      );
      expect(find.text('Yesterday'), findsOneWidget);

      await drain(tester);
    });

    testWidgets('stepping back through the gate resumes on the earlier days', (
      tester,
    ) async {
      // Tests run as a debug build, where the guard passes: this is the path
      // a confirmed purchase takes once the paywall closes.
      await pumpTab(tester, subscribed: false);
      expect(find.text('Yesterday'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('miniatures_date_earlier')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Yesterday'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('miniatures_date_earlier')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('miniatures_archive_boundary')),
        findsNothing,
      );

      await drain(tester);
    });
  });
}
