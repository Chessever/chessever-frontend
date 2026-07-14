import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_scroll_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  testWidgets(
    'removes its scroll pause reason safely when unmounted while scrolling',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: GamesTourScrollActivityDetector(
              scopeId: 'for_you',
              child: ListView(children: const <Widget>[SizedBox(height: 1200)]),
            ),
          ),
        ),
      );

      await tester.drag(find.byType(ListView), const Offset(0, -100));

      expect(container.read(liveGameCardsPausedProvider), isTrue);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SizedBox.shrink(),
        ),
      );

      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 1));
      expect(container.read(liveGameCardsPauseReasonsProvider), isEmpty);
    },
  );

  testWidgets(
    'unmounting one detector does not resume cards paused by another',
    (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      Widget build({required bool includeFirst}) {
        final detectors = <Widget>[
          if (includeFirst)
            Expanded(
              key: const ValueKey('first-slot'),
              child: GamesTourScrollActivityDetector(
                key: const ValueKey('first-detector'),
                scopeId: 'shared',
                child: ListView(
                  key: const ValueKey('first-list'),
                  children: const <Widget>[SizedBox(height: 1200)],
                ),
              ),
            ),
          Expanded(
            key: const ValueKey('second-slot'),
            child: GamesTourScrollActivityDetector(
              key: const ValueKey('second-detector'),
              scopeId: 'shared',
              child: ListView(
                key: const ValueKey('second-list'),
                children: const <Widget>[SizedBox(height: 1200)],
              ),
            ),
          ),
        ];

        return UncontrolledProviderScope(
          container: container,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Column(children: detectors),
          ),
        );
      }

      await tester.pumpWidget(build(includeFirst: true));
      await tester.drag(
        find.byKey(const ValueKey('first-list')),
        const Offset(0, -100),
      );
      await tester.drag(
        find.byKey(const ValueKey('second-list')),
        const Offset(0, -100),
      );

      expect(container.read(liveGameCardsPauseReasonsProvider), hasLength(2));

      await tester.pumpWidget(build(includeFirst: false));
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(milliseconds: 1));

      expect(container.read(liveGameCardsPauseReasonsProvider), hasLength(1));
      expect(container.read(liveGameCardsPausedProvider), isTrue);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SizedBox.shrink(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets('moves an active pause reason safely when its scope changes', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    Widget build(String scopeId) {
      return UncontrolledProviderScope(
        container: container,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: GamesTourScrollActivityDetector(
            key: const ValueKey('detector'),
            scopeId: scopeId,
            child: ListView(
              key: const ValueKey('list'),
              children: const <Widget>[SizedBox(height: 1200)],
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(build('old-scope'));
    await tester.drag(
      find.byKey(const ValueKey('list')),
      const Offset(0, -100),
    );

    await tester.pumpWidget(build('new-scope'));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 1));

    final reasons = container.read(liveGameCardsPauseReasonsProvider);
    expect(reasons, hasLength(1));
    expect(reasons.single, startsWith('games_tour_scroll_new-scope_'));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const SizedBox.shrink(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1));
  });
}
