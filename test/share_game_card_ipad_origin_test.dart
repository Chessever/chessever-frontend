// The board's Share Game overlay on iPad (simulator run, 2026-11-23): Share
// Image and Share GIF opened the share popover from the screen's bottom
// centre, over the overlay's own action row, while every other share in the
// app rises from the control that was tapped. These drive the real overlay
// to the real share call (share_plus' platform channel) and read where the
// popover is anchored.

import 'dart:io';

import 'package:chessever2/screens/chessboard/widgets/share_game_card_overlay.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/share_card.dart';
import 'package:chessground/chessground.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// An 11-inch iPad, portrait.
const _ipad = Size(834, 1194);

void main() {
  late Directory temp;
  late List<Map<Object?, Object?>> shared;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('share_origin_');
    shared = [];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => temp.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/share'),
      (call) async {
        shared.add(call.arguments as Map<Object?, Object?>);
        return 'success';
      },
    );
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/share'),
      null,
    );
    temp.deleteSync(recursive: true);
  });

  Future<void> pumpOverlay(WidgetTester tester, {required String pgn}) async {
    tester.view
      ..physicalSize = _ipad * 2
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return ShareGameCardOverlay(
                boardSettings: const ChessboardSettings(),
                positionFen: '8/8/4k3/8/8/4K3/8/8 w - - 0 60',
                lastMove: null,
                pgn: pgn,
                moveSans: const [],
                whitePlayerName: 'Carlsen, Magnus',
                blackPlayerName: 'Nakamura, Hikaru',
                currentMoveIndex: 0,
                evaluation: 0.0,
                mate: 0,
                isFlipped: false,
                gameStatus: GameStatus.ongoing,
                onClose: () {},
                shareUrl: 'https://chessever.com/games/abc123',
                gameId: 'abc123',
              );
            },
          ),
        ),
      ),
    );
    // The entrance springs settle and the export card is built.
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// The card is rendered to a PNG and written to disk before the share:
  /// both are real work outside the test's clock.
  Future<void> untilShared(WidgetTester tester) async {
    for (var i = 0; i < 80 && shared.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
  }

  Finder button(String label) => find
      .ancestor(of: find.text(label), matching: find.byType(GestureDetector))
      .first;

  Rect origin(Map<Object?, Object?> call) => Rect.fromLTWH(
    (call['originX']! as num).toDouble(),
    (call['originY']! as num).toDouble(),
    (call['originWidth']! as num).toDouble(),
    (call['originHeight']! as num).toDouble(),
  );

  testWidgets('Share Image anchors the iPad popover at the tapped button', (
    tester,
  ) async {
    await pumpOverlay(tester, pgn: '1. e4 e5 *');
    final tapped = tester.getRect(button('Share Image'));

    await tester.tap(button('Share Image'));
    await untilShared(tester);

    expect(shared, hasLength(1));
    // Where the tapped button stands when the sheet opens (the overlay can
    // re-lay its row between the tap and the share): the same button.
    // The row may still be settling on its spring after the sheet opens:
    // the anchor is that button's box, a few points from where it rests.
    final atShare = tester.getRect(button('Share Image'));
    final anchor = origin(shared.single);
    expect(anchor.left, tapped.left);
    expect(anchor.right, tapped.right);
    expect(anchor.height, closeTo(atShare.height, 0.5));
    expect((anchor.top - atShare.top).abs(), lessThan(12));
    expect(
      origin(shared.single),
      isNot(shareScreenBottomOrigin()),
      reason: 'never the bottom centre over the action row',
    );
  });

  testWidgets('Share GIF anchors the iPad popover at the tapped button', (
    tester,
  ) async {
    // A game with no moves has nothing to animate: Share GIF shares the
    // image, still from its own button.
    await pumpOverlay(tester, pgn: '*');
    final tapped = tester.getRect(button('Share GIF'));
    expect(tapped, isNot(tester.getRect(button('Share Image'))));

    await tester.tap(button('Share GIF'));
    await untilShared(tester);

    expect(shared, hasLength(1));
    // The row may still be settling on its spring after the sheet opens:
    // the anchor is that button's box, a few points from where it rests.
    final atShare = tester.getRect(button('Share GIF'));
    final anchor = origin(shared.single);
    expect(anchor.left, tapped.left);
    expect(anchor.right, tapped.right);
    expect(anchor.height, closeTo(atShare.height, 0.5));
    expect((anchor.top - atShare.top).abs(), lessThan(12));
  });
}
