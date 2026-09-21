import 'dart:async';

import 'package:chessever2/providers/event_video_provider.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/screens/chessboard/video/video_metadata_cache.dart';
import 'package:chessever2/screens/chessboard/video/video_repository.dart';
import 'package:chessever2/screens/chessboard/video/video_session.dart';
import 'package:chessever2/screens/chessboard/video/video_stream.dart';
import 'package:chessever2/screens/chessboard/video/video_widgets.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'event_video_test.dart' show FakeVideoRepository, fixtureVideos;
import 'event_video_widgets_test.dart' show FakePlayer;

class ControlledVideoRepository implements EventVideoRepository {
  final requests = <EventVideoKey>[];
  final responses = <Completer<ResolvedEventVideos>>[];
  bool closed = false;

  @override
  Future<ResolvedEventVideos> fetch({
    required String tourId,
    required String roundId,
  }) {
    requests.add(EventVideoKey(tourId: tourId, roundId: roundId));
    final response = Completer<ResolvedEventVideos>();
    responses.add(response);
    return response.future;
  }

  void complete(int index, [ResolvedEventVideos? value]) =>
      responses[index].complete(value ?? ResolvedEventVideos(fixtureVideos()));

  @override
  void close() => closed = true;
}

void main() {
  test(
    'cached web-only streams never expose the mobile video action',
    () async {
      final repository = FakeVideoRepository(
        EventVideoStream.readList([
          {
            'id': 'web-stream',
            'label': 'Web only',
            'url': 'https://youtu.be/abcdefghijk',
            'platforms': ['web'],
          },
        ]),
      );
      final cache = EventVideoMetadataCache(repository);
      addTearDown(cache.dispose);
      await cache.fetch(tourId: 'tour', roundId: 'round');
      final session = EventVideoSession(repository: cache);
      addTearDown(session.dispose);
      session.openGame(gameId: 'game', tourId: 'tour', roundId: 'round');
      expect(session.hasVideo, isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(session.hasVideo, isFalse);
    },
  );

  test('live-round and board requests share one in-flight response', () async {
    final repository = ControlledVideoRepository();
    final cache = EventVideoMetadataCache(repository);
    addTearDown(cache.dispose);
    cache.setLiveRounds(['r1', 'r1']);
    final board = cache.fetch(tourId: 'tour', roundId: 'r1');
    expect(repository.requests, [const EventVideoKey(roundId: 'r1')]);
    repository.complete(0);
    await board;
    expect(
      cache.peek(const EventVideoKey(tourId: 'tour', roundId: 'r1'))!.streams,
      isNotEmpty,
    );
    await cache.fetch(tourId: 'tour', roundId: 'r1');
    expect(repository.requests, hasLength(1));
  });

  test(
    'round results never bleed into sibling rounds or tour fallback',
    () async {
      final repository = FakeVideoRepository(fixtureVideos());
      final cache = EventVideoMetadataCache(repository);
      addTearDown(cache.dispose);
      await cache.fetch(tourId: 'tour', roundId: '');
      expect(
        cache.peek(const EventVideoKey(tourId: 'tour', roundId: 'r1')),
        isNull,
      );
      repository.streams = [];
      await cache.fetch(tourId: 'tour', roundId: 'r1');
      expect(
        cache.peek(const EventVideoKey(tourId: 'tour'))!.streams,
        isNotEmpty,
      );
      expect(
        cache.peek(const EventVideoKey(tourId: 'tour', roundId: 'r1'))!.streams,
        isEmpty,
      );
      expect(
        cache.peek(const EventVideoKey(tourId: 'tour', roundId: 'r2')),
        isNull,
      );
      await cache.fetch(tourId: 'tour', roundId: 'r1');
      expect(
        repository.requests,
        2,
        reason: 'An empty response is also cached',
      );
    },
  );

  test(
    'a reopened board uses cached streams synchronously and does not own the cache',
    () async {
      final repository = ControlledVideoRepository();
      final cache = EventVideoMetadataCache(repository);
      addTearDown(cache.dispose);
      final preload = cache.fetch(tourId: 'tour', roundId: 'r1');
      repository.complete(0);
      await preload;

      for (var i = 0; i < 2; i++) {
        final session = EventVideoSession(repository: cache, visible: false);
        session.openGame(gameId: 'g$i', tourId: 'tour', roundId: 'r1');
        // Deliberately do not yield to a microtask or pump a second frame.
        expect(session.hasVideo, isTrue);
        expect(session.visible, isFalse);
        expect(session.selected!.id, 'english-main');
        session.dispose();
        expect(repository.closed, isFalse);
      }
      expect(repository.requests, hasLength(1));
    },
  );

  test(
    'stale streams paint immediately while one background refresh runs',
    () async {
      var now = DateTime(2026);
      final repository = ControlledVideoRepository();
      final cache = EventVideoMetadataCache(repository, now: () => now);
      addTearDown(cache.dispose);
      final preload = cache.fetch(tourId: 'tour', roundId: 'r1');
      repository.complete(0);
      await preload;
      now = now.add(const Duration(seconds: 31));
      final session = EventVideoSession(repository: cache);
      addTearDown(session.dispose);
      session.openGame(gameId: 'g', tourId: 'tour', roundId: 'r1');
      expect(session.hasVideo, isTrue);
      expect(repository.requests, hasLength(2));
      repository.complete(1);
      await session.refresh();
    },
  );

  test(
    'transient failures retain URLs, permanent failures clear shared availability',
    () async {
      var now = DateTime(2026);
      final repository = FakeVideoRepository(fixtureVideos());
      final cache = EventVideoMetadataCache(repository, now: () => now);
      addTearDown(cache.dispose);
      await cache.fetch(tourId: 'tour', roundId: 'r1');
      final session = EventVideoSession(repository: cache);
      addTearDown(session.dispose);
      session.openGame(gameId: 'g', tourId: 'tour', roundId: 'r1');
      await Future<void>.delayed(Duration.zero);
      now = now.add(const Duration(seconds: 31));
      repository.error = const VideoMetadataException(false);
      await expectLater(
        cache.fetch(tourId: 'tour', roundId: 'r1'),
        throwsA(isA<VideoMetadataException>()),
      );
      expect(session.hasVideo, isTrue);
      expect(
        cache.peek(const EventVideoKey(roundId: 'r1'))!.streams,
        isNotEmpty,
      );
      now = now.add(const Duration(seconds: 31));
      repository.error = const VideoMetadataException(true);
      await expectLater(
        cache.fetch(tourId: 'tour', roundId: 'r1'),
        throwsA(isA<VideoMetadataException>()),
      );
      expect(session.hasVideo, isFalse);
      expect(cache.peek(const EventVideoKey(roundId: 'r1'))!.streams, isEmpty);
    },
  );

  test('limits concurrent requests and prioritizes visible rounds', () async {
    final repository = ControlledVideoRepository();
    final cache = EventVideoMetadataCache(repository, maxConcurrentRequests: 2);
    addTearDown(cache.dispose);
    cache.setLiveRounds(['r1', 'r2', 'r3', 'r4', 'r5']);
    final visible = cache.fetch(tourId: 'tour', roundId: 'r5');
    expect(repository.requests, hasLength(2));
    repository.complete(0);
    await Future<void>.delayed(Duration.zero);
    expect(repository.requests.last.roundId, 'r5');
    repository.complete(2);
    await visible;
    expect(repository.requests, hasLength(4));
  });

  test(
    'foreground refresh uses active scopes; released scopes remain cached',
    () async {
      var now = DateTime(2026);
      final repository = FakeVideoRepository(fixtureVideos());
      final cache = EventVideoMetadataCache(repository, now: () => now);
      addTearDown(cache.dispose);
      final release = cache.retain(
        const EventVideoKey(tourId: 'tour', roundId: 'r1'),
      );
      await cache.fetch(tourId: 'tour', roundId: 'r1');
      cache.setForeground(false);
      now = now.add(const Duration(seconds: 31));
      cache.refreshWatched();
      expect(repository.requests, 1);
      cache.setForeground(true);
      await Future<void>.delayed(Duration.zero);
      expect(repository.requests, 2);
      release();
      now = now.add(const Duration(seconds: 31));
      cache.refreshWatched();
      expect(repository.requests, 2);
      expect(cache.peek(const EventVideoKey(roundId: 'r1')), isNotNull);
    },
  );

  test('idle cache is bounded without evicting a mounted scope', () async {
    final repository = FakeVideoRepository(fixtureVideos());
    final cache = EventVideoMetadataCache(repository, maxEntries: 2);
    addTearDown(cache.dispose);
    final release = cache.retain(
      const EventVideoKey(tourId: 'tour', roundId: 'r1'),
    );
    addTearDown(release);
    await cache.fetch(tourId: 'tour', roundId: 'r1');
    await cache.fetch(tourId: 'tour', roundId: 'r2');
    await cache.fetch(tourId: 'tour', roundId: 'r3');
    expect(cache.peek(const EventVideoKey(roundId: 'r1')), isNotNull);
    expect(cache.peek(const EventVideoKey(roundId: 'r2')), isNull);
    expect(cache.peek(const EventVideoKey(roundId: 'r3')), isNotNull);
  });

  testWidgets('root provider warms metadata before a real host first builds', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'ce-video-visible.v1': false,
      'ce-video-country.v1': 'ES',
    });
    await tester.runAsync(SharedPreferencesService.instance.initialize);
    final repository = ControlledVideoRepository();
    final cache = EventVideoMetadataCache(repository);
    final container = ProviderContainer(
      overrides: [
        eventVideoMetadataProvider.overrideWith((ref) => cache),
        liveRoundsIdProvider.overrideWith((ref) => Stream.value(['r1'])),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (_, ref, _) {
            ref.watch(eventVideoPreloadProvider);
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pump();
    expect(repository.requests, hasLength(1));
    repository.complete(0);
    await tester.pump();
    final frames = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: EventVideoHost(
          gameId: 'g',
          tourId: 'tour',
          roundId: 'r1',
          metadata: container.read(eventVideoMetadataProvider.notifier),
          player: FakePlayer(),
          child: Builder(
            builder: (context) {
              final layout = EventVideoLayoutScope.maybeOf(context)!;
              frames.add(layout.hasVideo);
              expect(layout.visible, isFalse);
              expect(
                EventVideoScope.sessionOf(context)!.selected!.id,
                'spanish',
              );
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(frames.first, isTrue);
    expect(frames, everyElement(isTrue));
    expect(repository.requests, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    expect(repository.closed, isFalse);
    container.dispose();
    expect(repository.closed, isTrue);
  });

  testWidgets(
    'missing test configuration does not subscribe to backend round discovery',
    (tester) async {
      var subscribed = false;
      final container = ProviderContainer(
        overrides: [
          eventVideoConfigurationProvider.overrideWithValue(null),
          liveRoundsIdProvider.overrideWith((ref) {
            subscribed = true;
            return Stream.value(['r1']);
          }),
        ],
      );
      addTearDown(container.dispose);
      container.read(eventVideoPreloadProvider);
      expect(container.read(eventVideoMetadataProvider).enabled, isFalse);
      expect(subscribed, isFalse);
    },
  );
}
