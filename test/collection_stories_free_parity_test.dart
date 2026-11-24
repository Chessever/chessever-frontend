// Guests, free and Premium readers watch the same Today stories (owner +
// PM, 2026-11-23): the same games, positions, moves, words, arrows and
// evaluations, for a book, an event and Missed chances. Premium is asked
// for only when a story opens its game, its collection or its event, with
// the chooser (Upgrade / Watch ad) a collection's own game opens with; a
// reward or a purchase (a guest signs in first) lets the open go on, a
// subscriber opens directly.
import 'dart:convert';
import 'dart:typed_data';

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/collections/collections_screen.dart'
    show CollectionCoverPlate;
import 'package:chessever2/screens/stories/story_models.dart';
import 'package:chessever2/screens/stories/story_pages.dart';
import 'package:chessever2/screens/stories/story_row.dart';
import 'package:chessever2/screens/stories/story_row_prefs.dart';
import 'package:chessever2/screens/stories/story_seen_store.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'support/story_parity_harness.dart';

void main() {
  group('the same stories', () {
    test('a Premium book: a guest, a free and a Premium reader get one '
        'batch, read from the server\'s story games', () async {
      Future<(StoryBatch, StoryServer)> read(Tier tier) async {
        final opens = Opens(tier);
        late final ProviderContainer container;
        final server = StoryServer(
          entitled: () => container.read(premiumAccessProvider),
          collection: book,
        );
        container = ProviderContainer(
          overrides: [
            ...readerOverrides(
              tier: tier,
              collection: book,
              server: server,
              opens: opens,
            ),
            storyClockProvider.overrideWithValue(() => now),
            storySeenStorageProvider.overrideWithValue(MemoryStorySeen()),
          ],
        );
        addTearDown(container.dispose);
        container.read(opens.granted.notifier).state = tier == Tier.premium;
        final sub = container.listen(storyBatchProvider(book.slug), (_, _) {});
        addTearDown(sub.close);
        return (
          await container.read(storyBatchProvider(book.slug).future),
          server,
        );
      }

      final reads = {for (final tier in Tier.values) tier: await read(tier)};
      String describe(StoryBatch batch) => [
        for (final f in batch.frames)
          [
            f.id,
            f.position.fenAfter,
            f.position.san,
            f.position.label,
            f.position.comment,
            f.position.shapes.length,
            f.position.evalAfter,
            f.position.puzzle?.answerSan,
          ].join(' | '),
      ].join('\n');
      final (premium, _) = reads[Tier.premium]!;
      for (final tier in [Tier.guest, Tier.free]) {
        final (batch, _) = reads[tier]!;
        expect(describe(batch), describe(premium), reason: tier.name);
        expect(batch.total, premium.total, reason: tier.name);
        expect(batch.gameCount, premium.gameCount, reason: tier.name);
      }
      // The screenshot's story: three positions with the book's words,
      // never one still frame.
      final (guest, _) = reads[Tier.guest]!;
      expect(guest.games.first.id, 'latest');
      expect(guest.games.first.segments, hasLength(kStoryMaxSegments));
      expect(guest.games.first.segments.any((s) => s.comment != null), isTrue);
      // Every reader reads the server's picks for their day, never the full
      // games.
      for (final MapEntry(key: tier, value: (_, server)) in reads.entries) {
        expect(server.storyReads, [
          '${book.slug}@2026-11-23',
        ], reason: tier.name);
        expect(server.pgnReads, isEmpty, reason: tier.name);
      }
    });

    for (final light in [false, true]) {
      final theme = light ? 'light' : 'dark';
      testWidgets('a Premium book draws page for page the same for a guest, '
          'a free and a Premium reader, $theme', (tester) async {
        final guest = await watch(tester, Tier.guest, book, light: light);
        final free = await watch(tester, Tier.free, book, light: light);
        final premium = await watch(tester, Tier.premium, book, light: light);
        expect(free, isNotEmpty);
        expect(guest, premium);
        expect(free, premium);
        expect(free.first['bars'], greaterThan(1));
        expect(
          guest.map((p) => p['comment']).whereType<String>(),
          isNotEmpty,
          reason: 'the book\'s words are on a guest\'s story too',
        );
      });
    }

    for (final event in [freeEvent, premiumEvent]) {
      testWidgets('an event collection draws page for page the same '
          '(${event.access.name})', (tester) async {
        final guest = await watch(tester, Tier.guest, event);
        final free = await watch(tester, Tier.free, event);
        final premium = await watch(tester, Tier.premium, event);
        expect(free, isNotEmpty);
        expect(guest, premium);
        expect(free, premium);
      });
    }

    testWidgets('Missed chances draws page for page the same', (tester) async {
      final missed = missedChancesCollection(now);
      final guest = await watch(tester, Tier.guest, missed);
      final free = await watch(tester, Tier.free, missed);
      final premium = await watch(tester, Tier.premium, missed);
      expect(free, isNotEmpty);
      expect(guest, premium);
      expect(free, premium);
      expect(free.any((p) => p['puzzle'] != null), isTrue);
    });
  });

  group('opening asks for Premium', () {
    testWidgets('View collection: a free reader meets the chooser; Not now '
        'opens nothing and the story plays on', (tester) async {
      final (_, _, opens) = await pumpStories(
        tester,
        tier: Tier.free,
        collection: book,
      );
      await tapAction(tester, 'story_view_collection');
      expect(opens.chooserShown, 1);
      expect(find.byKey(const ValueKey('collection_page')), findsNothing);
      expect(find.byType(StoryFrameView), findsOneWidget);
    });

    testWidgets('View collection: after a watched ad the collection opens', (
      tester,
    ) async {
      final (_, _, opens) = await pumpStories(
        tester,
        tier: Tier.free,
        collection: book,
      );
      opens.rewardWatched = true;
      await tapAction(tester, 'story_view_collection');
      expect(opens.chooserShown, 1);
      expect(find.byKey(const ValueKey('collection_page')), findsOneWidget);
    });

    testWidgets('the header opens the collection behind the same gate', (
      tester,
    ) async {
      final (_, _, opens) = await pumpStories(
        tester,
        tier: Tier.free,
        collection: book,
      );
      await tapAction(tester, 'story_header_open');
      expect(opens.chooserShown, 1);
      expect(find.byKey(const ValueKey('collection_page')), findsNothing);
    });

    testWidgets('View collection: a Premium reader opens it directly', (
      tester,
    ) async {
      final (_, _, opens) = await pumpStories(
        tester,
        tier: Tier.premium,
        collection: book,
      );
      await tapAction(tester, 'story_view_collection');
      expect(opens.chooserShown, 0);
      expect(find.byKey(const ValueKey('collection_page')), findsOneWidget);
    });

    testWidgets('Go to event on a Premium event asks a free reader; a free '
        'event opens for everyone', (tester) async {
      var (_, _, opens) = await pumpStories(
        tester,
        tier: Tier.free,
        collection: premiumEvent,
      );
      expect(find.text('Go to event'), findsOneWidget);
      opens.rewardWatched = true;
      await tapAction(tester, 'story_view_collection');
      expect(opens.chooserShown, 1);
      expect(find.byKey(const ValueKey('collection_page')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      (_, _, opens) = await pumpStories(
        tester,
        tier: Tier.free,
        collection: freeEvent,
      );
      await tapAction(tester, 'story_view_collection');
      expect(opens.chooserShown, 0);
      expect(find.byKey(const ValueKey('collection_page')), findsOneWidget);
    });

    testWidgets('Open game: a free reader meets the chooser before any full '
        'game is read; Not now opens nothing', (tester) async {
      final (_, server, opens) = await pumpStories(
        tester,
        tier: Tier.free,
        collection: book,
      );
      await tapAction(tester, 'story_open_game');
      expect(opens.chooserShown, 1);
      expect(server.playableReads, 0);
      expect(opens.boards, isEmpty);
      expect(find.byType(StoryFrameView), findsOneWidget);
    });

    testWidgets('Open game: after a watched ad the game opens at the story\'s '
        'position', (tester) async {
      final (_, server, opens) = await pumpStories(
        tester,
        tier: Tier.free,
        collection: book,
      );
      opens.rewardWatched = true;
      await tapAction(tester, 'story_open_game');
      expect(opens.chooserShown, 1);
      expect(server.playableReads, 1);
      expect(opens.boards, hasLength(1));
      final (ids, index, moves) = opens.boards.single;
      expect(ids[index], 'latest');
      expect(moves.keys.single, 'latest');
      expect(moves['latest'], greaterThan(0));
    });

    testWidgets('Open game: a Premium reader opens directly', (tester) async {
      final (_, server, opens) = await pumpStories(
        tester,
        tier: Tier.premium,
        collection: book,
      );
      await tapAction(tester, 'story_open_game');
      expect(opens.chooserShown, 0);
      expect(server.playableReads, 1);
      expect(opens.boards, hasLength(1));
    });

    testWidgets('one chooser per open: after a watched ad on Open game, View '
        'collection opens without asking again', (tester) async {
      final (_, server, opens) = await pumpStories(
        tester,
        tier: Tier.free,
        collection: book,
      );
      opens.rewardWatched = true;
      await tapAction(tester, 'story_open_game');
      expect(opens.chooserShown, 1);
      expect(opens.boards, hasLength(1));
      await tapAction(tester, 'story_view_collection');
      expect(opens.chooserShown, 1);
      expect(find.byKey(const ValueKey('collection_page')), findsOneWidget);
      expect(server.playableReads, 1);
    });
  });

  group('a guest opening from a story', () {
    testWidgets('View collection and the header meet the same chooser; Not '
        'now opens nothing and the story plays on', (tester) async {
      final (_, _, opens) = await pumpStories(
        tester,
        tier: Tier.guest,
        collection: book,
      );
      await tapAction(tester, 'story_view_collection');
      expect(opens.chooserShown, 1);
      await tapAction(tester, 'story_header_open');
      expect(opens.chooserShown, 2);
      expect(find.byKey(const ValueKey('collection_page')), findsNothing);
      expect(find.byType(StoryFrameView), findsOneWidget);
    });

    testWidgets('Open game meets the chooser before any full game is read; '
        'Not now opens nothing', (tester) async {
      final (_, server, opens) = await pumpStories(
        tester,
        tier: Tier.guest,
        collection: book,
      );
      await tapAction(tester, 'story_open_game');
      expect(opens.chooserShown, 1);
      expect(server.playableReads, 0);
      expect(opens.boards, isEmpty);
      expect(find.byType(StoryFrameView), findsOneWidget);
    });

    testWidgets('an ad watched on the guest session opens the game at the '
        'story\'s position, asked once', (tester) async {
      final (_, server, opens) = await pumpStories(
        tester,
        tier: Tier.guest,
        collection: book,
      );
      opens.rewardWatched = true;
      await tapAction(tester, 'story_open_game');
      expect(opens.chooserShown, 1);
      expect(server.playableReads, 1);
      final (ids, index, moves) = opens.boards.single;
      expect(ids[index], 'latest');
      expect(moves['latest'], greaterThan(0));
    });

    testWidgets('Upgrade: signed in (the guest account made permanent) and '
        'subscribed, the game opens, asked once', (tester) async {
      final (container, server, opens) = await pumpStories(
        tester,
        tier: Tier.guest,
        collection: book,
      );
      final guest = container.read(opens.user)!;
      opens.signsInAs = AppUser(
        id: guest.id,
        email: 'guest@example.com',
        createdAt: guest.createdAt,
      );
      await tapAction(tester, 'story_open_game');
      expect(opens.chooserShown, 1);
      expect(container.read(opens.user)!.isAnonymous, isFalse);
      expect(server.playableReads, 1);
      expect(opens.boards, hasLength(1));
    });

    testWidgets('Upgrade into another account: nothing opens for the guest '
        'who asked, no error, and the story plays on', (tester) async {
      final (_, server, opens) = await pumpStories(
        tester,
        tier: Tier.guest,
        collection: book,
      );
      opens.signsInAs = readerOf(Tier.free);
      await tapAction(tester, 'story_open_game');
      expect(opens.chooserShown, 1);
      expect(server.playableReads, 0);
      expect(opens.boards, isEmpty);
      expect(find.textContaining("Couldn't"), findsNothing);
      expect(find.byType(StoryFrameView), findsOneWidget);
    });

    testWidgets('a free collection opens for a guest with no chooser', (
      tester,
    ) async {
      final (_, _, opens) = await pumpStories(
        tester,
        tier: Tier.guest,
        collection: freeEvent,
      );
      await tapAction(tester, 'story_view_collection');
      expect(opens.chooserShown, 0);
      expect(find.byKey(const ValueKey('collection_page')), findsOneWidget);
    });
  });

  group('the circle', () {
    Future<void> pumpCircle(
      WidgetTester tester,
      Collection collection, {
      ImageProvider? cover,
    }) async {
      tester.view.physicalSize = const Size(393, 852) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storyCoverOverrideProvider.overrideWithValue((_) => cover),
            boardSettingsProviderNew.overrideWith(DefaultBoard.new),
          ],
          child: MaterialApp(
            home: Center(
              child: StoryCover(collection: collection, diameter: 64),
            ),
          ),
        ),
      );
      if (cover != null) {
        await tester.runAsync(
          () => precacheImage(cover, tester.element(find.byType(StoryCover))),
        );
      }
      await tester.pump();
      await tester.pump();
    }

    testWidgets('the whole cover stands centred, clear of the rim, on a bed '
        'of its own colours', (tester) async {
      const cover = AssetImage('assets/pngs/hub_library_editorial.webp');
      await pumpCircle(tester, book, cover: cover);
      final circle = tester.getRect(find.byType(StoryCover));
      final whole = tester.getRect(
        find.byKey(const ValueKey('story_cover_whole')),
      );
      expect(whole.center.dx, moreOrLessEquals(circle.center.dx));
      expect(whole.center.dy, moreOrLessEquals(circle.center.dy));
      expect(whole.width, moreOrLessEquals(64 * kStoryCoverShare));
      expect(whole.height, moreOrLessEquals(64 * kStoryCoverShare));
      // A 2:3 cover as tall as that box keeps its corners off the rim.
      final corner = Offset(whole.height / 3, whole.height / 2).distance;
      expect(corner, lessThan(circle.width / 2 - 1.5));
      final picture = tester.widget<RawImage>(
        find.descendant(
          of: find.byKey(const ValueKey('story_cover_whole')),
          matching: find.byType(RawImage),
        ),
      );
      expect(picture.fit, BoxFit.contain);
      final bed = tester.widget<RawImage>(
        find.descendant(
          of: find.byKey(const ValueKey('story_cover_bed')),
          matching: find.byType(RawImage),
        ),
      );
      expect(bed.fit, BoxFit.cover);
    });

    testWidgets('a collection with no cover keeps its pixel plate, whole', (
      tester,
    ) async {
      await pumpCircle(tester, book);
      expect(find.byType(CollectionCoverPlate), findsOneWidget);
      expect(find.byKey(const ValueKey('story_cover_bed')), findsNothing);
    });

    testWidgets('Missed chances\' mark draws its picture at the same share, '
        'the board running on to the rim', (tester) async {
      await pumpCircle(tester, missedChancesCollection(now));
      final mark = tester.widget<CustomPaint>(
        find.byKey(const ValueKey('missed_chances_mark')),
      );
      expect(
        (mark.painter! as MissedChancesMarkPainter).share,
        kStoryCoverShare,
      );
    });
  });

  group('a server from before the stories\' read', () {
    test('keeps the old path: the reader\'s own picks, PGNs where it may read '
        'them', () async {
      final repository = _LegacyServer();
      Future<StoryBatch> read(bool locked) async {
        final container = ProviderContainer(
          overrides: [
            collectionContentsProvider.overrideWith(
              (ref, slug) async => CollectionContents(
                sections: const [],
                games: [
                  for (final card in bookCards)
                    CollectionGame.fromPreviewCard(card)!,
                ],
              ),
            ),
            collectionDetailProvider.overrideWith(
              (ref, slug) async => storyCollection(
                slug,
                kind: CollectionKind.book,
                access: CollectionAccess.premium,
                locked: locked,
              ),
            ),
            collectionsRepositoryProvider.overrideWithValue(repository),
            storyAnalyzerProvider.overrideWithValue(
              (jobs) async => analyzeStoryJobs(jobs),
            ),
            storyClockProvider.overrideWithValue(() => now),
            storySeenStorageProvider.overrideWithValue(MemoryStorySeen()),
          ],
        );
        addTearDown(container.dispose);
        final sub = container.listen(storyBatchProvider('b'), (_, _) {});
        addTearDown(sub.close);
        return container.read(storyBatchProvider('b').future);
      }

      final premium = await read(false);
      expect(premium.games.first.segments, hasLength(kStoryMaxSegments));
      expect(repository.pgnReads, 1);
      // That server keeps a Premium book's moves from a free reader: the
      // latest game's final position until gamebase ships the read.
      final free = await read(true);
      expect(free.games.single.segments.single.isStill, isTrue);
      expect(repository.pgnReads, 1);
    });
  });

  group('the story read on the wire', () {
    // A card as gamebase sends it in the stories' read: the browse read's
    // card with its PGN.
    Map<String, Object?> wire(CollectionGameCard card) => {
      'id': card.id,
      'white': {'name': card.white.name, 'key': card.white.key},
      'black': {'name': card.black.name, 'key': card.black.key},
      'event': card.event,
      'eco': card.eco,
      'opening': card.opening,
      'finalFen': card.finalFen,
      'updatedAt': card.updatedAt?.toUtc().toIso8601String(),
      'hasAnnotations': card.hasAnnotations,
      'commentCount': card.commentCount,
      'pgn': card.pgn,
    };

    CollectionsRepository repositoryOver(_Wire http, String? session) =>
        CollectionsRepository(
          GamebaseRepository(
            Dio()..httpClientAdapter = http,
            baseUrl: 'https://gamebase.test',
            apiKey: 'first-party',
          ),
          accessToken: () => session,
        );

    test('signed out, a guest session, a free reader and a subscriber send '
        'one read and get one answer: the app\'s key and their day, no '
        'account needed', () async {
      final http = _Wire(
        (_) => (
          200,
          {
            'status': 'success',
            'data': {
              'items': [for (final card in bookCards) wire(card)],
              'total': bookCards.length,
              'limit': bookCards.length,
              'offset': 0,
              'day': '2026-11-23',
            },
          },
        ),
      );
      // The session each reader's request carries, if any.
      const sessions = <String, String?>{
        'signed out': null,
        'guest': 'guest-session-jwt',
        'free': 'free-session-jwt',
        'premium': 'premium-session-jwt',
      };
      final games = [
        for (final card in bookCards) CollectionGame.fromPreviewCard(card)!,
      ];
      final reads = <String, StoryGamesRead>{};
      for (final MapEntry(key: who, value: session) in sessions.entries) {
        reads[who] = await readStoryGames(
          repositoryOver(http, session),
          slug: book.slug,
          day: '2026-11-23',
          // The server keeps the full games from all but the subscriber.
          detail: storyCollection(
            book.slug,
            kind: CollectionKind.book,
            access: CollectionAccess.premium,
            locked: who != 'premium',
          ),
          games: games,
        );
      }
      expect(http.requests, hasLength(sessions.length));
      for (final request in http.requests) {
        expect(request.method, 'GET');
        expect(
          request.uri.path,
          '/api/collections/${Uri.encodeComponent(book.slug)}/games',
        );
        // Exactly what gamebase's strict story query takes.
        expect(request.uri.queryParameters, {
          'include': 'story',
          'day': '2026-11-23',
        });
        expect(request.headers['X-API-Key'], 'first-party');
      }
      // Signed out, the read carries no account at all.
      expect(http.requests.first.headers['Authorization'], isNull);
      expect(
        http.requests[1].headers['Authorization'],
        'Bearer guest-session-jwt',
      );
      String describe(StoryGamesRead read) => [
        read.latest?.id,
        for (final g in read.candidates) g.id,
        for (final id in read.pgns.keys.toList()..sort())
          '$id=${read.pgns[id]}',
      ].join('\n');
      for (final who in sessions.keys) {
        expect(describe(reads[who]!), describe(reads['premium']!), reason: who);
      }
      final guest = reads['guest']!;
      expect(guest.latest?.id, 'latest');
      expect([for (final g in guest.candidates) g.id], ['sideline']);
      expect(guest.pgns, {'latest': botvinnikPgn, 'sideline': sidelinePgn});
    });

    test('a server from before the read answers 400 (or 404) and the old '
        'path runs; any other refusal is not hidden', () async {
      Map<String, Object?> refusal(String message, [String? code]) => {
        'status': 'error',
        'error': {'message': message, 'code': ?code},
      };
      for (final (status, body) in [
        (400, refusal('Failed to validate request')),
        (404, refusal('Not found')),
      ]) {
        final read = await repositoryOver(
          _Wire((_) => (status, body)),
          null,
        ).fetchStoryGames(book.slug, day: '2026-11-23');
        expect(read, isNull, reason: '$status');
      }
      await expectLater(
        repositoryOver(
          _Wire(
            (_) => (
              403,
              refusal(
                'Premium collections are not available on contributor keys',
                'access_denied',
              ),
            ),
          ),
          null,
        ).fetchStoryGames(book.slug, day: '2026-11-23'),
        throwsA(
          isA<CollectionsRequestException>().having(
            (e) => e.statusCode,
            'statusCode',
            403,
          ),
        ),
      );
    });
  });
}

/// Records every request and answers each with [answer]'s status and body.
class _Wire implements HttpClientAdapter {
  _Wire(this.answer);

  final (int, Object) Function(RequestOptions options) answer;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final (status, body) = answer(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _LegacyServer implements CollectionsRepository {
  int pgnReads = 0;

  @override
  Future<List<CollectionGameCard>?> fetchStoryGames(
    String slug, {
    required String day,
  }) async => null;

  @override
  Future<Map<String, String>> fetchPgnsOf(
    String slug,
    Set<String> ids, {
    List<String>? order,
  }) async {
    pgnReads++;
    return {
      for (final card in bookCards)
        if (ids.contains(card.id)) card.id: card.pgn!,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
