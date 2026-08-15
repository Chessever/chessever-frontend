import 'package:chessever2/utils/date_time_provider.dart';
import 'package:chessever2/widgets/atomic_countdown_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final _now = DateTime.utc(2026, 8, 14, 12, 0, 0);

/// Pumps a running clock that started [elapsed] ago with [totalSeconds] left at
/// that moment, with both time sources frozen at [_now].
Future<void> _pumpRunningClock(
  WidgetTester tester, {
  required int totalSeconds,
  required Duration elapsed,
  required bool showSubSecond,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dateTimeProvider.overrideWith((ref) => Stream.value(_now)),
        subSecondTimeProvider.overrideWith((ref) => Stream.value(_now)),
      ],
      child: MaterialApp(
        home: AtomicCountdownText(
          clockSeconds: totalSeconds,
          clockCentiseconds: 0,
          lastMoveTime: _now.subtract(elapsed),
          isActive: true,
          style: const TextStyle(color: Colors.white),
          showSubSecond: showSubSecond,
        ),
      ),
    ),
  );
  // One frame to build, one to receive the seeded stream values, then let the
  // tenths reveal spring settle.
  await tester.pump();
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders unknown live clock as placeholder, not zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: AtomicCountdownText(
            clockCentiseconds: 0,
            lastMoveTime: null,
            isActive: false,
            style: TextStyle(),
          ),
        ),
      ),
    );

    expect(find.text('--:--'), findsOneWidget);
    expect(find.text('00:00'), findsNothing);
  });

  testWidgets('keeps explicit zero clock displayable', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: AtomicCountdownText(
            clockSeconds: 0,
            clockCentiseconds: 0,
            lastMoveTime: null,
            isActive: false,
            style: TextStyle(),
          ),
        ),
      ),
    );

    expect(find.text('00:00'), findsOneWidget);
  });

  testWidgets('board clock reveals one tenth inside the last 30 seconds', (
    tester,
  ) async {
    await tester.pumpRunningBoardClock(
      totalSeconds: 20,
      elapsed: const Duration(milliseconds: 7400),
    );

    // 20.0s - 7.4s = 12.6s remaining. One digit, never milliseconds.
    expect(find.text('00:12'), findsOneWidget);
    expect(find.text('.6'), findsOneWidget);
    expect(find.text('.64'), findsNothing);
    expect(find.text('.647'), findsNothing);
  });

  testWidgets('board clock stays on whole seconds above the window', (
    tester,
  ) async {
    await tester.pumpRunningBoardClock(
      totalSeconds: 300,
      elapsed: const Duration(milliseconds: 10400),
    );

    expect(find.text('04:50'), findsOneWidget);
    expect(find.textContaining('.'), findsNothing);
  });

  testWidgets(
    'board clock above the window still rolls hours and minutes',
    (tester) async {
      // 1:05:00 on the clock, 10s elapsed → 1:04:50. Same h:mm:ss path the
      // shared clock uses; the tenth must not appear or rewrite the format.
      await tester.pumpRunningBoardClock(
        totalSeconds: 3900,
        elapsed: const Duration(seconds: 10),
      );

      expect(find.text('1:04:50'), findsOneWidget);
      expect(find.textContaining('.'), findsNothing);
    },
  );

  testWidgets('board tenth rolls into the next second the same way seconds do', (
    tester,
  ) async {
    await tester.pumpRunningBoardClock(
      totalSeconds: 10,
      elapsed: const Duration(milliseconds: 9000),
    );
    expect(find.text('00:01'), findsOneWidget);
    expect(find.text('.0'), findsOneWidget);

    await tester.pumpRunningBoardClock(
      totalSeconds: 10,
      elapsed: const Duration(milliseconds: 9100),
    );
    // 1.0s → 0.9s: the second decrements as the tenth wraps, from one
    // remaining-ms reading — the same lockstep as 1:00 → 0:59.
    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('.9'), findsOneWidget);
  });

  testWidgets('board clock floors to zero without a negative tenth', (
    tester,
  ) async {
    await tester.pumpRunningBoardClock(
      totalSeconds: 5,
      elapsed: const Duration(milliseconds: 9000),
    );

    expect(find.text('00:00'), findsOneWidget);
    expect(find.text('.0'), findsOneWidget);
  });

  testWidgets('game cards never show tenths, even under 30 seconds', (
    tester,
  ) async {
    await _pumpRunningClock(
      tester,
      totalSeconds: 20,
      elapsed: const Duration(milliseconds: 7400),
      showSubSecond: false,
    );

    // The shared card path truncates elapsed to whole seconds: 20 - 7 = 13.
    expect(find.text('00:13'), findsOneWidget);
    expect(find.textContaining('.'), findsNothing);
  });
}

extension on WidgetTester {
  Future<void> pumpRunningBoardClock({
    required int totalSeconds,
    required Duration elapsed,
  }) => _pumpRunningClock(
    this,
    totalSeconds: totalSeconds,
    elapsed: elapsed,
    showSubSecond: true,
  );
}
