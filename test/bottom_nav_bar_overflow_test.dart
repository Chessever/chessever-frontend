import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

void main() {
  testWidgets(
    'canonical glass tab bar never overflows on a short screen at large text '
    'scale with a gesture-nav inset',
    (tester) async {
      // Regression guard: the old solid bar overflowed its fixed-height slot at
      // large text scale + large safe-area insets. The package GlassTabBar must
      // stay overflow-free under the same stress.
      final mediaQuery = const MediaQueryData(
        size: Size(393, 600),
        devicePixelRatio: 3,
        viewPadding: EdgeInsets.only(bottom: 34),
        padding: EdgeInsets.only(bottom: 34),
      ).copyWith(textScaler: const TextScaler.linear(3));

      final errors = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = errors.add;

      await tester.pumpWidget(
        ProviderScope(
          child: LiquidGlassWidgets.wrap(
            child: MaterialApp(
              theme: AppTheme.darkTheme,
              home: MediaQuery(
                data: mediaQuery,
                child: Builder(
                  builder: (context) {
                    ResponsiveHelper.init(context);
                    return const Scaffold(
                      extendBody: true,
                      backgroundColor: Colors.black,
                      body: Stack(
                        children: [
                          Positioned.fill(child: SizedBox.shrink()),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: SafeArea(
                              top: false,
                              child: BottomNavBar(),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );

      // Allow glass indicator / layout animations to settle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      FlutterError.onError = previousOnError;

      final overflowErrors =
          errors
              .map((e) => e.exceptionAsString())
              .where((e) => e.contains('overflowed'))
              .toList();

      expect(overflowErrors, isEmpty, reason: overflowErrors.join('\n'));

      // One cohesive canonical GlassTabBar pill.
      expect(find.byType(GlassTabBar), findsOneWidget);
    },
  );
}
