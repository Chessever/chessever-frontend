import 'package:chessever2/widgets/window_metrics_dismissal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<int Function()> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    var dismissals = 0;
    await tester.pumpWidget(
      WindowMetricsDismissal(
        onChanged: () => dismissals++,
        child: const SizedBox.expand(),
      ),
    );
    return () => dismissals;
  }

  testWidgets('ignores a metrics report that changed nothing', (tester) async {
    final dismissals = await pump(tester);

    // iOS re-sends an identical viewport on every UIKit layout pass.
    tester.binding.handleMetricsChanged();
    tester.binding.handleMetricsChanged();
    await tester.pump();

    expect(dismissals(), 0);
  });

  testWidgets('ignores inset-only churn', (tester) async {
    final dismissals = await pump(tester);

    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    await tester.pump();
    tester.view.padding = const FakeViewPadding(top: 141, bottom: 102);
    await tester.pump();

    expect(dismissals(), 0);
  });

  testWidgets('dismisses once when the window is resized', (tester) async {
    final dismissals = await pump(tester);

    tester.view.physicalSize = const Size(2556, 1179);
    await tester.pump();
    expect(dismissals(), 1);

    // The new size is the baseline; repeating it is not another resize.
    tester.binding.handleMetricsChanged();
    await tester.pump();
    expect(dismissals(), 1);
  });

  testWidgets('dismisses when the pixel ratio changes', (tester) async {
    final dismissals = await pump(tester);

    tester.view.devicePixelRatio = 2;
    await tester.pump();

    expect(dismissals(), 1);
  });
}
