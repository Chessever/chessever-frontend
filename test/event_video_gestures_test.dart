import 'package:chessever2/screens/chessboard/video/video_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercise Flutter's actual platform-view gesture arena without starting a
/// native WebView or contacting a video provider.
class _RecordingPlatformView extends PlatformViewController {
  final events = <PointerEvent>[];
  @override
  final int viewId = 9876;
  @override
  Future<void> dispatchPointerEvent(PointerEvent event) async =>
      events.add(event);
  @override
  Future<void> clearFocus() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  testWidgets(
    'existing eager platform view adopts the scroll-friendly policy',
    (tester) async {
      final scroll = ScrollController();
      final pages = PageController();
      final view = _RecordingPlatformView();
      await tester.pumpWidget(
        _harness(
          view,
          scroll,
          pages,
          gestureRecognizers: {
            Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
          },
        ),
      );
      await tester.drag(
        find.byType(PlatformViewSurface),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      view.events.clear();
      await tester.pumpWidget(_harness(view, scroll, pages));
      await tester.drag(
        find.byType(PlatformViewSurface),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(60));
      expect(view.events.whereType<PointerMoveEvent>(), isEmpty);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
      pages.dispose();
    },
  );

  testWidgets(
    'vertical drags from the video scroll the surrounding game in both directions',
    (tester) async {
      final scroll = ScrollController();
      final pages = PageController();
      final view = _RecordingPlatformView();
      await tester.pumpWidget(_harness(view, scroll, pages));
      final video = find.byType(PlatformViewSurface);
      await tester.drag(video, const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(80));
      expect(view.events.whereType<PointerMoveEvent>(), isEmpty);
      expect(pages.page, 0);
      final afterUp = scroll.offset;
      await tester.drag(video, const Offset(0, 80));
      await tester.pumpAndSettle();
      expect(scroll.offset, lessThan(afterUp));
      expect(view.events.whereType<PointerMoveEvent>(), isEmpty);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
      pages.dispose();
    },
  );

  testWidgets('video taps reach the provider and still reveal flag controls', (
    tester,
  ) async {
    final scroll = ScrollController();
    final pages = PageController();
    final view = _RecordingPlatformView();
    var touches = 0;
    await tester.pumpWidget(
      _harness(view, scroll, pages, onTouch: () => touches++),
    );
    await tester.tap(find.byType(PlatformViewSurface));
    await tester.pump();
    expect(view.events.whereType<PointerDownEvent>(), hasLength(1));
    expect(view.events.whereType<PointerUpEvent>(), hasLength(1));
    expect(touches, 1);
    expect(scroll.offset, 0);
    await tester.pumpWidget(const SizedBox());
    scroll.dispose();
    pages.dispose();
  });

  testWidgets(
    'horizontal video gestures seek without swiping to another game',
    (tester) async {
      final scroll = ScrollController();
      final pages = PageController();
      final view = _RecordingPlatformView();
      await tester.pumpWidget(_harness(view, scroll, pages));
      await tester.drag(
        find.byType(PlatformViewSurface),
        const Offset(-200, 0),
      );
      await tester.pumpAndSettle();
      expect(view.events.whereType<PointerMoveEvent>(), isNotEmpty);
      expect(pages.page, 0);
      expect(scroll.offset, 0);
      await tester.pumpWidget(const SizedBox());
      scroll.dispose();
      pages.dispose();
    },
  );
}

Widget _harness(
  _RecordingPlatformView view,
  ScrollController scroll,
  PageController pages, {
  VoidCallback? onTouch,
  Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers =
      eventVideoGestureRecognizers,
}) => MaterialApp(
  home: Scaffold(
    body: PageView(
      controller: pages,
      children: [
        SingleChildScrollView(
          controller: scroll,
          child: Column(
            children: [
              const SizedBox(height: 160),
              Listener(
                onPointerDown: (_) => onTouch?.call(),
                child: SizedBox(
                  height: 240,
                  child: PlatformViewSurface(
                    controller: view,
                    gestureRecognizers: gestureRecognizers,
                    hitTestBehavior: PlatformViewHitTestBehavior.opaque,
                  ),
                ),
              ),
              const SizedBox(height: 1000, child: Text('Notation')),
            ],
          ),
        ),
        const Center(child: Text('Next game')),
      ],
    ),
  ),
);
