import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/app_switch_colors.dart';
import 'package:chessever2/widgets/auth_button.dart';
import 'package:chessever2/widgets/back_drop_filter_widget.dart';
import 'package:chessever2/widgets/blur_background.dart';
import 'package:chessever2/widgets/generic_loading_widget.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const AppColors _light = AppColors.light;

void _expectContrast(
  Color fg,
  Color bg, {
  required double min,
  required String what,
}) {
  final ratio = wcagContrast(fg, bg);
  expect(
    ratio,
    greaterThanOrEqualTo(min),
    reason: '$what reads ${ratio.toStringAsFixed(2)}:1, needs $min:1',
  );
}

/// Pumps [child] under [theme] on the 393pt design phone, with the
/// responsive units initialised.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required ThemeData theme,
}) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      themeAnimationDuration: Duration.zero,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(body: Center(child: child));
        },
      ),
    ),
  );
  await tester.pump();
}

Future<T> _under<T>(
  WidgetTester tester,
  ThemeData theme,
  T Function(BuildContext context) read,
) async {
  late T value;
  await _pump(
    tester,
    Builder(
      builder: (context) {
        value = read(context);
        return const SizedBox();
      },
    ),
    theme: theme,
  );
  return value;
}

Color _resolve(WidgetStateProperty<Color?> property, {required bool on}) =>
    property.resolve({if (on) WidgetState.selected})!;

void main() {
  group('AuthButton', () {
    Future<(Color plate, Color label, ColorFilter? logo)> read(
      WidgetTester tester,
      ThemeData theme,
      String logo,
    ) async {
      await _pump(
        tester,
        AuthButton(svgIconPath: logo, signInTitle: 'Sign in', onPressed: () {}),
        theme: theme,
      );
      final plate =
          (tester
                      .widget<Container>(
                        find
                            .descendant(
                              of: find.byType(AuthButton),
                              matching: find.byType(Container),
                            )
                            .first,
                      )
                      .decoration!
                  as BoxDecoration)
              .color!;
      final label = tester.widget<Text>(find.text('Sign in')).style!.color!;
      final filter = tester
          .widget<SvgWidget>(find.byType(SvgWidget))
          .colorFilter;
      return (plate, label, filter);
    }

    testWidgets('light: mint label and mark on the ink plate', (tester) async {
      final (plate, label, logo) = await read(
        tester,
        AppTheme.lightTheme,
        SvgAsset.appleIcon,
      );
      expect(plate, _light.textPrimary);
      _expectContrast(label, plate, min: 4.5, what: 'auth label');
      expect(
        logo,
        ColorFilter.mode(_light.textInverse, BlendMode.srcIn),
        reason: 'the black Apple mark would vanish on the ink plate',
      );
    });

    testWidgets('light keeps the Google mark in its own colours', (
      tester,
    ) async {
      final (_, _, logo) = await read(
        tester,
        AppTheme.lightTheme,
        SvgAsset.googleIcon,
      );
      expect(logo, isNull);
    });

    testWidgets('dark is unchanged: black label on the white plate', (
      tester,
    ) async {
      final (plate, label, logo) = await read(
        tester,
        AppTheme.darkTheme,
        SvgAsset.appleIcon,
      );
      expect(plate, kWhiteColor);
      expect(label, kBlackColor);
      expect(logo, isNull);
    });
  });

  group('GenericLoadingWidget', () {
    Future<Color> spinner(WidgetTester tester, ThemeData theme) async {
      await _pump(tester, const GenericLoadingWidget(), theme: theme);
      final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      return indicator.valueColor!.value!;
    }

    testWidgets('light spins in accent-text teal, 3:1 on paper', (
      tester,
    ) async {
      final color = await spinner(tester, AppTheme.lightTheme);
      expect(color, _light.accentText);
      _expectContrast(color, _light.background, min: 3, what: 'spinner');
    });

    testWidgets('dark keeps brand cyan', (tester) async {
      expect(await spinner(tester, AppTheme.darkTheme), kPrimaryColor);
    });
  });

  group('house switch colours', () {
    testWidgets('light: on and off both read, on reads against off', (
      tester,
    ) async {
      final (thumb, track) = await _under(
        tester,
        AppTheme.lightTheme,
        (context) =>
            (appSwitchThumbColor(context), appSwitchTrackColor(context)),
      );
      final onThumb = _resolve(thumb, on: true);
      final onTrack = _resolve(track, on: true);
      final offThumb = _resolve(thumb, on: false);
      final offTrack = _resolve(track, on: false);
      _expectContrast(onThumb, onTrack, min: 3, what: 'on thumb');
      _expectContrast(offThumb, offTrack, min: 3, what: 'off thumb');
      _expectContrast(onTrack, _light.surface, min: 3, what: 'on track');
      _expectContrast(onTrack, offTrack, min: 3, what: 'on vs off track');
    });

    testWidgets('dark returns the historic values', (tester) async {
      final (thumb, track, customThumb, divider) = await _under(
        tester,
        AppTheme.darkTheme,
        (context) => (
          appSwitchThumbColor(context),
          appSwitchTrackColor(context),
          appSwitchThumbColor(context, darkOffThumb: const Color(0x99FFFFFF)),
          context.colors.divider,
        ),
      );
      expect(_resolve(thumb, on: true), kPrimaryColor);
      expect(_resolve(thumb, on: false), kPrimaryColor);
      expect(_resolve(customThumb, on: false), const Color(0x99FFFFFF));
      expect(_resolve(track, on: true), kPrimaryColor.withValues(alpha: 0.35));
      expect(_resolve(track, on: false), divider.withValues(alpha: 0.5));
    });
  });

  group('dims and atmosphere', () {
    Gradient? dim(WidgetTester tester) =>
        (tester
                    .widget<Container>(
                      find.descendant(
                        of: find.byType(BackDropFilterWidget),
                        matching: find.byType(Container),
                      ),
                    )
                    .decoration!
                as BoxDecoration)
            .gradient;

    testWidgets('dialog dim is palette ink on paper, black on the stage', (
      tester,
    ) async {
      await _pump(
        tester,
        const SizedBox.square(dimension: 100, child: BackDropFilterWidget()),
        theme: AppTheme.lightTheme,
      );
      expect(dim(tester), radialOverlayGradientLight);

      await _pump(
        tester,
        const SizedBox.square(dimension: 100, child: BackDropFilterWidget()),
        theme: AppTheme.darkTheme,
      );
      expect(dim(tester), radialOverlayGradient);
    });

    testWidgets('the cyan blur blob is dark-only', (tester) async {
      Finder blob() => find.descendant(
        of: find.byType(BlurBackground),
        matching: find.byType(CustomPaint),
      );

      await _pump(
        tester,
        const SizedBox.square(dimension: 100, child: BlurBackground()),
        theme: AppTheme.lightTheme,
      );
      expect(blob(), findsNothing);

      await _pump(
        tester,
        const SizedBox.square(dimension: 100, child: BlurBackground()),
        theme: AppTheme.darkTheme,
      );
      expect(blob(), findsOneWidget);
    });
  });
}
