import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:chessever2/providers/game_video_sources_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/chessboard/video/game_analysis_sources.dart';
import 'package:chessever2/screens/chessboard/video/video_session.dart';
import 'package:chessever2/screens/chessboard/video/video_widgets.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/collections/open_collection_game.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'event_video_widgets_test.dart' show FakePlayer;

const _url = 'https://youtu.be/abcdefghijk?t=120&end=180';
const _pgn = '[White "White"]\n[Black "Black"]\n[Result "1-0"]\n\n1. e4 e5 1-0';
CollectionGameCard _card({String? url = _url, String? author = 'Coach One'}) =>
    CollectionGameCard.fromJson({
      'id': 'g1',
      'pgn': _pgn,
      'videoUrl': url,
      'annotator': author,
    });

class _Repository extends CollectionsRepository {
  _Repository()
    : super(
        GamebaseRepository(
          Dio(),
          baseUrl: 'https://example.invalid',
          apiKey: 'unused',
        ),
      );
  bool allowed = true;
  int playableReads = 0;
  @override
  Future<Collection> fetchCollection(String slug) async => Collection(
    id: 'c1',
    slug: slug,
    kind: CollectionKind.book,
    title: 'Book',
    access: CollectionAccess.premium,
    contentLocked: true,
  );
  @override
  Future<List<CollectionGame>> fetchPlayableGames(String slug) async {
    playableReads++;
    if (!allowed) throw StateError('Denied by server');
    return [CollectionGame.fromCard(_card())!];
  }
}

