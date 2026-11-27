import 'package:chessever2/providers/board_engine_lines_visibility_provider.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/settings/widgets/engine_settings_body.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test('default line count is three and explicit five is retained', () {
    expect(const EngineSettings().multiPvForStockfish(), 3);
    expect(
      const EngineSettings(principalVariationIndex: 4).multiPvForStockfish(),
      5,
    );
  });

  testWidgets('evaluation bar settings expose board and grid controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          boardEngineLinesVisibleProvider.overrideWith(_VisibleBoardLines.new),
          engineSettingsProviderNew.overrideWith(
            () => _FakeEngineSettingsNotifier(const EngineSettings()),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [AppColors.dark]),
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: SingleChildScrollView(
                  child: EngineSettingsBody(trackPersist: (_) {}),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Evaluation Bar'), findsOneWidget);
    expect(find.byKey(const ValueKey('toby-switch')), findsNothing);
    expect(find.byKey(const ValueKey('engine-source-toby')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('engine-source-stockfish')),
      findsOneWidget,
    );
    expect(find.text('Board View'), findsOneWidget);
    expect(find.text('Grid View'), findsOneWidget);
    expect(find.text('Computer Analysis'), findsNothing);
    expect(find.byKey(const ValueKey('engine-source-subtitle')), findsNothing);
    expect(find.text('Both'), findsOneWidget);
    expect(find.byTooltip('About Toby'), findsNothing);
    expect(find.textContaining('Off hides in-game lines'), findsNothing);
    final titles = [
      'Evaluation Bar',
      'Engine',
      'Engine Lines',
      'Show Arrows',
      'Arrow Count',
      'Number of Lines',
      'Thinking Time',
      'Analysis Depth Indicator',
    ];
    expect(
      titles.map((title) => tester.getTopLeft(find.text(title)).dy),
      orderedEquals(
        titles.map((title) => tester.getTopLeft(find.text(title)).dy).toList()
          ..sort(),
      ),
    );

    expect(
      find.byKey(const ValueKey('evaluation-bar-master-switch')),
      findsNothing,
    );
    expect(
      tester
          .widget<Switch>(
            find.byKey(const ValueKey('evaluation-bar-board-switch')),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<Switch>(
            find.byKey(const ValueKey('evaluation-bar-grid-switch')),
          )
          .value,
      isTrue,
    );
  });

  testWidgets('legacy master off keeps both surfaces effectively off', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          boardEngineLinesVisibleProvider.overrideWith(_VisibleBoardLines.new),
          engineSettingsProviderNew.overrideWith(
            () => _FakeEngineSettingsNotifier(
              const EngineSettings(
                showEngineGauge: false,
                tobyEnabled: false,
                engineSource: EngineSource.toby,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [AppColors.dark]),
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: SingleChildScrollView(
                  child: EngineSettingsBody(trackPersist: (_) {}),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('engine-source-toby')), findsOneWidget);
    final board = tester.widget<Switch>(
      find.byKey(const ValueKey('evaluation-bar-board-switch')),
    );
    final grid = tester.widget<Switch>(
      find.byKey(const ValueKey('evaluation-bar-grid-switch')),
    );
    expect(board.value, isFalse);
    expect(board.onChanged, isNotNull);
    expect(grid.value, isFalse);
    expect(grid.onChanged, isNotNull);
    await tester.tap(find.byKey(const ValueKey('evaluation-bar-board-switch')));
    await tester.pump();
    expect(
      tester
          .widget<Switch>(
            find.byKey(const ValueKey('evaluation-bar-board-switch')),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<Switch>(
            find.byKey(const ValueKey('evaluation-bar-grid-switch')),
          )
          .value,
      isFalse,
    );
  });

  test(
    'local evaluation controls reload without overwriting the account master',
    () {
      final choice = const EngineSettings(
        showEngineGauge: false,
      ).withGaugeVisibility(board: true);
      final reloaded = applyDeviceLocalEngineSettings(
        const EngineSettings(showEngineGauge: false),
        {
          'independentGaugeControls': choice.independentGaugeControls,
          'showEngineGaugeOnBoard': choice.showEngineGaugeOnBoard,
          'showEngineGaugeInGrid': choice.showEngineGaugeInGrid,
        },
      );
      expect(reloaded.showEngineGauge, isFalse);
      expect(reloaded.shouldShowEngineGaugeOnBoard, isTrue);
      expect(reloaded.shouldShowEngineGaugeInGrid, isFalse);
    },
  );

  testWidgets('board and grid switches update independently', (tester) async {
    late _FakeEngineSettingsNotifier notifier;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          boardEngineLinesVisibleProvider.overrideWith(_VisibleBoardLines.new),
          engineSettingsProviderNew.overrideWith(
            () =>
                notifier = _FakeEngineSettingsNotifier(const EngineSettings()),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: const [AppColors.dark]),
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: SingleChildScrollView(
                  child: EngineSettingsBody(trackPersist: (_) {}),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('evaluation-bar-board-switch')));
    await tester.pump();

    expect(notifier.state.requireValue.showEngineGaugeOnBoard, isFalse);
    expect(notifier.state.requireValue.showEngineGaugeInGrid, isTrue);
    expect(
      tester
          .widget<Switch>(
            find.byKey(const ValueKey('evaluation-bar-board-switch')),
          )
          .value,
      isFalse,
    );
    expect(
      tester
          .widget<Switch>(
            find.byKey(const ValueKey('evaluation-bar-grid-switch')),
          )
          .value,
      isTrue,
    );
  });
}

class _VisibleBoardLines extends BoardEngineLinesVisibleNotifier {
  @override
  Future<bool> build() async => true;
}

class _FakeEngineSettingsNotifier extends EngineSettingsNotifierNew {
  _FakeEngineSettingsNotifier(this.settings);

  final EngineSettings settings;

  @override
  Future<EngineSettings> build() async => settings;

  @override
  Future<void> toggleEngineGauge(bool value) async {
    state = AsyncValue.data(
      state.requireValue.copyWith(showEngineGauge: value),
    );
  }

  @override
  Future<void> toggleEngineGaugeOnBoard(bool value) async {
    state = AsyncValue.data(
      state.requireValue.withGaugeVisibility(board: value),
    );
  }

  @override
  Future<void> toggleEngineGaugeInGrid(bool value) async {
    state = AsyncValue.data(
      state.requireValue.withGaugeVisibility(grid: value),
    );
  }
}
