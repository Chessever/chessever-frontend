import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:chessever2/screens/chessboard/widgets/board_arrow_key_shortcuts.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_nav_bar.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _Settings extends EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async => const EngineSettings();
}

Widget _app(Widget child, {GlobalKey<NavigatorState>? navigatorKey}) =>
    MaterialApp(
      navigatorKey: navigatorKey,
      home: Scaffold(body: child),
    );

Widget _shortcuts({
  bool active = true,
  VoidCallback? previous,
  VoidCallback? next,
  Widget child = const SizedBox.expand(),
}) => BoardArrowKeyShortcuts(
  isActivePage: active,
  onPrevious: previous,
  onNext: next,
  child: child,
);

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
      '$platform: real bottom-bar keyboard/touch parity and boundaries',
      (tester) async {
        final nav = ChessGameNavigator(
          ChessGame.fromPgn('keyboard-game', '1. e4 e5 2. Nf3 *'),
        );
        addTearDown(nav.dispose);
        var backwardCalls = 0;
        var forwardCalls = 0;
        late StateSetter rebuild;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              engineSettingsProviderNew.overrideWith(_Settings.new),
              engineDepthStatusProvider.overrideWithValue(null),
            ],
            child: MaterialApp(
              theme: AppTheme.darkTheme.copyWith(platform: platform),
              home: StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  ResponsiveHelper.init(context);
                  return Scaffold(
                    bottomNavigationBar: ChessBoardBottomNavBar(
                      gameIndex: 0,
                      onFlip: () {},
                      onLeftMove: () => setState(() {
                        backwardCalls++;
                        nav.goToPreviousMove();
                      }),
                      onRightMove: () => setState(() {
                        forwardCalls++;
                        nav.goToNextMove();
                      }),
                      canMoveForward: nav.state.canGoForward,
                      canMoveBackward: nav.state.canGoBackward,
                      showEngineAnalysis: false,
                      showUnseenMoveBadge: false,
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();
        final focusBefore = FocusManager.instance.primaryFocus;
        await _press(tester, LogicalKeyboardKey.arrowLeft);
        expect(backwardCalls, 0);
        expect(nav.state.movePointer, isEmpty);
        await _press(tester, LogicalKeyboardKey.arrowRight);
        expect(forwardCalls, 1);
        expect(nav.state.movePointer, [0]);
        final firstFen = nav.state.currentFen;
        await _press(tester, LogicalKeyboardKey.arrowLeft);
        expect(backwardCalls, 1);
        await tester.tap(find.byKey(e2eKey(E2eIds.boardMoveForward)));
        await tester.pump();
        expect(nav.state.currentFen, firstFen);
        await tester.tap(find.byKey(e2eKey(E2eIds.boardMoveBack)));
        await tester.pump();
        expect(nav.state.movePointer, isEmpty);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(nav.state.movePointer, [0]);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(nav.state.movePointer, [1]);
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(nav.state.movePointer, [2]);
        final atEndCalls = forwardCalls;
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(forwardCalls, atEndCalls);
        expect(nav.state.game.mainline.length, 3);
        expect(FocusManager.instance.primaryFocus, same(focusBefore));

        // Exercise an existing continuation variation without new keyboard logic.
        nav.goToMovePointerUnchecked(<Number>[0]);
        nav.makeOrGoToMove('c7c5');
        nav.makeOrGoToMove('g1f3');
        final endOfVariation = List<Number>.of(nav.state.movePointer);
        rebuild(() {});
        await tester.pump();
        await tester.tap(find.byKey(e2eKey(E2eIds.boardMoveBack)));
        await tester.pump();
        final previousPointer = List<Number>.of(nav.state.movePointer);
        final previousFen = nav.state.currentFen;
        await _press(tester, LogicalKeyboardKey.arrowRight);
        expect(nav.state.movePointer, endOfVariation);
        await _press(tester, LogicalKeyboardKey.arrowLeft);
        expect(nav.state.movePointer, previousPointer);
        expect(nav.state.currentFen, previousFen);
        expect(nav.state.currentMove?.san, 'c5');
      },
    );
  }

  testWidgets(
    'unrelated and modifier arrows remain available to focused controls',
    (tester) async {
      var steps = 0;
      final received = <LogicalKeyboardKey>[];
      await tester.pumpWidget(
        _app(
          _shortcuts(
            previous: () => steps++,
            next: () => steps++,
            child: Focus(
              autofocus: true,
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent) received.add(event.logicalKey);
                return KeyEventResult.handled;
              },
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pump();
      for (final key in [
        LogicalKeyboardKey.keyA,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
      ]) {
        await _press(tester, key);
        expect(received.last, key);
      }
      for (final modifier in [
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.altLeft,
        LogicalKeyboardKey.metaLeft,
      ]) {
        await tester.sendKeyDownEvent(modifier);
        for (final arrow in [
          LogicalKeyboardKey.arrowLeft,
          LogicalKeyboardKey.arrowRight,
        ]) {
          await _press(tester, arrow);
          expect(received.last, arrow);
        }
        await tester.sendKeyUpEvent(modifier);
      }
      expect(steps, 0);
      received.clear();
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(steps, 1);
      expect(
        received,
        isEmpty,
        reason: 'handled exactly once, no focus fallback',
      );
    },
  );

  for (final readOnly in [false, true]) {
    testWidgets('editable focus ancestry preserves caret (readOnly=$readOnly)', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'abcd');
      final fieldFocus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(fieldFocus.dispose);
      var steps = 0;
      await tester.pumpWidget(
        _app(
          _shortcuts(
            previous: () => steps++,
            next: () => steps++,
            child: TextField(
              controller: controller,
              focusNode: fieldFocus,
              readOnly: readOnly,
            ),
          ),
        ),
      );
      fieldFocus.requestFocus();
      controller.selection = const TextSelection.collapsed(offset: 2);
      await tester.pump();
      expect(fieldFocus.hasFocus, isTrue);
      // Flutter attaches the primary focus to a Focus, not EditableText itself.
      expect(
        FocusManager.instance.primaryFocus!.context!.widget,
        isNot(isA<EditableText>()),
      );
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      expect(controller.selection.baseOffset, 1);
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(controller.selection.baseOffset, 2);
      expect(steps, 0);
      expect(controller.text, 'abcd');
      fieldFocus.unfocus();
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(steps, 1);
    });
  }

  testWidgets('slider keeps arrows for editing its value', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var steps = 0;
    var value = 0.5;
    await tester.pumpWidget(
      _app(
        _shortcuts(
          next: () => steps++,
          child: StatefulBuilder(
            builder: (context, setState) => Slider(
              focusNode: focus,
              value: value,
              onChanged: (next) => setState(() => value = next),
            ),
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(steps, 0);
    expect(value, greaterThan(0.5));
  });

  testWidgets(
    'only active page handles arrows; page changes do not duplicate',
    (tester) async {
      var first = 0;
      var second = 0;
      var selected = 0;
      late StateSetter rebuild;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Stack(
                children: [
                  _shortcuts(active: selected == 0, next: () => first++),
                  _shortcuts(active: selected == 1, next: () => second++),
                ],
              );
            },
          ),
        ),
      );
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect([first, second], [1, 0]);
      rebuild(() => selected = 1);
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect([first, second], [1, 1]);
      rebuild(() => selected = -1);
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect([first, second], [1, 1]);
    },
  );

  testWidgets('covered route, dialog and bottom sheet block; pop restores', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    var steps = 0;
    await tester.pumpWidget(
      _app(_shortcuts(next: () => steps++), navigatorKey: navigatorKey),
    );
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(steps, 1);
    final boardContext = tester.element(find.byType(BoardArrowKeyShortcuts));
    navigatorKey.currentState!.push<void>(
      MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('other route')),
      ),
    );
    await tester.pumpAndSettle();
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(steps, 1);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    showDialog<void>(
      context: boardContext,
      builder: (_) => const AlertDialog(title: Text('modal')),
    );
    await tester.pumpAndSettle();
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(steps, 1);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    showModalBottomSheet<void>(
      context: boardContext,
      builder: (_) => const SizedBox(height: 100),
    );
    await tester.pumpAndSettle();
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(steps, 1);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(steps, 2);
  });

  testWidgets(
    'nested current board route cannot act under covered outer route',
    (tester) async {
      final root = GlobalKey<NavigatorState>();
      var steps = 0;
      await tester.pumpWidget(
        _app(
          Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => _shortcuts(next: () => steps++),
            ),
          ),
          navigatorKey: root,
        ),
      );
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(steps, 1);
      root.currentState!.push<void>(
        PageRouteBuilder(
          opaque: false,
          pageBuilder: (_, animation, secondaryAnimation) =>
              const SizedBox.expand(),
        ),
      );
      await tester.pumpAndSettle();
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(steps, 1);
      root.currentState!.pop();
      await tester.pumpAndSettle();
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(steps, 2);
    },
  );

  testWidgets(
    'hidden ticker mode and background lifecycle suppress navigation',
    (tester) async {
      var steps = 0;
      var visible = false;
      late StateSetter rebuild;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return TickerMode(
                enabled: visible,
                child: _shortcuts(next: () => steps++),
              );
            },
          ),
        ),
      );
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(steps, 0);
      rebuild(() => visible = true);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(steps, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(steps, 1);
    },
  );

  testWidgets('disposal removes handler; remount uses fresh callbacks only', (
    tester,
  ) async {
    var old = 0;
    var fresh = 0;
    var show = true;
    late StateSetter rebuild;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return show
                ? _shortcuts(next: () => old++)
                : const SizedBox.expand();
          },
        ),
      ),
    );
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(old, 1);
    rebuild(() => show = false);
    await tester.pump();
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(old, 1);
    await tester.pumpWidget(_app(_shortcuts(next: () => fresh++)));
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect([old, fresh], [1, 1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('global-key reparenting reattaches exactly once', (tester) async {
    final key = GlobalKey();
    var steps = 0;
    var secondSlot = false;
    late StateSetter rebuild;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            final board = BoardArrowKeyShortcuts(
              key: key,
              isActivePage: true,
              onPrevious: null,
              onNext: () => steps++,
              child: const SizedBox.expand(),
            );
            return Row(
              children: [
                Expanded(child: secondSlot ? const SizedBox() : board),
                Expanded(child: secondSlot ? board : const SizedBox()),
              ],
            );
          },
        ),
      ),
    );
    await _press(tester, LogicalKeyboardKey.arrowRight);
    rebuild(() => secondSlot = true);
    await tester.pump();
    await _press(tester, LogicalKeyboardKey.arrowRight);
    expect(steps, 2);
    expect(tester.takeException(), isNull);
  });
}
