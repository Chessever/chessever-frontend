import 'package:flutter_test/flutter_test.dart';

import 'package:chessever2/screens/chessboard/game_review/game_report_progress.dart';

void main() {
  test('advances between sparse callbacks without reaching completion', () {
    var now = DateTime(2026, 1, 1);
    final simulator = GameReportProgressSimulator(now: () => now);

    simulator.start();
    final first = simulator.observe(0.2);
    now = now.add(const Duration(seconds: 30));
    final second = simulator.tick();

    expect(second, greaterThan(first));
    expect(simulator.observe(1), lessThan(1));
    expect(simulator.finish(), 1);
  });

  test('an unstarted simulator passes local progress straight through', () {
    // The engine passes call back per analysed position, which is already an
    // honest bar — a time curve there would overstate real work.
    final simulator = GameReportProgressSimulator(
      now: () => DateTime(2026, 1, 1),
    );

    expect(simulator.observe(0.25), 0.25);
    expect(simulator.observe(0.5), 0.5);
    expect(simulator.tick(), 0.5);
    // Completion still belongs to the finished report.
    expect(simulator.observe(1), lessThan(1));
  });

  test('reset disarms the curve for the pass that follows', () {
    var now = DateTime(2026, 1, 1);
    final simulator = GameReportProgressSimulator(now: () => now);

    simulator.start();
    now = now.add(const Duration(seconds: 45));
    expect(simulator.tick(), greaterThan(0.1));

    simulator.reset();
    now = now.add(const Duration(seconds: 45));
    // A failed server attempt hands over to the local passes; they start from
    // their own progress, not from where the abandoned curve had climbed to.
    expect(simulator.tick(), 0);
    expect(simulator.observe(0.05), 0.05);
  });

  test('never moves backwards when a remote callback regresses', () {
    final simulator = GameReportProgressSimulator(
      now: () => DateTime(2026, 1, 1),
    );

    simulator.start();
    final reported = simulator.observe(0.8);
    final regressed = simulator.observe(0.1);

    expect(regressed, greaterThanOrEqualTo(reported));
    expect(regressed, lessThan(1));
  });
}
