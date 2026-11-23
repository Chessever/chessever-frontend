// The rewarded-interstitial intro ("Try another ad?"): the disclosure the
// ad format requires before the alternative ad loads.
//
// "answers" pins what the caller gets back (rewarded_access_provider.dart
// loads the alternative ad only on true). Those tests use only the entry
// point and the labels, so they pass on the old AlertDialog as on the new
// card: run `--plain-name answers` against HEAD's
// rewarded_interstitial_intro.dart to compare.
//
// "card" pins the Unlock Premium chooser's language: its glass, its Watch
// ad plate with the play mark, 44 pt targets and the semantics.
import 'dart:async';

import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/widgets/glass_dialog_route.dart';
import 'package:chessever2/widgets/paywall/rewarded_premium/premium_marks.dart';
import 'package:chessever2/widgets/paywall/rewarded_premium/rewarded_interstitial_intro.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _title = 'Try another ad?';

void main() {
  late List<MethodCall> platform;
  late List<bool> answers;

  /// A page with an Open button that asks the intro and records the answer.
  /// With [underDialog] the intro opens over another dialog, as it opens
  /// over the Unlock Premium chooser.
  Future<void> host(
    WidgetTester tester, {
    ThemeData? theme,
    double textScale = 1,
    bool underDialog = false,
  }) async {
    platform = [];
    answers = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platform.add(call);
        return null;
      },
    );
    Future<void> ask(BuildContext context) async {
      answers.add(await showRewardedInterstitialIntro(context));
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.darkTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                if (!underDialog) {
                  unawaited(ask(context));
                  return;
                }
                unawaited(
                  showDialog<void>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      content: const Text('Chooser'),
                      actions: [
                        TextButton(
                          onPressed: () => unawaited(ask(dialogContext)),
                          child: const Text('Ask'),
                        ),
                      ],
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    if (underDialog) {
      await tester.tap(find.text('Ask'));
      await tester.pumpAndSettle();
    }
    expect(find.text(_title), findsOneWidget);
  }

  group('answers', () {
    testWidgets('Watch ad answers true, once, and closes the intro', (
      tester,
    ) async {
      await host(tester);
      await tester.tap(find.text('Watch ad'));
      await tester.pumpAndSettle();
      expect(answers, [true]);
      expect(find.text(_title), findsNothing);
    });

    testWidgets('Skip answers false and closes the intro', (tester) async {
      await host(tester);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(answers, [false]);
      expect(find.text(_title), findsNothing);
    });

    testWidgets('an outside tap answers false', (tester) async {
      await host(tester);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(answers, [false]);
      expect(find.text(_title), findsNothing);
    });

    testWidgets('system back answers false', (tester) async {
      await host(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(answers, [false]);
      expect(find.text(_title), findsNothing);
    });

    // It opens over the chooser: either answer closes the intro only.
    for (final (label, answer) in [('Watch ad', true), ('Skip', false)]) {
      testWidgets('$label closes only the intro, not the dialog under it', (
        tester,
      ) async {
        await host(tester, underDialog: true);
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(answers, [answer]);
        expect(find.text(_title), findsNothing);
        expect(find.text('Chooser'), findsOneWidget);
      });
    }

    testWidgets('an opener that has left answers false and shows nothing', (
      tester,
    ) async {
      late BuildContext gone;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              gone = context;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(gone.mounted, isFalse);
      expect(await showRewardedInterstitialIntro(gone), isFalse);
      await tester.pumpAndSettle();
      expect(find.text(_title), findsNothing);
    });

    testWidgets('the intro names the reward before the ad loads', (
      tester,
    ) async {
      await host(tester);
      expect(find.textContaining('10 minutes of Premium'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
    });
  });

  /// The plate a choice's label sits on: its ink well's box.
  Rect plateOf(WidgetTester tester, String label) => tester.getRect(
    find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first,
  );

  group('card', () {
    for (final light in [false, true]) {
      testWidgets('the chooser\'s glass and Watch ad plate '
          '(${light ? 'light' : 'dark'})', (tester) async {
        await host(
          tester,
          theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
        );
        expect(find.byType(GlassDialog), findsOneWidget);
        // Watch ad wears the chooser's play mark, as tall as its label's
        // line, mark and label centred on the plate between them.
        final mark = find.descendant(
          of: find.ancestor(
            of: find.text('Watch ad'),
            matching: find.byType(Row),
          ),
          matching: find.byType(ChoiceGlyphIcon),
        );
        expect(tester.widget<ChoiceGlyphIcon>(mark).glyph, ChoiceGlyph.play);
        final plate = plateOf(tester, 'Watch ad');
        final glyph = tester.getRect(mark);
        final text = tester.getRect(find.text('Watch ad'));
        expect(glyph.height, 16);
        expect(glyph.center.dy, closeTo(plate.center.dy, 0.5));
        expect(text.center.dy, closeTo(plate.center.dy, 0.5));
        expect((glyph.left + text.right) / 2, closeTo(plate.center.dx, 0.75));
        // Title and copy on the card's centre line.
        final card = tester.getRect(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.byType(SingleChildScrollView),
          ),
        );
        expect(
          tester.getCenter(find.text(_title)).dx,
          closeTo(card.center.dx, 0.5),
        );
        expect(plate.center.dx, closeTo(card.center.dx, 0.5));
        await tester.tap(find.text('Skip'));
        await tester.pumpAndSettle();
      });
    }

    testWidgets('Watch ad is a 56 pt plate, Skip a 44 pt button, and the '
        'title names the popup', (tester) async {
      final semantics = tester.ensureSemantics();
      await host(tester);
      expect(
        tester.getSemantics(find.text('Watch ad')),
        matchesSemantics(
          label: 'Watch ad',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          isFocusable: true,
          hasFocusAction: true,
        ),
      );
      expect(plateOf(tester, 'Watch ad').height, greaterThanOrEqualTo(56));
      final skip = find.widgetWithText(TextButton, 'Skip');
      expect(tester.getSize(skip).height, greaterThanOrEqualTo(44));
      expect(
        tester.getSemantics(find.text('Skip')),
        matchesSemantics(
          label: 'Skip',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          isFocusable: true,
          hasFocusAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.text(_title)),
        matchesSemantics(label: _title, isHeader: true, namesRoute: true),
      );
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      semantics.dispose();
    });

    testWidgets('a tap on Watch ad gives the choices\' light haptic', (
      tester,
    ) async {
      await host(tester);
      await tester.tap(find.text('Watch ad'));
      await tester.pumpAndSettle();
      expect(
        platform.where((call) => call.method == 'HapticFeedback.vibrate'),
        hasLength(1),
      );
    });

    testWidgets('fits a narrow phone with large text', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await host(tester, textScale: 2);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Skip'));
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(answers, [false]);
    });
  });
}
