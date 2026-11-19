import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/notification_preferences_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart'
    show smartEventSpaceDraft;
import 'package:chessever2/screens/my_space/actions/space_star_pin.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_auto_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/smart_event_card.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
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

/// My Space in memory.
class _Space extends SpaceShortcutsNotifier {
  _Space(this.seed);

  final List<SpaceShortcut> seed;

  @override
  Future<List<SpaceShortcut>> build() async => seed;

  @override
  Future<bool> add(SpaceShortcut draft) async {
    final list = state.valueOrNull ?? const <SpaceShortcut>[];
    if (!draft.canAddToMySpace || list.any((s) => s.key == draft.key)) {
      return false;
    }
    state = AsyncData([draft, ...list]);
    return true;
  }
}

class _Hidden extends SpaceHiddenAutoKeys {
  @override
  Set<String> build() => const {};
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
  bool editing = false,
  SpaceShortcut? spaceDraft,
  VoidCallback? onTap,
  List<SpaceShortcut> pins = const [],
  bool starPins = false,
}) async {
  final store = _Favorites(favorites);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        favoriteEventsProvider.overrideWith(() => store),
        notificationPreferencesProvider.overrideWith(_Prefs.new),
        spaceShortcutsProvider.overrideWith(() => _Space(pins)),
        spaceHiddenAutoKeysProvider.overrideWith(_Hidden.new),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            final card = SmartEventCard(
              tierLabel: 'GM',
              minElo: 2500,
              liveCount: 3,
              avgElo: 2728,
              formatsAndStates: const {'standard'},
              starRequest: starRequest,
              editing: editing,
              spaceDraft: spaceDraft,
              onTap: onTap ?? () {},
            );
            return Scaffold(body: starPins ? SpaceStarPins(child: card) : card);
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

  testWidgets('in My Space\'s Edit the star keeps its place, faded out, and '
      'a tap on it stars nothing', (tester) async {
    final request = _request();
    await _pump(tester, starRequest: request);
    final rest = tester.getSize(find.byType(SmartEventCard));
    final title = tester.getRect(find.text('GM Games'));

    final store = await _pump(tester, starRequest: request, editing: true);
    await tester.pump(const Duration(milliseconds: 400));
    expect(_star, findsOneWidget);
    expect(
      tester
          .widget<Opacity>(
            find.ancestor(of: _star, matching: find.byType(Opacity)).first,
          )
          .opacity,
      0,
    );
    expect(tester.getSize(find.byType(SmartEventCard)), rest);
    expect(tester.getRect(find.text('GM Games')), title);

    await tester.tap(_star, warnIfMissed: false);
    await _settle(tester);
    expect(store.added, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a hold lifts the card as an event card lifts: the shared '
      'focus menu, the card hidden under its copy, Open smart event first', (
    tester,
  ) async {
    final request = _request();
    final draft = smartEventSpaceDraft(request);
    var opens = 0;
    await _pump(
      tester,
      starRequest: request,
      spaceDraft: draft,
      onTap: () => opens++,
    );
    final card = find.byType(SmartEventCard);
    expect(
      find.descendant(of: card, matching: find.byType(CardContextMenu)),
      findsOneWidget,
    );

    await tester.longPress(card);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Open smart event'), findsOneWidget);
    expect(find.text('Add to My Space'), findsOneWidget);
    expect(
      tester
          .widget<Visibility>(
            find
                .descendant(
                  of: find.byType(CardContextMenu),
                  matching: find.byType(Visibility),
                )
                .first,
          )
          .visible,
      isFalse,
    );
    expect(
      tester.getTopLeft(find.text('Open smart event')).dy,
      lessThan(tester.getTopLeft(find.text('Add to My Space')).dy),
    );

    await tester.tap(find.text('Open smart event'));
    await _settle(tester);
    expect(opens, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('starring saves the smart event subscribed, and asks nothing', (
    tester,
  ) async {
    final request = _request();
    final store = await _pump(tester, starRequest: request);

    await tester.tap(_star);
    await _settle(tester);

    expect(store.added.single.eventId, request.favoriteEventId);
    expect(store.added.single.metadata['type'], 'smart_event');
    expect(starNotificationsEnabled(store.added.single), isTrue);
    expect(_question, findsNothing);
    expect(store.patches, isEmpty);
    expect(tester.takeException(), isNull);
  });

  test('a smart star always notifies: there is no switch, whatever an old '
      'build saved', () {
    final saved = _starred(_request());
    expect(starNotificationsEnabled(saved), isTrue);
    expect(
      starNotificationsEnabled(
        FavoriteEvent(
          id: saved.id,
          userId: saved.userId,
          eventId: saved.eventId,
          eventName: saved.eventName,
          metadata: {...saved.metadata, kStarNotificationsKey: false},
          createdAt: _stamp,
          updatedAt: _stamp,
        ),
      ),
      isTrue,
    );
  });

  group('on the Search tab (SpaceStarPins)', () {
    bool pinned(WidgetTester tester, SmartEventRequest request) =>
        ProviderScope.containerOf(
          tester.element(find.byType(SmartEventCard)),
        ).read(spaceShortcutExistsProvider(smartEventSpaceDraft(request).key));

    testWidgets('a star also keeps the smart event in My Space, and says so '
        'once', (tester) async {
      final request = _request();
      final store = await _pump(tester, starRequest: request, starPins: true);
      expect(pinned(tester, request), isFalse);

      await tester.tap(_star);
      await _settle(tester);
      expect(store.added.single.eventId, request.favoriteEventId);
      expect(pinned(tester, request), isTrue);
      expect(find.text('Added to My Space'), findsOneWidget);

      // An unstar stops the pushes and leaves My Space as it is.
      await tester.tap(_star);
      await _settle(tester);
      expect(store.removed, [request.favoriteEventId]);
      expect(pinned(tester, request), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a smart event already in My Space is starred without a word '
        'about it', (tester) async {
      final request = _request();
      await _pump(
        tester,
        starRequest: request,
        starPins: true,
        pins: [smartEventSpaceDraft(request)],
      );
      await tester.tap(_star);
      await _settle(tester);
      expect(pinned(tester, request), isTrue);
      expect(find.text('Added to My Space'), findsNothing);
    });

    testWidgets('anywhere else a star is a star only', (tester) async {
      final request = _request();
      final store = await _pump(tester, starRequest: request);
      await tester.tap(_star);
      await _settle(tester);
      expect(store.added, hasLength(1));
      expect(pinned(tester, request), isFalse);
      expect(find.text('Added to My Space'), findsNothing);
    });
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

  testWidgets('an opening smart event is starred subscribed too', (
    tester,
  ) async {
    final request = _request(eco: GameEcoFilter.forCode('B90'));
    final store = await _pump(tester, starRequest: request);

    await tester.tap(_star);
    await _settle(tester);

    expect(store.added.single.eventId, request.favoriteEventId);
    expect(starNotificationsEnabled(store.added.single), isTrue);
    expect(_question, findsNothing);
  });

  test('a push opens the smart event it names, from the saved row or from '
      'its criteria', () {
    final request = _request(eco: GameEcoFilter.forCode('B9'));
    final saved = _starred(request);
    final data = <String, dynamic>{
      'type': 'smart_event_games',
      'smart_event_id': request.favoriteEventId,
      'smart_event_name': 'Sicilian: Najdorf Games',
      'min_elo': 2500,
      'max_elo': 3000,
      'formats': ['standard'],
      'eco_code': 'B9',
      'label': 'GM',
    };

    final fromRow = smartEventRequestFromPushData(data, favorites: [saved]);
    expect(fromRow?.criteriaKey, request.criteriaKey);

    final fromPush = smartEventRequestFromPushData(data);
    expect(fromPush?.criteriaKey, request.criteriaKey);
    expect(fromPush?.favoriteEventId, request.favoriteEventId);

    expect(
      smartEventRequestFromPushData({'type': 'smart_event_games'}),
      isNull,
    );
  });
}
