import 'dart:ui' show AppLifecycleState;

import 'package:chessever2/utils/foreground_task_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

/// The startup intake of a shared .pgn and AppsFlyer's OneLink callbacks ride
/// one scheduled task. A launch that was not in the foreground when it came
/// due used to drop it for the whole process; it now waits for the resume.
void main() {
  testWidgets('a refresh due while the app is not resumed is dropped', (
    tester,
  ) async {
    var runs = 0;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    ForegroundTaskScheduler.schedule(
      key: 'refresh',
      delay: const Duration(milliseconds: 250),
      task: () => runs++,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 1));
    expect(runs, 0);
  });

  testWidgets('a runWhenResumed task waits for the resume and runs once', (
    tester,
  ) async {
    var runs = 0;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    ForegroundTaskScheduler.schedule(
      key: 'startup_deep_link_services',
      delay: const Duration(milliseconds: 250),
      runWhenResumed: true,
      task: () => runs++,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(runs, 0, reason: 'not while the app is inactive');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(runs, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 1));
    expect(runs, 1, reason: 'once per schedule');
  });

  testWidgets('a runWhenResumed task in the foreground runs at once', (
    tester,
  ) async {
    var runs = 0;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    ForegroundTaskScheduler.schedule(
      key: 'startup',
      delay: const Duration(milliseconds: 250),
      runWhenResumed: true,
      task: () => runs++,
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(runs, 1);
  });
}
