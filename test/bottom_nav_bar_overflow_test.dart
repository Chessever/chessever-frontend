import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  testWidgets(
    'bottom nav bar never overflows the bottom on a short screen at large '
    'text scale with a gesture-nav inset',
    (tester) async {
      // The regression: the nav-item Column (icon + label + vertical padding,
      // whose label height rides MediaQuery.textScaler) was placed in a fixed
      // height slot — clamp(70.h + inset, 70, 120) minus the inset. On a short
      // screen and/or large accessibility text scale and/or a large safe-area
      // inset, that slot dropped a few pixels below the Column's intrinsic
      // height and the bottom overflowed. This combination forces it.
      final mediaQuery = const MediaQueryData(
        size: Size(393, 600),
        devicePixelRatio: 3,
        viewPadding: EdgeInsets.only(bottom: 34),
        padding: EdgeInsets.only(bottom: 34),
      ).copyWith(textScaler: const TextScaler.linear(3));

      // Capture overflow specifically; svg assets aren't bundled in the unit
      // test, so SvgWidget's errorBuilder fires — we must not let that noise
      // mask (or fake) the layout assertion.
      final errors = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = errors.add;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: MediaQuery(
              data: mediaQuery,
              child: Builder(
                builder: (context) {
                  ResponsiveHelper.init(context);
                  return const Scaffold(
                    bottomNavigationBar: BottomNavBar(),
                    body: SizedBox.shrink(),
                  );
                },
              ),
            ),
          ),
        ),
      );

      FlutterError.onError = previousOnError;

      final overflowErrors = errors
          .map((e) => e.exceptionAsString())
          .where((e) => e.contains('overflowed'))
          .toList();

      expect(
        overflowErrors,
        isEmpty,
        reason: overflowErrors.join('\n'),
      );
    },
  );
}
