import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/settings/widgets/engine_settings_body.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  testWidgets('evaluation bar settings expose board and grid controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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
    expect(find.text('Board View'), findsOneWidget);
    expect(find.text('Grid View'), findsOneWidget);

    expect(
      tester
          .widget<Switch>(
            find.byKey(const ValueKey('evaluation-bar-master-switch')),
          )
          .value,
      isTrue,
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

  testWidgets('master off keeps child choices on but disables their controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          engineSettingsProviderNew.overrideWith(
            () => _FakeEngineSettingsNotifier(
              const EngineSettings(showEngineGauge: false),
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

    final master = tester.widget<Switch>(
      find.byKey(const ValueKey('evaluation-bar-master-switch')),
    );
    final board = tester.widget<Switch>(
      find.byKey(const ValueKey('evaluation-bar-board-switch')),
    );
    final grid = tester.widget<Switch>(
      find.byKey(const ValueKey('evaluation-bar-grid-switch')),
    );
    expect(master.value, isFalse);
    expect(board.value, isTrue);
    expect(board.onChanged, isNull);
    expect(grid.value, isTrue);
    expect(grid.onChanged, isNull);
  });

  testWidgets('board and grid switches update independently', (tester) async {
    late _FakeEngineSettingsNotifier notifier;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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
      state.requireValue.copyWith(showEngineGaugeOnBoard: value),
    );
  }

  @override
  Future<void> toggleEngineGaugeInGrid(bool value) async {
    state = AsyncValue.data(
      state.requireValue.copyWith(showEngineGaugeInGrid: value),
    );
  }
}
