import 'package:chessever2/screens/chessboard/widgets/like_nudge.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  testWidgets('asks the question and teaches the gesture', (tester) async {
    await _pumpNudge(tester);

    expect(find.text(kLikeNudgeQuestion), findsOneWidget);
    expect(find.text(kLikeNudgeHint), findsOneWidget);
    expect(find.textContaining('Tap the heart'), findsNothing);
    expect(tester.takeException(), isNull);

    await _drainBeat(tester);
  });

  // The reminder must never depend on a spring having run: a nudge stranded at
  // its entrance frame would be an invisible, unanswerable question.
  testWidgets('is fully visible on its first frame', (tester) async {
    await _pumpNudge(tester, settle: false);
    await tester.pump();

    final question = find.text(kLikeNudgeQuestion);
    expect(question, findsOneWidget);
    expect(tester.getSize(question).isEmpty, isFalse);
    // Nothing in the entrance touches opacity, so no Opacity can be hiding it.
    expect(
      find.ancestor(of: question, matching: find.byType(Opacity)),
      findsNothing,
    );

    await _drainBeat(tester);
  });

  testWidgets('the heart answers yes and reports its own centre', (
    tester,
  ) async {
    Offset? likedFrom;
    await _pumpNudge(tester, onLike: (offset) => likedFrom = offset);

    await tester.tap(find.byIcon(Icons.favorite_rounded));
    await tester.pump();

    expect(likedFrom, isNotNull);
    // The burst has to grow out of the heart the user actually tapped, so the
    // reported point must be that glyph's centre, not the widget origin.
    final heartCentre = tester.getCenter(find.byIcon(Icons.favorite_rounded));
    expect((likedFrom! - heartCentre).distance, lessThan(1.0));

    await _drainBeat(tester);
  });

  testWidgets('the close control dismisses without liking', (tester) async {
    var liked = false;
    var dismissed = false;
    await _pumpNudge(
      tester,
      onLike: (_) => liked = true,
      onDismiss: () => dismissed = true,
    );

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();

    expect(dismissed, isTrue);
    expect(liked, isFalse);

    await _drainBeat(tester);
  });

  testWidgets('sits on the notation panel and leaves the board uncovered', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const boardKey = Key('board');
    const notationKey = Key('notation');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          likeNudgeOfferProvider(0).overrideWith(
            (ref) => LikeNudgeOffer(onLike: (_) {}, onDismiss: () {}),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                backgroundColor: context.colors.background,
                body: Column(
                  children: [
                    const SizedBox(key: boardKey, height: 280, width: 390),
                    Expanded(
                      child: LikeNudgeOverlay(
                        pageIndex: 0,
                        child: const SizedBox.expand(key: notationKey),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    final nudge = tester.getRect(find.byType(LikeNudge));
    final board = tester.getRect(find.byKey(boardKey));
    final notation = tester.getRect(find.byKey(notationKey));

    expect(nudge.overlaps(board), isFalse);
    expect(nudge.overlaps(notation), isTrue);
    expect(nudge.top, greaterThanOrEqualTo(board.bottom));

    await _drainBeat(tester);
  });

  testWidgets('both controls clear the 44dp minimum tap target', (tester) async {
    await _pumpNudge(tester);

    for (final icon in [Icons.favorite_rounded, Icons.close_rounded]) {
      final target = find.ancestor(
        of: find.byIcon(icon),
        matching: find.byType(SizedBox),
      );
      final size = tester.getSize(target.first);
      expect(size.width, greaterThanOrEqualTo(44.0), reason: '$icon width');
      expect(size.height, greaterThanOrEqualTo(44.0), reason: '$icon height');
    }

    await _drainBeat(tester);
  });
}

/// The heart's double-beat runs on timers; let them all fire so no test ends
/// with a pending timer.
Future<void> _drainBeat(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Future<void> _pumpNudge(
  WidgetTester tester, {
  ValueChanged<Offset>? onLike,
  VoidCallback? onDismiss,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(
            backgroundColor: context.colors.background,
            body: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: LikeNudge(
                  onLike: onLike ?? (_) {},
                  onDismiss: onDismiss ?? () {},
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  if (settle) await tester.pump(const Duration(milliseconds: 16));
}
