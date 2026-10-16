import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/notification_preferences_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/collections/collections_screen.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/star_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final _stamp = DateTime.utc(2026, 10, 12);

const _collection = Collection(
  id: 'c1',
  slug: 'candidates-2026',
  kind: CollectionKind.event,
  title: 'Candidates 2026',
  gameCount: 56,
);

FavoriteEvent _row(
  String eventId, {
  Map<String, dynamic> metadata = const {},
}) => FavoriteEvent(
  id: eventId,
  userId: 'user',
  eventId: eventId,
  eventName: _collection.title,
  metadata: metadata,
  createdAt: _stamp,
  updatedAt: _stamp,
);

/// The favorites table in memory: what each star wrote, in order.
class _Favorites extends FavoriteEventsNotifier {
  _Favorites(this._initial);

  final List<FavoriteEvent> _initial;
  final added = <String>[];
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
    added.add(eventId);
    state = AsyncData([
      ..._rows,
      _row(eventId, metadata: {...?extraMetadata}),
    ]);
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

class _NoShortcuts extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];
}

Future<_Favorites> _pump(
  WidgetTester tester, {
  List<FavoriteEvent> favorites = const [],
}) async {
  final store = _Favorites(favorites);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        favoriteEventsProvider.overrideWith(() => store),
        notificationPreferencesProvider.overrideWith(_Prefs.new),
        spaceShortcutsProvider.overrideWith(_NoShortcuts.new),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return const Scaffold(
              body: Padding(
                padding: EdgeInsets.all(16),
                child: CollectionCard(collection: _collection),
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

/// The star's own semantics node, by the label that says which way it goes.
Finder _labelled(String label) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == label,
);

final _star = _labelled('Star Candidates 2026');
final _unstar = _labelled('Unstar Candidates 2026');
final _question = find.text('Turn on notifications?');

void main() {
  testWidgets('starring a collection asks about new games; a yes is written '
      'onto its row', (tester) async {
    final store = await _pump(tester);

    await tester.tap(_star);
    await _settle(tester);

    expect(store.added, ['collection:candidates-2026']);
    expect(_question, findsOneWidget);
    expect(
      find.text('Get an alert when new games are added to Candidates 2026.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Turn on'));
    await _settle(tester);

    final (patchedId, patch) = store.patches.single;
    expect(patchedId, 'collection:candidates-2026');
    expect(patch, {kStarNotificationsKey: true});
    expect(tester.takeException(), isNull);
  });

  testWidgets('a starred event of the same name is not the collection\'s '
      'star: starring the collection leaves it alone', (tester) async {
    final store = await _pump(tester, favorites: [_row('candidates_2026')]);

    // The event's star does not fill the collection's.
    expect(_star, findsOneWidget);
    expect(_unstar, findsNothing);

    await tester.tap(_star);
    await _settle(tester);
    await tester.tap(find.text('Not now'));
    await _settle(tester);

    expect(store.added, ['collection:candidates-2026']);
    expect(store.removed, isEmpty);
    expect(_unstar, findsOneWidget);
    // "Not now" is written down: a collection star with no answer notifies.
    final (patchedId, patch) = store.patches.single;
    expect(patchedId, 'collection:candidates-2026');
    expect(patch, {kStarNotificationsKey: false});
  });

  test('a collection star notifies unless its owner said no; a smart event '
      'star only after a yes (Trello #1225)', () {
    // Starred before the question, on the desktop app or an older build.
    expect(
      starNotificationsEnabled(_row('collection:candidates-2026')),
      isTrue,
    );
    expect(
      starNotificationsEnabled(
        _row('legacy-id', metadata: {'kind': 'collection', 'slug': 'x'}),
      ),
      isTrue,
    );
    expect(
      starNotificationsEnabled(
        _row(
          'collection:candidates-2026',
          metadata: {kStarNotificationsKey: false},
        ),
      ),
      isFalse,
    );
    expect(
      starNotificationsEnabled(_row('smart_event:v2:minElo=2700')),
      isFalse,
    );
    expect(
      starNotificationsEnabled(
        _row(
          'smart_event:v2:minElo=2700',
          metadata: {kStarNotificationsKey: true},
        ),
      ),
      isTrue,
    );
  });

  testWidgets('unstarring a collection removes its own row and asks nothing', (
    tester,
  ) async {
    final store = await _pump(
      tester,
      favorites: [
        _row('candidates_2026'),
        _row('collection:candidates-2026', metadata: {'kind': 'collection'}),
      ],
    );

    await tester.tap(_unstar);
    await _settle(tester);

    expect(store.removed, ['collection:candidates-2026']);
    expect(store.added, isEmpty);
    expect(_question, findsNothing);
  });
}
