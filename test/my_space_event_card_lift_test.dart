import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart' show TappableScale;
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/event_card/event_image_provider.dart';
import 'package:chessever2/widgets/event_card/event_next_round_provider.dart';
import 'package:chessever2/widgets/hub_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// My Space's cards hold and press alike: an event card lifts into its menu
/// the way a smart event card does (the card itself steps out of sight under
/// its lifted copy), and the Prep and Library hub tiles press to the same
/// depth as every other card.

class _NoShortcuts extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];
}

class _NoFavoriteEvents extends FavoriteEventsNotifier {
  @override
  Future<List<FavoriteEvent>> build() async => const <FavoriteEvent>[];
}

class _NoSpoilersOff extends EventNoSpoilersController {
  _NoSpoilersOff(Ref ref, String tourId) : super(ref: ref, tourId: tourId);

  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(enabled: false, isLoading: false);
  }
}

class _Tours implements GroupBroadcastRepository {
  @override
  Future<List<String>> getTourIdsForGroupBroadcast(String id) async => const [
    'tour-1',
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _event = GroupEventCardModel(
  id: 'group-1',
  title: 'Sinquefield Cup 2026',
  dates: 'Aug 1 - 9, 2026',
  maxAvgElo: 2760,
  timeUntilStart: '',
  tourEventCategory: TourEventCategory.completed,
  timeControl: '90+30',
  startDate: DateTime(2026, 8, 1),
  endDate: DateTime(2026, 8, 9),
);

/// The card the event card's own long-press wraps: shown, or stepped out of
/// sight (its room kept) while the menu's copy is lifted.
bool _originalShown(WidgetTester tester) {
  final original = find.byType(EventCard).first;
  final hiding = find.descendant(
    of: original,
    matching: find.byWidgetPredicate(
      (widget) => widget is Visibility && widget.maintainSize,
    ),
  );
  expect(hiding, findsWidgets);
  return tester.widget<Visibility>(hiding.first).visible;
}

void main() {
  testWidgets('an event card\'s long-press hides the card under its lifted '
      'copy, as a smart event card\'s does, and brings it back', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          spaceShortcutsProvider.overrideWith(_NoShortcuts.new),
          favoriteEventsProvider.overrideWith(_NoFavoriteEvents.new),
          eventImageProvider.overrideWith(
            (ref, id) async => const EventImageData(),
          ),
          eventNoSpoilersProvider.overrideWith(
            (ref, tourId) => _NoSpoilersOff(ref, tourId),
          ),
          groupBroadcastRepositoryProvider.overrideWithValue(_Tours()),
          eventNextRoundProvider.overrideWith((ref, id) async => null),
          liveGroupBroadcastIdsProvider.overrideWith(
            (ref) => Stream.value(const <String>[]),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: EventCard(
                      tourEventCardModel: _event,
                      favoritePlayersSource:
                          EventFavoritePlayersSource.cacheOnly,
                      heroTagSuffix: 'test',
                      onTap: () {},
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final rest = tester.getRect(find.byType(EventCard).first);
    expect(_originalShown(tester), isTrue);

    await tester.longPress(find.byType(EventCard).first);
    await tester.pumpAndSettle();
    expect(find.text('Add to My Space'), findsOneWidget);
    // Lifted: the copy stands in for the card, which keeps its room.
    expect(find.byType(EventCard), findsNWidgets(2));
    expect(_originalShown(tester), isFalse);
    expect(tester.getRect(find.byType(EventCard).first), rest);

    // Dismissed: the card is back where it was.
    await tester.tapAt(const Offset(8, 590));
    await tester.pumpAndSettle();
    expect(find.text('Add to My Space'), findsNothing);
    expect(_originalShown(tester), isTrue);
    expect(tester.getRect(find.byType(EventCard).first), rest);

    await tester.pump(const Duration(seconds: 1));
  });

  test('the hub tiles press to the depth every other My Space card does', () {
    final card = TappableScale(onTap: () {}, child: const SizedBox());
    expect(HubTilePress.pressedScale, card.scaleDown);
    expect(HubTilePress.pressedScale, 0.96);
  });
}
