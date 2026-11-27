import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/screens/feed/providers/board_feed_client.dart';
import 'package:chessever2/screens/feed/providers/feed_entries_provider.dart';
import 'package:chessever2/screens/feed/providers/feed_provider.dart';
import 'package:chessever2/screens/streaks/models/streak_models.dart';
import 'package:chessever2/screens/streaks/providers/streak_providers.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/story_parity_harness.dart' show DefaultBoard;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer fixture({AppUser? viewer, _Server? server}) {
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWithValue(viewer),
        boardFeedClientProvider.overrideWithValue(server),
        boardSettingsProviderNew.overrideWith(DefaultBoard.new),
        countryDropdownProvider.overrideWith((ref) => _NoCountry()),
        streakWallProvider.overrideWith(_NoStreaks.new),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  AppUser signedIn() => AppUser(id: 'viewer', createdAt: DateTime.utc(2026));

  test('an unauthenticated viewer gets the sign-in state', () async {
    final container = fixture();
    await expectLater(
      container.read(feedProvider.future),
      throwsA(isA<BoardFeedSignInRequired>()),
    );
    expect(container.read(feedEntriesProvider), isEmpty);
  });

  test(
    'a backend 404 reaches the first-page error without a local draw',
    () async {
      final server = _Server()..fail = true;
      addTearDown(server.auth.dispose);
      final container = fixture(viewer: signedIn(), server: server);
      await expectLater(
        container.read(feedProvider.future),
        throwsA(
          isA<BoardFeedUnavailable>().having((e) => e.status, 'status', 404),
        ),
      );
      expect(container.read(feedEntriesProvider), isEmpty);
      expect(server.starts, 1);
    },
  );

  test(
    'refresh and pagination use backend order and keep the current page on error',
    () async {
      final server = _Server();
      addTearDown(server.auth.dispose);
      final container = fixture(viewer: signedIn(), server: server);
      List<String> keys() => [
        for (final entry in container.read(feedEntriesProvider)) entry.key,
      ];
      await container.read(feedProvider.future);
      final feed = container.read(feedProvider.notifier);
      expect(keys(), ['youtube:ShortTest01', 'collection:study']);

      await feed.loadMore();
      expect(keys(), [
        'youtube:ShortTest01',
        'collection:study',
        'youtube:ShortTest02',
      ]);
      expect(server.cursors, ['next']);
      expect(feed.more, FeedMore.exhausted);

      server.fail = true;
      await expectLater(feed.refresh(), throwsA(isA<BoardFeedUnavailable>()));
      expect(keys(), [
        'youtube:ShortTest01',
        'collection:study',
        'youtube:ShortTest02',
      ]);

      server.fail = false;
      await feed.refresh();
      expect(keys(), ['youtube:ShortTest01', 'collection:study']);
      expect(server.starts, 3);
    },
  );
}

class _Server extends BoardFeedClient {
  _Server()
    : super(
        Uri.parse('https://feed.example.com'),
        'viewer',
        GoTrueClient(url: 'https://auth.example.com', autoRefreshToken: false),
      );

  int starts = 0;
  bool fail = false;
  final cursors = <String>[];

  @override
  Future<BoardFeedPage> start(
    String requestId, {
    String? country,
    List<String> languages = const [],
  }) async {
    starts++;
    if (fail) throw const BoardFeedUnavailable(404);
    return BoardFeedPage({
      'sessionId': requestId,
      'pageId': 'first',
      'nextCursor': 'next',
      'items': [
        {
          'type': 'short',
          'id': 'ShortTest01',
          'title': 'First Short',
          'channelName': 'Example',
        },
        {
          'type': 'collection',
          'id': 'study',
          'slug': 'study',
          'title': 'Study',
          'kind': 'book',
        },
      ],
    });
  }

  @override
  Future<BoardFeedPage> next(String cursor) async {
    cursors.add(cursor);
    return BoardFeedPage({
      'sessionId': 'session',
      'pageId': 'second',
      'items': [
        {
          'type': 'short',
          'id': 'ShortTest02',
          'title': 'Second Short',
          'channelName': 'Example',
        },
      ],
    });
  }
}

class _NoCountry extends StateNotifier<AsyncValue<Country>>
    implements SelectedCountryNotifier {
  _NoCountry() : super(const AsyncLoading());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoStreaks extends StreakWallNotifier {
  @override
  Future<List<StreakRow>> build() async => const [];
}
