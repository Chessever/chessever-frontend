import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/notification_preferences_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/smart_event_card.dart';
import 'package:chessever2/widgets/event_card/smart_event_star.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/star_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final _stamp = DateTime.utc(2026, 10, 12);

/// The favorites table in memory: what each star wrote, in order.
class _Favorites extends FavoriteEventsNotifier {
  _Favorites(this._initial);

  final List<FavoriteEvent> _initial;
  final added = <FavoriteEvent>[];
  final removed = <String>[];
  final patches = <(String, Map<String, dynamic>)>[];

  @override
  Future<List<FavoriteEvent>> build() async => _initial;

  List<FavoriteEvent> get _rows => state.valueOrNull ?? const [];

  @override
  Future<void> addFavorite({
    required String eventId,
    required String eventName,
    String? timeControl,
    int? maxAvgElo,
    String? dates,
    Map<String, dynamic>? extraMetadata,
  }) async {
    final row = FavoriteEvent(
      id: 'row_${added.length}',
      userId: 'user',
      eventId: eventId,
      eventName: eventName,
      metadata: {...?extraMetadata},
      createdAt: _stamp,
      updatedAt: _stamp,
    );
    added.add(row);
    state = AsyncData([..._rows, row]);
  }

  @override
  Future<void> removeFavorite(String eventId, {String? eventName}) async {
    removed.add(eventId);
    state = AsyncData([
      for (final row in _rows)
        if (row.eventId != eventId) row,
    ]);
  }

  @override
  Future<void> updateMetadata(
    String eventId,
    Map<String, dynamic> patch,
  ) async {
    patches.add((eventId, patch));
    state = AsyncData([
      for (final row in _rows)
        if (row.eventId == eventId)
          FavoriteEvent(
            id: row.id,
            userId: row.userId,
            eventId: row.eventId,
            eventName: row.eventName,
            metadata: {...row.metadata, ...patch},
            createdAt: row.createdAt,
            updatedAt: row.updatedAt,
          )
        else
          row,
    ]);
  }
}

class _Prefs extends NotificationPreferencesNotifier {
  @override
  Future<NotificationPreferences> build() async =>
      const NotificationPreferences(
        favoriteEventAlerts: true,
        favoritePlayerAlerts: true,
        headsUpAlerts: false,
        dailyDigest: false,
        callToActionAlerts: false,
        bookUpdateAlerts: true,
        fpClassical: true,
        fpRapid: true,
        fpBlitz: false,
        seClassical: true,
        seRapid: true,
        seBlitz: false,
        headsUpLeadMinutes: 30,
      );
}

SmartEventRequest _request({GameEcoFilter? eco}) => SmartEventRequest(
  source: SmartEventSource.forYou,
  tierLabel: 'GM',
  titleSuffix: 'Games',
  minElo: 2500,
  maxElo: 3000,
  caption: 'From your 2500+ filter',
  countSingular: 'event',
  countPlural: 'events',
  events: const [],
  formatsAndStates: const {'standard'},
  eco: eco,
);

FavoriteEvent _starred(SmartEventRequest request) => FavoriteEvent(
  id: 'saved',
  userId: 'user',
  eventId: request.favoriteEventId,
  eventName: request.displayName,
  metadata: request.toFavoriteMetadata(),
  createdAt: _stamp,
  updatedAt: _stamp,
);

Future<_Favorites> _pump(
  WidgetTester tester, {
  SmartEventRequest? starRequest,
  List<FavoriteEvent> favorites = const [],
}) async {
  final store = _Favorites(favorites);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        favoriteEventsProvider.overrideWith(() => store),
        notificationPreferencesProvider.overrideWith(_Prefs.new),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: SmartEventCard(
                tierLabel: 'GM',
                minElo: 2500,
                liveCount: 3,
                avgElo: 2728,
                formatsAndStates: const {'standard'},
                starRequest: starRequest,
                onTap: () {},
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return store;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump(const Duration(seconds: 1));
}

final _chevron = find.byIcon(Icons.chevron_right_rounded);
final _star = find.byType(SmartEventStar);
final _question = find.text('Turn on notifications?');

void main() {
  testWidgets('ends in its star in the Events lists, and in the open chevron '
      'where no star is asked for', (tester) async {
    await _pump(tester, starRequest: _request());
    expect(_star, findsOneWidget);
    expect(_chevron, findsNothing);

    await _pump(tester);
    expect(_star, findsNothing);
    expect(_chevron, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the star takes the chevron\'s place: the card keeps its size', (
    tester,
  ) async {
    await _pump(tester);
    final withChevron = tester.getSize(find.byType(SmartEventCard));

    await _pump(tester, starRequest: _request());
    expect(tester.getSize(find.byType(SmartEventCard)), withChevron);
  });

  testWidgets('starring saves the smart event at once, then asks; a yes is '
      'written onto the row', (tester) async {
    final request = _request();
    final store = await _pump(tester, starRequest: request);

    await tester.tap(_star);
    await _settle(tester);

    expect(store.added.single.eventId, request.favoriteEventId);
    expect(store.added.single.metadata['type'], 'smart_event');
    expect(starNotificationsEnabled(store.added.single), isFalse);
    expect(_question, findsOneWidget);
    expect(
      find.text(
        'Get round start and result alerts for every event in GM Games.',
      ),
      findsOneWidget,
    );
    expect(store.patches, isEmpty);

    await tester.tap(find.text('Turn on'));
    await _settle(tester);

    expect(_question, findsNothing);
    final (patchedId, patch) = store.patches.single;
    expect(patchedId, request.favoriteEventId);
    expect(patch, {kStarNotificationsKey: true});
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Not now" keeps the star and leaves it quiet', (tester) async {
    final request = _request();
    final store = await _pump(tester, starRequest: request);

    await tester.tap(_star);
    await _settle(tester);
    await tester.tap(find.text('Not now'));
    await _settle(tester);

    expect(store.added, hasLength(1));
    expect(store.removed, isEmpty);
    expect(store.patches, isEmpty);
    expect(_question, findsNothing);
  });

  testWidgets('dismissing the question is not an answer: still starred, '
      'still quiet', (tester) async {
    final store = await _pump(tester, starRequest: _request());

    await tester.tap(_star);
    await _settle(tester);
    await tester.tapAt(const Offset(4, 4));
    await _settle(tester);

    expect(_question, findsNothing);
    expect(store.added, hasLength(1));
    expect(store.removed, isEmpty);
    expect(store.patches, isEmpty);
  });

  testWidgets('unstarring removes the row and asks nothing', (tester) async {
    final request = _request();
    final store = await _pump(
      tester,
      starRequest: request,
      favorites: [_starred(request)],
    );

    await tester.tap(_star);
    await _settle(tester);

    expect(store.removed, [request.favoriteEventId]);
    expect(store.added, isEmpty);
    expect(_question, findsNothing);
  });

  testWidgets('an opening smart event is starred without the question', (
    tester,
  ) async {
    final request = _request(eco: GameEcoFilter.forCode('B90'));
    final store = await _pump(tester, starRequest: request);

    await tester.tap(_star);
    await _settle(tester);

    expect(store.added.single.eventId, request.favoriteEventId);
    expect(_question, findsNothing);
    expect(store.patches, isEmpty);
  });
}
