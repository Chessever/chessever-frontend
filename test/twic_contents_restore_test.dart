import 'dart:async';

import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/library/providers/gamebase_database_games_provider.dart';
import 'package:chessever2/screens/library/providers/twic_event_aggregates_provider.dart';
import 'package:chessever2/screens/library/twic_contents_screen.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Every database screen shares one search, event and filter. One opened
/// over another (an event tapped on a game opened from it, or from that
/// game's Watch post) must not leave the one under it on its own search.
void main() {
  testWidgets('a database screen gets its own search back when the one '
      'opened over it closes', (tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gamebaseRepositoryProvider.overrideWithValue(_OfflineGamebase()),
          twicDatabaseTotalGamesProvider.overrideWith((ref) async => 0),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          navigatorObservers: [routeObserver],
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return const TwicContentsScreen(initialEvent: 'Tata Steel');
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TwicContentsScreen)),
    );
    expect(container.read(librarySearchQueryProvider), 'Tata Steel');

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const TwicContentsScreen(initialEvent: 'Norway Chess'),
      ),
    );
    await _frames(tester);
    expect(container.read(librarySearchQueryProvider), 'Norway Chess');

    navigator.pop();
    await _frames(tester);
    expect(container.read(librarySearchQueryProvider), 'Tata Steel');
    expect(container.read(twicSelectedEventProvider), isNull);
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).first)
          .controller
          .text,
      'Tata Steel',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

/// The loading skeleton never settles: run the route transition out.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// No network in tests: every gamebase call stays pending, so no load lands
/// on a list that a newer search has already replaced.
class _OfflineGamebase implements GamebaseRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => Completer<Never>().future;
}
