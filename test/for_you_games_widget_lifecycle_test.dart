import 'package:chessever2/main.dart' show pageRouteObserver;
import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/screens/for_you/providers/for_you_tab_provider.dart';
import 'package:chessever2/screens/group_event/widget/for_you_games_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  testWidgets(
    'route subscription does not publish visibility during widget build',
    (tester) async {
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      final container = ProviderContainer(
        overrides: [
          // Another For You page (or another section) is showing.
          forYouTodayTabActiveProvider.overrideWith((ref) => false),
          forYouSurfaceVisibleProvider.overrideWith((ref) => true),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorObservers: [pageRouteObserver],
            home: ForYouGamesWidget(scrollController: scrollController),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(container.read(forYouSurfaceVisibleProvider), isFalse);

      container.read(forYouSurfaceVisibleProvider.notifier).state = true;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(container.read(forYouSurfaceVisibleProvider), isFalse);
    },
  );
}
