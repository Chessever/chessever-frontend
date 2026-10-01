import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event_id.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/my_space/actions/space_share.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/screens/player_profile/widgets/player_profile_resolved_event_card.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/event_card/event_image_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _MemoryShortcuts extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => [];

  @override
  Future<bool> add(SpaceShortcut draft) async {
    state = AsyncData([draft]);
    return true;
  }

  @override
  Future<SpaceShortcut?> remove(String id) async {
    final removed = state.requireValue.single;
    state = const AsyncData([]);
    return removed;
  }
}

class _NoFavorites extends FavoriteEventsNotifier {
  @override
  Future<List<FavoriteEvent>> build() async => [];
}

void main() {
  test(
    'fallback pins use reopenable broadcast or exact archive identities',
    () {
      final card = _event(id: 'player_event_raw', title: 'Archive event');
      const request = PlayerProfileEventCardRequest(
        dataSource: PlayerProfileDataSource.twic,
        tourId: 'raw-event',
        tourName: 'Archive event',
        site: 'Oslo NOR',
        broadcastSlug: 'archive-event',
      );
      final archive = playerProfileFallbackEventSpaceDraft(
        request: request,
        card: card,
        gamebaseKey: 'canonical:archive:2026',
      );
      final identity = virtualEventKeyFromId(archive.targetId)!;
      expect(identity.eventName, request.tourName);
      expect(identity.site, request.site);
      expect(identity.slug, 'canonical:archive:2026');
      expect(isSpaceCalendarEvent(archive), isFalse);
      expect(archive.canAddToMySpace, isTrue);

      final broadcast = playerProfileFallbackEventSpaceDraft(
        request: const PlayerProfileEventCardRequest(
          dataSource: PlayerProfileDataSource.supabase,
          tourId: 'real-broadcast',
          tourName: 'Broadcast event',
        ),
        card: card,
      );
      expect(broadcast.targetId, 'real-broadcast');
      expect(isSpaceCalendarEvent(broadcast), isFalse);
    },
  );

  for (final source in PlayerProfileDataSource.values) {
    testWidgets(
      'unresolved ${source.name} profile event has add and remove actions',
      (tester) async {
        final store = _MemoryShortcuts();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              playerEventCardProvider.overrideWith(
                (ref, request) async => null,
              ),
              spaceShortcutsProvider.overrideWith(() => store),
              favoriteEventsProvider.overrideWith(_NoFavorites.new),
              eventImageProvider.overrideWith(
                (ref, id) async => const EventImageData(),
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
                      child: PlayerProfileResolvedEventCard(
                        request: PlayerProfileEventCardRequest(
                          dataSource: source,
                          tourId: 'real-event',
                          tourName: 'Unresolved event',
                        ),
                        fallbackCard: _event(
                          id: 'player_event_real-event',
                          title: 'Unresolved event',
                          source: EventSource.communityEvent,
                        ),
                        gamebaseKey: 'archive-key',
                        trailingWidget: const SizedBox.shrink(),
                        heroTagSuffix: 'test-fallback',
                        onTap: (_) {},
                        statsRow: const SizedBox(height: 32),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.longPress(find.byType(EventCard));
        await tester.pumpAndSettle();
        expect(find.text('Open event'), findsOneWidget);
        expect(find.text('Add to My Space'), findsOneWidget);
        expect(find.text('Share'), findsNothing);
        await tester.tap(find.text('Add to My Space'));
        await tester.pumpAndSettle();
        final saved = store.state.requireValue.single;
        expect(
          saved.targetId,
          source == PlayerProfileDataSource.twic
              ? virtualBroadcastId('Unresolved event', slug: 'archive-key')
              : 'real-event',
        );
        expect(isSpaceCalendarEvent(saved), isFalse);

        await tester.longPress(find.byType(EventCard).first);
        await tester.pumpAndSettle();
        expect(find.text('Remove from My Space'), findsOneWidget);
        await tester.tap(find.text('Remove from My Space'));
        await tester.pumpAndSettle();
        expect(store.state.requireValue, isEmpty);
        await tester.pump(const Duration(seconds: 10));
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('a resolved profile event keeps only one full EventCard tree', (
    tester,
  ) async {
    const request = PlayerProfileEventCardRequest(
      dataSource: PlayerProfileDataSource.twic,
      tourId: 'raw-event',
      tourName: 'Raw event',
    );
    final resolved = _event(id: 'resolved', title: 'Resolved event');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerEventCardProvider.overrideWith(
            (ref, request) async => resolved,
          ),
          eventImageProvider.overrideWith(
            (ref, id) async => const EventImageData(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: SizedBox(
                  width: 360,
                  child: PlayerProfileResolvedEventCard(
                    request: request,
                    fallbackCard: _event(
                      id: 'fallback',
                      title: 'Fallback event',
                    ),
                    heroTagSuffix: 'test',
                    onTap: (_) {},
                    statsRow: const SizedBox(height: 32),
                    trailingWidget: const SizedBox.shrink(),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    final card = find.byType(PlayerProfileResolvedEventCard);
    expect(
      find.descendant(of: card, matching: find.byType(EventCard)),
      findsOneWidget,
    );
  });
}

GroupEventCardModel _event({
  required String id,
  required String title,
  EventSource source = EventSource.lichessBroadcast,
}) {
  return GroupEventCardModel(
    id: id,
    eventSource: source,
    title: title,
    dates: 'Jul 28, 2026',
    maxAvgElo: 2700,
    timeUntilStart: '',
    tourEventCategory: TourEventCategory.completed,
    timeControl: 'Blitz',
    startDate: DateTime.utc(2026, 7, 28),
    endDate: DateTime.utc(2026, 7, 28),
  );
}
