import 'package:chessever2/screens/tour_detail/widgets/event_games_list_end.dart';
import 'package:chessever2/screens/tour_detail/widgets/event_games_no_matches.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:chessever2/widgets/search_no_matches.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The event Games list's no-hits state and its end, on the shared pieces
/// every Games list uses ([SearchNoMatches], [SearchModeListEnd]).
Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(body: child);
        },
      ),
    ),
  );
}

void main() {
  final title = find.byKey(const ValueKey('search_no_matches_title'));
  final clear = find.byKey(const ValueKey('search_no_matches_clear'));

  testWidgets('echoes the words searched in the shared line', (tester) async {
    await _pump(tester, const EventGamesNoMatches(query: '  carlsen '));

    expect(find.byType(SearchNoMatches), findsOneWidget);
    expect(tester.widget<Text>(title).data, 'No matches for "carlsen"');
  });

  testWidgets('with no words, says only that nothing matched', (tester) async {
    await _pump(tester, const EventGamesNoMatches(query: null));

    expect(tester.widget<Text>(title).data, 'No matching games');
  });

  testWidgets('offers no way back when no search is open over it', (
    tester,
  ) async {
    await _pump(tester, const EventGamesNoMatches(query: 'carlsen'));

    // Nothing to clear: no search mode above it.
    expect(clear, findsNothing);
  });

  testWidgets('the list end keeps clear of the floating buttons with no '
      'search mode above it', (tester) async {
    await _pump(
      tester,
      ListView(children: const [SizedBox(height: 40), EventGamesListEnd()]),
    );

    final context = tester.element(find.byType(EventGamesListEnd));
    expect(
      tester.getSize(find.byType(EventGamesListEnd)).height,
      moreOrLessEquals(
        EventGamesListEnd.margin + EventGamesListEnd.buttonsReach(context),
      ),
    );
  });
}
