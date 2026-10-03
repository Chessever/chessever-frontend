import 'dart:async';

import 'package:chessever2/providers/gamebase_overlay_settings_provider.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/gamebase/providers/explorer_game_focus_provider.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _StoredExplorerPreference extends GamebaseOverlayEnabledNotifier {
  _StoredExplorerPreference(this.value);
  final Future<bool> value;
  @override
  Future<bool> build() => value;
  @override
  Future<void> setEnabled(bool enabled) async {
    fail(
      'Opening/swiping a board must not rewrite standalone Explorer preference',
    );
  }
}

void main() {
  for (final delayed in [false, true]) {
    testWidgets(
      'new game starts Notation despite ${delayed ? 'late' : 'loaded'} Explorer preference; explicit switch survives',
      (tester) async {
        final preference = Completer<bool>();
        if (!delayed) preference.complete(true);
        final container = ProviderContainer(
          overrides: [
            gamebaseOverlayEnabledProvider.overrideWith(
              () => _StoredExplorerPreference(preference.future),
            ),
            gamebaseExplorerProvider.overrideWith(
              (ref) => GamebaseExplorerNotifier(ref),
            ),
          ],
        );
        addTearDown(container.dispose);
        final preferenceWatch = container.listen(
          gamebaseOverlayEnabledProvider,
          (_, __) {},
        );
        addTearDown(preferenceWatch.close);
        final focusWatch = container.listen(
          explorerFocusedGameProvider,
          (_, __) {},
        );
        addTearDown(focusWatch.close);
        final focus = container.read(explorerFocusedGameProvider.notifier);
        focus.focus(
          gameId: 'old-card',
          anchorFen: 'anchor',
          sans: ['e4'],
          fens: ['anchor', 'one'],
        );
        container.read(explorerInlineGamesPinnedProvider.notifier).state = true;

        Future<void> open(String gameId) async {
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                home: boardAnalysisSwipePanelsForTesting(gameId: gameId),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await open('first');
        expect(find.text('Notation fixture').hitTestable(), findsOneWidget);
        expect(container.read(boardExplorerPanelVisibleProvider), isFalse);
        expect(container.read(explorerFocusedGameProvider), isNull);
        expect(container.read(explorerInlineGamesPinnedProvider), isFalse);
        if (delayed) preference.complete(true);
        await tester.pumpAndSettle();
        expect(find.text('Notation fixture').hitTestable(), findsOneWidget);
        container
            .read(boardExplorerToggleRequestProvider('first').notifier)
            .state++;
        await tester.pumpAndSettle();
        expect(find.text('Explorer fixture').hitTestable(), findsOneWidget);
        expect(container.read(boardExplorerPanelVisibleProvider), isTrue);
        focus.focus(
          gameId: 'intentional-card',
          anchorFen: 'anchor',
          sans: ['e4'],
          fens: ['anchor', 'one'],
        );
        await tester.drag(find.byType(PageView), const Offset(700, 0));
        await tester.pumpAndSettle();
        expect(find.text('Notation fixture').hitTestable(), findsOneWidget);
        expect(container.read(explorerFocusedGameProvider), isNull);
        await tester.drag(find.byType(PageView), const Offset(-700, 0));
        await tester.pumpAndSettle();
        expect(find.text('Explorer fixture').hitTestable(), findsOneWidget);
        await open('second');
        expect(find.text('Notation fixture').hitTestable(), findsOneWidget);
        expect(container.read(boardExplorerPanelVisibleProvider), isFalse);
        expect(
          container.read(gamebaseOverlayEnabledProvider).requireValue,
          isTrue,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('preloaded inactive game cannot reset active Explorer focus', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        gamebaseExplorerProvider.overrideWith(
          (ref) => GamebaseExplorerNotifier(ref),
        ),
      ],
    );
    addTearDown(container.dispose);
    final focusWatch = container.listen(
      explorerFocusedGameProvider,
      (_, __) {},
    );
    addTearDown(focusWatch.close);
    container.read(boardExplorerPanelVisibleProvider.notifier).state = true;
    container
        .read(explorerFocusedGameProvider.notifier)
        .focus(
          gameId: 'visible-card',
          anchorFen: 'anchor',
          sans: ['e4'],
          fens: ['anchor', 'one'],
        );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: boardAnalysisSwipePanelsForTesting(
            gameId: 'adjacent',
            isActivePage: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(container.read(boardExplorerPanelVisibleProvider), isTrue);
    expect(container.read(explorerFocusedGameProvider)?.gameId, 'visible-card');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
