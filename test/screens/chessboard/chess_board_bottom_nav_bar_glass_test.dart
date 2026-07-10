import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_nav_bar.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

class _TestEngineSettingsNotifier extends AsyncNotifier<EngineSettings>
    implements EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async => const EngineSettings();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<void> _pumpControls(
  WidgetTester tester, {
  required ThemeData theme,
  required TextScaler textScaler,
  VoidCallback? onGamebase,
  VoidCallback? onEngine,
  VoidCallback? onEngineLongPress,
  VoidCallback? onFlip,
  VoidCallback? onBack,
  VoidCallback? onBackLongPressStart,
  VoidCallback? onBackLongPressEnd,
  VoidCallback? onForward,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 640);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        engineSettingsProviderNew.overrideWith(_TestEngineSettingsNotifier.new),
      ],
      child: LiquidGlassWidgets.wrap(
        child: MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              final media = MediaQuery.of(context).copyWith(
                textScaler: textScaler,
                disableAnimations: true,
                viewPadding: const EdgeInsets.only(bottom: 34),
                padding: const EdgeInsets.only(bottom: 34),
              );
              return MediaQuery(
                data: media,
                child: Scaffold(
                  body: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 34),
                      child: ChessBoardBottomNavBar(
                        gameIndex: 0,
                        showGamebaseButton: true,
                        isGamebaseActive: true,
                        showEngineAnalysis: true,
                        showUnseenMoveBadge: true,
                        canMoveBackward: true,
                        canMoveForward: true,
                        onGamebaseToggle: onGamebase,
                        toggleEngineVisibility: onEngine,
                        onEngineSettingsLongPress: onEngineLongPress,
                        onFlip: onFlip ?? () {},
                        onLeftMove: onBack,
                        onLongPressBackwardStart: onBackLongPressStart,
                        onLongPressBackwardEnd: onBackLongPressEnd,
                        onRightMove: onForward,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'five controls stay floating, 48pt, and overflow-free in dark mode at '
    'large Dynamic Type',
    (tester) async {
      await _pumpControls(
        tester,
        theme: AppTheme.darkTheme,
        textScaler: const TextScaler.linear(3),
      );

      expect(tester.takeException(), isNull);

      final island = find.byKey(
        const ValueKey<String>('board-floating-bottom-controls'),
      );
      expect(island, findsOneWidget);
      final islandSize = tester.getSize(island);
      expect(islandSize.width, lessThan(320));
      expect(islandSize.height, inInclusiveRange(56, 88));

      for (final id in <String>[
        E2eIds.boardGamebaseToggle,
        E2eIds.boardEngineToggle,
        E2eIds.boardFlip,
        E2eIds.boardMoveBack,
        E2eIds.boardMoveForward,
      ]) {
        final control = find.byKey(e2eKey(id));
        expect(control, findsOneWidget, reason: id);
        final size = tester.getSize(control);
        expect(size.width, greaterThanOrEqualTo(48), reason: id);
        expect(size.height, greaterThanOrEqualTo(48), reason: id);
      }
    },
  );

  testWidgets(
    'light-mode controls retain callbacks, long press, and semantics',
    (tester) async {
      var gamebaseTaps = 0;
      var engineTaps = 0;
      var engineLongPresses = 0;
      var flipTaps = 0;
      var backTaps = 0;
      var backLongPressStarts = 0;
      var backLongPressEnds = 0;
      var forwardTaps = 0;

      final semantics = tester.ensureSemantics();

      await _pumpControls(
        tester,
        theme: AppTheme.lightTheme,
        textScaler: TextScaler.noScaling,
        onGamebase: () => gamebaseTaps++,
        onEngine: () => engineTaps++,
        onEngineLongPress: () => engineLongPresses++,
        onFlip: () => flipTaps++,
        onBack: () => backTaps++,
        onBackLongPressStart: () => backLongPressStarts++,
        onBackLongPressEnd: () => backLongPressEnds++,
        onForward: () => forwardTaps++,
      );

      expect(find.bySemanticsLabel('Chess board controls'), findsOneWidget);
      expect(find.bySemanticsLabel('Flip board'), findsOneWidget);
      expect(find.bySemanticsLabel('Hide Gamebase explorer'), findsOneWidget);

      await tester.tap(find.byKey(e2eKey(E2eIds.boardGamebaseToggle)));
      await tester.tap(find.byKey(e2eKey(E2eIds.boardEngineToggle)));
      await tester.tap(find.byKey(e2eKey(E2eIds.boardFlip)));
      await tester.tap(find.byKey(e2eKey(E2eIds.boardMoveBack)));
      await tester.tap(find.byKey(e2eKey(E2eIds.boardMoveForward)));
      await tester.pump();

      expect(gamebaseTaps, 1);
      expect(engineTaps, 1);
      expect(flipTaps, 1);
      expect(backTaps, 1);
      expect(forwardTaps, 1);

      final backLongPressEndsBeforeHold = backLongPressEnds;
      await tester.longPress(find.byKey(e2eKey(E2eIds.boardEngineToggle)));
      await tester.longPress(find.byKey(e2eKey(E2eIds.boardMoveBack)));
      await tester.pump();

      expect(engineLongPresses, 1);
      expect(backLongPressStarts, 1);
      expect(backLongPressEnds, backLongPressEndsBeforeHold + 1);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
}