class _Api implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({
        'status': 'success',
        'data': options.path.endsWith('/games')
            ? {
                'items': [
                  {'id': 'g1', 'pgn': _pgn, 'videoUrl': _url},
                ],
                'total': 1,
                'limit': 200,
                'offset': 0,
              }
            : {
                'id': 'c1',
                'slug': 'book',
                'kind': 'book',
                'access': 'premium',
                'contentLocked': false,
              },
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

// Let entrance/exit frames complete without pumpAndSettle draining the snack's
// animated five-second lifetime before we can press Retry.
Future<void> _pumpNotice(WidgetTester tester) async {
  for (var frame = 0; frame < 8; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  test(
    'real repository separates preview and gated playable hydration',
    () async {
      final api = _Api();
      final repo = CollectionsRepository(
        GamebaseRepository(
          Dio()..httpClientAdapter = api,
          baseUrl: 'https://example.invalid',
          apiKey: 'test',
        ),
        accessToken: () => null,
      );
      final previews = await repo.fetchGames('book');
      expect(previews.single.card.videoUrl, isNull);
      expect(previews.single.game.collectionVideoStreams, isEmpty);
      expect(api.requests.single.queryParameters['include'], isNull);
      final games = await resolvePlayableCollectionGames(
        repository: repo,
        slug: 'book',
        visibleIds: ['g1'],
        requestAccess: (_) async => false,
        stillCurrent: () => true,
      );
      expect(api.requests.last.queryParameters['include'], 'pgn');
      expect(games!.single.collectionVideoStreams.single.isAnalysis, isTrue);
      expect(games.single.pgn, _pgn);
    },
  );
  test(
    'authorized hydration preserves segment, analysis kind and exact PGN through copyWith',
    () {
      final game = CollectionGame.fromCard(_card())!.game;
      final video = game.copyWith(boardNr: 2).collectionVideoStreams.single;
      expect(video.isAnalysis, isTrue);
      expect(video.authorName, 'Coach One');
      expect(video.authorId, isNull);
      expect(video.authorAvatarUrl, isNull);
      expect(video.source.url.queryParameters['start'], '120');
      expect(video.source.url.queryParameters['end'], '180');
      expect(game.pgn, _pgn);
      expect(() => game.collectionVideoStreams.clear(), throwsUnsupportedError);
    },
  );

  test('optional authors are not invented or required for analysis', () {
    for (final author in [null, '', '  ']) {
      final video = CollectionGame.fromCard(
        _card(author: author),
      )!.game.collectionVideoStreams.single;
      expect(video.authorName, isNull);
      expect(video.label, 'Video analysis');
      expect(video.isAnalysis, isTrue);
      expect(video.withRanking(video).isAnalysis, isTrue);
    }
    final longAuthor = List.filled(110, 'A').join();
    final video = CollectionGame.fromCard(
      _card(author: longAuthor),
    )!.game.collectionVideoStreams.single;
    expect(video.authorName, longAuthor);
    expect(video.label, hasLength(100));
  });

  test(
    'preview never carries a protected attachment, even with PGN in input',
    () {
      final preview = CollectionGame.fromPreviewCard(_card())!;
      expect(preview.card.videoUrl, isNull);
      expect(preview.card.pgn, isNull);
      expect(preview.game.pgn, isNull);
      expect(preview.game.collectionVideoStreams, isEmpty);
      expect(_card().withoutPgn().videoUrl, isNull);
      expect(CollectionGame.fromCard(_card().withoutPgn()), isNull);
      expect(
        hydrateCollectionGameCard(
          _card().withoutPgn(),
          collectionGameModel('g1', _pgn),
        ).collectionVideoStreams,
        isEmpty,
      );
    },
  );

  test('old/null and malformed attachment APIs remain playable', () {
    for (final url in [
      null,
      '',
      'https://evil.example/video',
      'https://youtu.be/abcdefghijk?t=live',
      'https://twitch.tv/coach',
      'https://kick.com/coach',
      'http://youtu.be/abcdefghijk',
      'https://user@youtu.be/abcdefghijk',
    ]) {
      final game = CollectionGame.fromCard(_card(url: url))!.game;
      expect(game.collectionVideoStreams, isEmpty);
      expect(game.pgn, _pgn);
    }
  });

  test(
    'open route only returns authorized attachments and honors access rejection',
    () async {
      final repo = _Repository();
      Future<List<dynamic>?> resolve(bool approve) =>
          resolvePlayableCollectionGames(
            repository: repo,
            slug: 'book',
            visibleIds: ['g1'],
            requestAccess: (_) async => approve,
            stillCurrent: () => true,
          );
      expect(await resolve(false), isNull);
      expect(repo.playableReads, 0);
      final games = await resolve(true);
      expect(games!.single.collectionVideoStreams, hasLength(1));
      repo.allowed = false;
      await expectLater(resolve(true), throwsStateError);
    },
  );

  test(
    'lookup loading/error cannot hide an attachment; success merges and dedupes normalized segment',
    () {
      final game = CollectionGame.fromCard(_card())!.game;
      expect(gameAnalysisStreams(game, const AsyncLoading()), hasLength(1));
      expect(
        gameAnalysisStreams(
          game,
          AsyncError(StateError('lookup'), StackTrace.current),
        ),
        hasLength(1),
      );
      final streams = gameAnalysisStreams(
        game,
        const AsyncData([
          {
            'id': 'remote-one',
            'kind': 'analysis',
            'authorName': 'Coach One',
            'authorAvatarUrl': 'https://example.invalid/avatar.webp',
            'label': 'Coach One',
            'url':
                'https://www.youtube.com/watch?v=abcdefghijk&start=120&end=180',
          },
          {
            'id': 'remote-two',
            'kind': 'analysis',
            'authorName': 'Coach Two',
            'label': 'Coach Two',
            'url': _url,
          },
          {
            'id': 'remote-extra',
            'kind': 'analysis',
            'authorName': 'Coach One',
            'label': 'Coach One',
            'url': 'https://youtu.be/abcdefghijk?t=300',
          },
        ]),
      );
      expect(streams, hasLength(3));
      expect(
        streams.first.authorAvatarUrl,
        'https://example.invalid/avatar.webp',
      );
      expect(streams.map((s) => s.id), isNot(contains('collection-video')));
      expect(gameAnalysisStreams(game, const AsyncData([])), hasLength(1));
    },
  );

  testWidgets(
    'hydrated attachment reaches video host/selector without an author',
    (tester) async {
      final game = CollectionGame.fromCard(_card(author: null))!.game;
      final session = EventVideoSession(repository: null);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: EventVideoHost(
              gameId: game.gameId,
              tourId: '',
              roundId: '',
              completed: true,
              analysisStreams: gameAnalysisStreams(game, const AsyncLoading()),
              session: session,
              player: FakePlayer(),
              child: const Scaffold(body: EventVideoFlags()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(session.hasVideo, isTrue);
      expect(session.selected!.isAnalysis, isTrue);
      final tile = find.byKey(const ValueKey('video_stream_collection-video'));
      expect(tile, findsOneWidget);
      await tester.tap(tile);
      await tester.pump();
      expect(session.playRequested, isTrue);
      expect(session.selected!.source.url.queryParameters['start'], '120');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('an expired failure notice does not replay on board rebuilds', (
    tester,
  ) async {
    const lookup = (gameId: 'rebuild', pgn: _pgn);
    var calls = 0;
    final overrides = [
      gameVideoSourcesProvider(lookup).overrideWith((ref) async {
        calls++;
        throw StateError('private failure');
      }),
    ];
    Widget harness() => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        builder: (context, child) {
          ResponsiveHelper.init(context);
          return child!;
        },
        home: const Scaffold(
          body: Stack(
            children: [
              SizedBox.expand(key: ValueKey('board')),
              GameVideoDiscoveryNotice(lookup: lookup),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(harness());
    final size = tester.getSize(find.byKey(const ValueKey('board')));
    await _pumpNotice(tester);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('board'))), size);
    await tester.pump(const Duration(seconds: 6));
    await _pumpNotice(tester);
    expect(find.text('Retry'), findsNothing);
    await tester.pumpWidget(harness());
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Retry'), findsNothing);
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  for (final cached in [false, true]) {
    testWidgets(
      'discovery failure cached=$cached retries each attempt without duplicate notices',
      (tester) async {
        const lookup = (gameId: 'g1', pgn: _pgn);
        var calls = 0;
        var pending = Completer<List<Map<String, dynamic>>>();
        final game = CollectionGame.fromCard(_card())!.game;
        final container = ProviderContainer(
          overrides: [
            gameVideoSourcesProvider(lookup).overrideWith((ref) {
              calls++;
              return pending.future;
            }),
          ],
        );
        final subscription = container.listen(
          gameVideoSourcesProvider(lookup),
          (_, _) {},
        );
        if (cached) {
          pending.completeError(StateError('private lookup details'));
          try {
            await container.read(gameVideoSourcesProvider(lookup).future);
          } catch (_) {}
        }
        Widget harness() => UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            builder: (context, child) {
              ResponsiveHelper.init(context);
              return child!;
            },
            home: Scaffold(
              bottomNavigationBar: const GameVideoDiscoveryNotice(
                lookup: lookup,
              ),
              body: Consumer(
                builder: (context, ref, _) {
                  final sources = ref.watch(gameVideoSourcesProvider(lookup));
                  return Column(
                    children: [
                      const Text('Board usable'),
                      Text(
                        'Videos: ${gameAnalysisStreams(game, sources).length}',
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpWidget(harness());
        expect(find.text('Videos: 1'), findsOneWidget);
        if (!cached) {
          pending.completeError(StateError('private lookup details'));
        }
        await _pumpNotice(tester);
        expect(find.text('Board usable'), findsOneWidget);
        expect(find.text('Videos: 1'), findsOneWidget);
        expect(
          find.textContaining("Couldn't look up additional game videos"),
          findsOneWidget,
        );
        expect(find.textContaining('private lookup details'), findsNothing);
        expect(find.byType(SnackBar), findsOneWidget);
        await tester.pumpWidget(harness());
        await _pumpNotice(tester);
        expect(calls, 1);
        pending = Completer<List<Map<String, dynamic>>>();
        await tester.tap(find.text('Retry'));
        await tester.pump();
        expect(calls, 2);
        expect(find.text('Videos: 1'), findsOneWidget);
        pending.completeError(StateError('second private failure'));
        await _pumpNotice(tester);
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('Videos: 1'), findsOneWidget);
        pending = Completer<List<Map<String, dynamic>>>();
        await tester.tap(find.text('Retry'));
        await tester.pump();
        expect(calls, 3);
        pending.complete([]);
        await _pumpNotice(tester);
        expect(find.text('Retry'), findsNothing);
        expect(find.text('Videos: 1'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        subscription.close();
        container.dispose();
        await tester.pump(const Duration(milliseconds: 1));
      },
    );
  }
}
