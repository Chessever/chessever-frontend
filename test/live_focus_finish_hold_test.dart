import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/game_display_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_focus_finish_hold_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  group('LiveFocusFinishHold', () {
    test('first ingest snapshots finished ids without holding them', () {
      final hold = LiveFocusFinishHold();
      addTearDown(hold.reset);
      expect(hold.ingestFinishedIds(const {'old-a', 'old-b'}), isEmpty);
      expect(hold.hasSnapshot, isTrue);
      expect(hold.state.heldIds, isEmpty);
    });

    test('later ingest holds only newly finished ids', () async {
      final hold = LiveFocusFinishHold();
      addTearDown(hold.reset);
      hold.ingestFinishedIds(const {'old-a'});
      expect(
        hold.ingestFinishedIds(const {'old-a', 'just-ended'}),
        <String>{'just-ended'},
      );
      await Future<void>.value();
      expect(hold.state.phaseOf('just-ended'), LiveFocusFinishPhase.holding);
    });

    testWidgets('hold is idempotent and does not restart the window', (
      tester,
    ) async {
      final hold = LiveFocusFinishHold();
      addTearDown(hold.reset);
      hold.hold('g1');
      await tester.pump(const Duration(seconds: 2));
      hold.hold('g1');
      expect(hold.state.phaseOf('g1'), LiveFocusFinishPhase.holding);
      await tester.pump(const Duration(seconds: 1));
      expect(hold.state.phaseOf('g1'), LiveFocusFinishPhase.exiting);
      await tester.pump(kLiveFocusFinishExitDuration);
      expect(hold.state.heldIds, isEmpty);
    });

    testWidgets(
      'stays held through overlay window then exits before release',
      (tester) async {
        final hold = LiveFocusFinishHold();
        addTearDown(hold.reset);
        hold.hold('g1');
        await tester.pump(
          kLiveFocusFinishHoldDuration - const Duration(milliseconds: 1),
        );
        expect(hold.state.heldIds, <String>{'g1'});
        expect(hold.state.phaseOf('g1'), LiveFocusFinishPhase.holding);

        await tester.pump(const Duration(milliseconds: 1));
        expect(hold.state.phaseOf('g1'), LiveFocusFinishPhase.exiting);
        expect(hold.state.heldIds, <String>{'g1'});

        await tester.pump(
          kLiveFocusFinishExitDuration - const Duration(milliseconds: 1),
        );
        expect(hold.state.heldIds, <String>{'g1'});

        await tester.pump(const Duration(milliseconds: 1));
        expect(hold.state.heldIds, isEmpty);
      },
    );

    test('reset clears holds when Live First is turned off', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(gameDisplayModeProvider('tour-1').notifier).state =
          GameDisplayMode.hideFinishedGames;
      final notifier = container.read(
        liveFocusFinishHoldProvider('tour-1').notifier,
      );
      notifier.hold('g1');
      expect(
        container.read(liveFocusFinishHoldProvider('tour-1')).heldIds,
        <String>{'g1'},
      );

      container.read(gameDisplayModeProvider('tour-1').notifier).state =
          GameDisplayMode.all;
      expect(
        container.read(liveFocusFinishHoldProvider('tour-1')).heldIds,
        isEmpty,
      );
      notifier.reset();
    });
  });
}
