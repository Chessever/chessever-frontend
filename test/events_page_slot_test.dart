import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/widget/all_events_tab_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/event_image_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// The Events Past list pages more in as its end comes near. Its end keeps
// one slot of one height whether a page is loading or not: a list that
// changed length at the page point would read to the scroll chrome as the
// reader scrolling, and tug the bars (scroll audit S1).

final _events = List.generate(
  12,
  (index) => GroupEventCardModel(
    id: 'past-$index',
    title: 'Past Open $index',
    dates: 'November 4 - 18, 2026',
    startDate: DateTime(2026, 11, 4),
    endDate: DateTime(2026, 11, 18),
    maxAvgElo: 2600,
    timeUntilStart: '',
    tourEventCategory: TourEventCategory.completed,
    timeControl: '90+30',
    eventSource: EventSource.lichessBroadcast,
  ),
);

class _NoFavorites extends FavoriteEventsNotifier {
  @override
  Future<List<FavoriteEvent>> build() async => const [];
}

Future<void> _pump(
  WidgetTester tester,
  ScrollController scroll, {
  required bool loading,
  bool paged = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        favoriteEventsProvider.overrideWith(_NoFavorites.new),
        eventImageProvider.overrideWith(
          (ref, id) async => const EventImageData(),
        ),
        liveGroupBroadcastIdsProvider.overrideWith(
          (ref) => Stream.value(const <String>[]),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: AllEventsTabWidget(
            filteredEvents: _events,
            scrollController: scroll,
            isLoadingMore: loading,
            paged: paged,
            onSelect: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() => ResponsiveHelper.initFromSize(const Size(393, 852)));

  testWidgets('a page loading never changes the list\'s length', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await _pump(tester, scroll, loading: false);
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    final idle = scroll.position.maxScrollExtent;
    expect(find.byKey(const ValueKey('events_page_slot')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await _pump(tester, scroll, loading: true);
    expect(scroll.position.maxScrollExtent, idle);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await _pump(tester, scroll, loading: false);
    expect(scroll.position.maxScrollExtent, idle);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a list that does not page keeps no slot', (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await _pump(tester, scroll, loading: false, paged: false);
    expect(find.byKey(const ValueKey('events_page_slot')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
