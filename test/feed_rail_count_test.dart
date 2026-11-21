import 'dart:io';
import 'dart:math' as math;

import 'package:chessever2/screens/feed/widgets/feed_action_row.dart';
import 'package:chessever2/screens/feed/widgets/feed_layout.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The like count under the rail's heart is always whole: compact ("12.3K",
/// never "123,456"), in tabular figures, at one size per text size, and
/// clear of the frosted backing's round bottom end by at least [_air] at
/// every text size Feed allows and beyond, for the widest count there is.
///
/// Set in the app's own face (Inter), loaded here, so the widths are the
/// ones a phone draws.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final loader = FontLoader('InterDisplay');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      // Sync read: an async one never completes under the fake clock.
      loader.addFont(
        Future.value(
          ByteData.sublistView(
            File('assets/fonts/Inter-$weight.otf').readAsBytesSync(),
          ),
        ),
      );
    }
    await loader.load();
  });

  group('feedCompactCount', () {
    test('whole and short, rounded down, never past what happened', () {
      const cases = {
        0: '0',
        3: '3',
        128: '128',
        999: '999',
        1000: '1K',
        1049: '1K',
        1250: '1.2K',
        9999: '9.9K',
        12345: '12.3K',
        99999: '99.9K',
        100000: '100K',
        123456: '123K',
        999999: '999K',
        1000000: '1M',
        1234567: '1.2M',
        9999999: '9.9M',
        12345678: '12M',
        999999999: '999M',
        1000000000: '1B',
        1500000000: '1.5B',
        12500000000: '12B',
      };
      cases.forEach((count, label) {
        expect(feedCompactCount(count), label, reason: '$count');
      });
    });

    test('never longer than five characters, and never a separator', () {
      for (var count = 0; count < 20000000000; count = count * 3 + 7) {
        final label = feedCompactCount(count);
        expect(label.length, lessThanOrEqualTo(5), reason: '$count');
        expect(label.contains(','), isFalse, reason: '$count');
      }
    });

    test('the rail shows it from the floor up, a reader hears it exact', () {
      expect(feedLikeCount(kFeedLikeCountFloor - 1), isNull);
      expect(feedLikeCount(123456), '123K');
      expect(
        feedLikeSemantics(liked: false, likes: 123456),
        'Like, 123456 likes',
      );
    });
  });

  const counts = [
    3,
    128,
    9999,
    88888,
    123456,
    888888,
    8888888,
    888888888,
    8888888888,
  ];
  const scales = [1.0, 1.15, 1.3, 1.4, 2.0];

  for (final light in [false, true]) {
    for (final scale in scales) {
      testWidgets('every count clears the round end at ${scale}x '
          '(${light ? 'light' : 'dark'})', (tester) async {
        double? size;
        for (final likes in counts) {
          await _pumpRail(tester, likes: likes, scale: scale, light: light);
          final glass = tester.getRect(
            find.byKey(const ValueKey('feed_rail_glass')),
          );
          final count = find.byKey(const ValueKey('feed_rail_count'));
          final text = tester.widget<Text>(count);
          expect(text.data, feedCompactCount(likes));
          final fontSize = text.style!.fontSize!;
          // One size for every count at a text size: "128" and "88.8K"
          // never differ.
          size ??= fontSize;
          expect(fontSize, closeTo(size, 1e-9), reason: '$likes');

          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(of: count, matching: find.byType(RichText)),
          );
          final box = tester.getRect(count);
          // Whole: laid out on one line at its full width, nothing cut.
          expect(paragraph.didExceedMaxLines, isFalse);
          expect(box.width, lessThanOrEqualTo(FeedLayout.railCountRoom));
          final baseline =
              box.top +
              paragraph.computeDistanceToActualBaseline(
                TextBaseline.alphabetic,
              );
          // The figures' ink: from the baseline up a cap's height (0.73 em
          // in Inter; 0.75 to be safe), across the line's advance.
          final ink = Rect.fromLTRB(
            box.left,
            baseline - fontSize * 0.75,
            box.right,
            baseline,
          );
          for (final corner in [
            ink.topLeft,
            ink.topRight,
            ink.bottomLeft,
            ink.bottomRight,
          ]) {
            expect(
              _airInsideCapsule(glass, corner),
              greaterThanOrEqualTo(_air),
              reason: '$likes at ${scale}x: $corner in $glass',
            );
          }
          // Centred under the heart, on the rail's axis.
          expect(box.center.dx, closeTo(glass.center.dx, 0.01));
        }
        // At the reading size the count is set at its rest size: only a
        // large text size fits it smaller.
        if (scale == 1.0) expect(size, FeedRailMark.countSize);
      });
    }
  }
}

/// The least air between the count's ink and the backing's rim.
const double _air = 3;

/// How far [point] is inside the capsule [rect] (round ends, radius half
/// its width): negative when outside.
double _airInsideCapsule(Rect rect, Offset point) {
  final radius = rect.width / 2;
  final cx = rect.center.dx;
  final top = rect.top + radius;
  final bottom = rect.bottom - radius;
  final y = point.dy.clamp(top, bottom);
  final distance = math.sqrt(
    math.pow(point.dx - cx, 2) + math.pow(point.dy - y, 2),
  );
  return radius - distance;
}

Future<void> _pumpRail(
  WidgetTester tester, {
  required int likes,
  required double scale,
  required bool light,
}) async {
  await tester.pumpWidget(
    MediaQuery(
      data: const MediaQueryData(size: Size(393, 852)),
      child: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(393, 852),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: FeedLayout.railWidth,
              height:
                  FeedLayout.railCells * FeedLayout.railCellMin +
                  FeedLayout.railInsets,
              child: FeedActionRail(
                cellHeight: FeedLayout.railCellMin,
                liked: false,
                likes: likes,
                likeIconKey: GlobalKey(),
                onLike: () {},
                onShare: () {},
                onSave: () {},
                onAnalyze: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
}
