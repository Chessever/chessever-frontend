import 'package:chessever2/utils/adaptive_window.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('primary controls retain tap area and grow around large labels', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = const Size(466, 300) * 3;
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => AdaptiveWindowScope(child: child!),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 220,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppButton(
                        text: 'Continue with this account',
                        onPressed: () => taps++,
                      ),
                      AppIconButton(
                        icon: Icons.close,
                        size: 24,
                        onPressed: () => taps++,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(AppButton)).height,
      greaterThanOrEqualTo(44),
    );
    expect(
      tester.getSize(find.byType(AppIconButton)).shortestSide,
      greaterThanOrEqualTo(44),
    );
    await tester.ensureVisible(find.text('Continue with this account'));
    await tester.tap(find.text('Continue with this account'));
    await tester.ensureVisible(find.byIcon(Icons.close));
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(taps, 2);
    expect(tester.takeException(), isNull);
  });
}
