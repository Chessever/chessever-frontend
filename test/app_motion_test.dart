import 'package:chessever2/utils/app_motion.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the system reduced-motion flag never reaches the app', (
    tester,
  ) async {
    late bool disabled;
    late bool screenReader;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          disableAnimations: true,
          accessibleNavigation: true,
        ),
        child: AppMotionAlwaysOn(
          child: Builder(
            builder: (context) {
              disabled = MediaQuery.disableAnimationsOf(context);
              screenReader = MediaQuery.accessibleNavigationOf(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(disabled, isFalse);
    // A screen reader is still honoured.
    expect(screenReader, isTrue);
  });
}
