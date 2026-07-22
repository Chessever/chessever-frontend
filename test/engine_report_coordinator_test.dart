import 'dart:io';

import 'package:chessever2/screens/chessboard/provider/engine_report_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EngineReportCoordinator coordinator;

  setUp(() {
    coordinator = EngineReportCoordinator.instance..resetForTest();
  });

  test('board keeps precedence: report is only capped while pending', () {
    expect(coordinator.shouldCapBoardDepth, isFalse);
    coordinator.setReportPending(true);
    expect(coordinator.shouldCapBoardDepth, isTrue);
    coordinator.setReportPending(false);
    expect(coordinator.shouldCapBoardDepth, isFalse);
  });

  test('handoff resolves immediately when the board is idle', () async {
    // No board search in flight → the report may run at once.
    await coordinator.waitForBoardHandoff().timeout(
      const Duration(milliseconds: 200),
    );
  });

  test('report waits until the board reaches the handoff depth', () async {
    coordinator.boardSearchStarted();
    var released = false;
    final waiter = coordinator.waitForBoardHandoff().then((_) {
      released = true;
    });

    coordinator.boardDepth(EngineReportCoordinator.handoffDepth - 1);
    await Future<void>.delayed(Duration.zero);
    expect(released, isFalse, reason: 'below the threshold must keep waiting');

    coordinator.boardDepth(EngineReportCoordinator.handoffDepth);
    await waiter.timeout(const Duration(milliseconds: 200));
    expect(released, isTrue);
  });

  test('going idle releases a waiting report even before the threshold',
      () async {
    coordinator.boardSearchStarted();
    final waiter = coordinator.waitForBoardHandoff();
    coordinator.boardSearchIdle();
    await waiter.timeout(const Duration(milliseconds: 200));
  });

  test('clearing pending fires registered board resume callbacks', () {
    var resumed = 0;
    coordinator.registerResume('owner-a', () => resumed++);
    coordinator.setReportPending(true);
    expect(resumed, 0);
    coordinator.setReportPending(false);
    expect(resumed, 1);

    coordinator.unregisterResume('owner-a');
    coordinator.setReportPending(true);
    coordinator.setReportPending(false);
    expect(resumed, 1, reason: 'unregistered callbacks must not fire');
  });

  test('a stuck board-busy flag cannot wedge the report forever', () async {
    coordinator.boardSearchStarted();
    // Never signals depth or idle — the safety timeout must still let it run.
    await coordinator.waitForBoardHandoff().timeout(
      const Duration(seconds: 4),
    );
  });

  group('boardSearchMaxDepth (depth-18 cap while report pending)', () {
    test('does not cap when no report is pending', () {
      expect(
        EngineReportCoordinator.boardSearchMaxDepth(
          configuredMaxDepth: 40,
          reportPending: false,
        ),
        40,
      );
    });

    test('caps at handoff depth while report is pending', () {
      expect(
        EngineReportCoordinator.boardSearchMaxDepth(
          configuredMaxDepth: 40,
          reportPending: true,
        ),
        EngineReportCoordinator.handoffDepth,
      );
      expect(
        EngineReportCoordinator.boardSearchMaxDepth(
          configuredMaxDepth: EngineReportCoordinator.handoffDepth,
          reportPending: true,
        ),
        EngineReportCoordinator.handoffDepth,
      );
      expect(
        EngineReportCoordinator.boardSearchMaxDepth(
          configuredMaxDepth: 12,
          reportPending: true,
        ),
        12,
        reason: 'already-shallower settings stay as-is',
      );
    });
  });

  group('shouldYieldBoardSearchForReport (mid-flight handoff)', () {
    test('yields only at/after handoff when report pending and uncapped', () {
      expect(
        EngineReportCoordinator.shouldYieldBoardSearchForReport(
          depth: 17,
          reportPending: true,
          searchMaxDepth: 40,
          alreadyYielding: false,
        ),
        isFalse,
      );
      expect(
        EngineReportCoordinator.shouldYieldBoardSearchForReport(
          depth: 18,
          reportPending: true,
          searchMaxDepth: 40,
          alreadyYielding: false,
        ),
        isTrue,
      );
    });

    test('does not yield when search was already capped at handoff', () {
      expect(
        EngineReportCoordinator.shouldYieldBoardSearchForReport(
          depth: 18,
          reportPending: true,
          searchMaxDepth: EngineReportCoordinator.handoffDepth,
          alreadyYielding: false,
        ),
        isFalse,
      );
    });

    test('does not yield when no report is pending', () {
      expect(
        EngineReportCoordinator.shouldYieldBoardSearchForReport(
          depth: 18,
          reportPending: false,
          searchMaxDepth: 40,
          alreadyYielding: false,
        ),
        isFalse,
      );
    });

    test('does not re-yield while already yielding', () {
      expect(
        EngineReportCoordinator.shouldYieldBoardSearchForReport(
          depth: 20,
          reportPending: true,
          searchMaxDepth: 40,
          alreadyYielding: true,
        ),
        isFalse,
      );
    });
  });

  test(
    'shipped board provider wires coordinator start/depth/idle/cap/resume',
    () {
      // Structural check of the real entry point used by the board screen —
      // proves the handoff contract is not only unit-tested in isolation.
      final providerSource = File(
        'lib/screens/chessboard/provider/chess_board_screen_provider_new.dart',
      ).readAsStringSync();
      final reportSource = File(
        'lib/screens/chessboard/game_review/game_analysis_report.dart',
      ).readAsStringSync();

      expect(providerSource.contains('EngineReportCoordinator'), isTrue);
      expect(providerSource.contains('boardSearchStarted()'), isTrue);
      expect(providerSource.contains('boardDepth('), isTrue);
      expect(providerSource.contains('boardSearchIdle()'), isTrue);
      expect(providerSource.contains('boardSearchMaxDepth('), isTrue);
      expect(
        providerSource.contains('shouldYieldBoardSearchForReport('),
        isTrue,
      );
      expect(providerSource.contains('registerResume('), isTrue);
      // Resume must forceRestart so depth-18 complete PVs do not short-circuit.
      expect(
        providerSource.contains(
          '_updateEvaluation(force: true, forceRestart: true)',
        ),
        isTrue,
      );
      // Review sheet visibility must not cancel / early-return board eval.
      expect(
        providerSource.contains('if (_gameReviewVisible) return'),
        isFalse,
      );
      expect(
        providerSource.contains('if (_isLongPressing || _gameReviewVisible)'),
        isFalse,
      );

      expect(reportSource.contains('setReportPending(true'), isTrue);
      expect(reportSource.contains('waitForBoardHandoff()'), isTrue);
      expect(reportSource.contains('isCurrentPosition: false'), isTrue);
    },
  );
}
