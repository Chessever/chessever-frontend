import 'dart:convert';
import 'package:chessever2/config/app_environment.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:chessever2/screens/chessboard/video/video_player.dart';
import 'package:chessever2/screens/chessboard/video/video_repository.dart';
import 'package:chessever2/screens/chessboard/video/video_session.dart';
import 'package:chessever2/screens/chessboard/video/video_stream.dart';

List<EventVideoStream> fixtureVideos() => EventVideoStream.readList(
  jsonDecode(
    File('test/fixtures/event_video_streams.json').readAsStringSync(),
  )['streams'],
);

class FakeVideoRepository implements EventVideoRepository {
  FakeVideoRepository(this.streams);
  List<EventVideoStream> streams;
  Object? error;
  int requests = 0;
  @override
  Future<ResolvedEventVideos> fetch({
    required String tourId,
    required String roundId,
  }) async {
    requests++;
    if (error != null) throw error!;
    return ResolvedEventVideos(streams);
  }

  @override
  void close() {}
}

void main() {
  test('video visibility is saved across events and restored paused', () async {
    bool? stored;
    final session = EventVideoSession(
      repository: FakeVideoRepository(fixtureVideos()),
      saveVisibility: (value) async {
        stored = value;
      },
    );
    addTearDown(session.dispose);
    session.openGame(gameId: 'g1', tourId: 'one', roundId: 'r1');
    await Future<void>.delayed(Duration.zero);
    expect(session.showVideo, isTrue);
    session.toggle();
    expect(stored, isFalse);
    session.openGame(gameId: 'g2', tourId: 'two', roundId: 'r2');
    await Future<void>.delayed(Duration.zero);
    expect(session.showVideo, isFalse);
    final restored = EventVideoSession(
      repository: FakeVideoRepository(fixtureVideos()),
      visible: stored!,
      saveVisibility: (value) async {
        stored = value;
      },
    );
    addTearDown(restored.dispose);
    restored.openGame(gameId: 'g3', tourId: 'three', roundId: 'r3');
    await Future<void>.delayed(Duration.zero);
    expect(restored.hasVideo, isTrue);
    expect(restored.showVideo, isFalse);
    expect(restored.streamChosen, isFalse);
    restored.toggle();
    expect(stored, isTrue);
    expect(restored.showVideo, isTrue);
    expect(restored.playRequested, isFalse);
  });

  test(
    'saved country comes first, then countrymen, without reordering on selection',
    () async {
      final session = EventVideoSession(
        repository: FakeVideoRepository(fixtureVideos()),
        savedCountry: 'ES',
        preferredCountry: 'DE',
      );
      addTearDown(session.dispose);
      session.openGame(gameId: 'g', tourId: 'tour', roundId: 'round');
      await Future<void>.delayed(Duration.zero);
      expect(session.streams.map((s) => s.id), [
        'spanish',
        'german',
        'english-main',
        'english-second',
      ]);
      final order = session.streams.map((s) => s.id).toList();
      session.select('english-main');
      await session.refresh();
      expect(session.streams.map((s) => s.id), order);
    },
  );

  test(
    'web platform contract supports legacy and explicitly enabled mobile streams',
    () {
      final base = <String, dynamic>{
        'id': 's',
        'label': 'Stream',
        'url': 'https://youtu.be/abcdefghijk',
      };
      for (final platforms in [
        null,
        <String>[],
        ['web'],
        ['desktop'],
        ['mobile'],
        ['web', 'mobile'],
        ['mobile', 'mobile'],
      ]) {
        final stream =
            EventVideoStream.readList([
              {...base, if (platforms != null) 'platforms': platforms},
            ]).single;
        expect(
          stream.supportsPlatform(VideoClientPlatform.mobile),
          platforms == null || platforms.contains('mobile'),
        );
      }
      for (final invalid in [
        null,
        'mobile',
        ['android'],
        ['mobile', 1],
      ]) {
        expect(
          EventVideoStream.readList([
            {...base, 'platforms': invalid},
          ]),
          isEmpty,
        );
      }
      final stream =
          EventVideoStream.readList([
            {
              ...base,
              'language': 'hi-IN',
              'publication': {'language': 'en'},
            },
          ]).single;
      expect(stream.languageKey, 'hi');
      expect(stream.flagCode, 'IN');
    },
  );

  test(
    'mobile filtering precedes preference selection and refresh removes excluded playback',
    () async {
      List<EventVideoStream> streams(List<String> targets) =>
          EventVideoStream.readList([
            {
              'id': 'preferred',
              'label': 'English',
              'url': 'https://youtu.be/abcdefghijk',
              'platforms': targets,
              'preferred': true,
            },
            {
              'id': 'mobile',
              'label': 'Deutsch',
              'url': 'https://twitch.tv/fixture_chess',
              'platforms': ['mobile'],
            },
          ]);
      final repo = FakeVideoRepository(streams(['web']));
      final session = EventVideoSession(repository: repo, savedCountry: 'GB');
      addTearDown(session.dispose);
      session.openGame(gameId: 'g', tourId: 'tour', roundId: 'round');
      await Future<void>.delayed(Duration.zero);
      expect(session.streams.map((s) => s.id), ['mobile']);
      expect(session.selected!.id, 'mobile');
      repo.streams = streams(['mobile']);
      await session.refresh();
      session.select('preferred');
      session.reportPlayback(true, session.playerRevision);
      repo.streams = streams(['desktop']);
      await session.refresh();
      expect(session.selected!.id, 'mobile');
      expect(session.playing, isFalse);
      repo.streams = streams(['web']).take(1).toList();
      await session.refresh();
      expect(session.hasVideo, isFalse);
    },
  );

  test(
    'country groups sort matching streams first and save manual country',
    () async {
      String? stored;
      final session = EventVideoSession(
        repository: FakeVideoRepository(fixtureVideos()),
        preferredCountry: 'MX',
        saveCountry: (value) async => stored = value,
      );
      addTearDown(session.dispose);
      session.openGame(gameId: 'g', tourId: 'tour', roundId: 'round');
      await Future<void>.delayed(Duration.zero);
      expect(session.selected!.id, 'spanish');
      expect(session.streams.first.id, 'spanish');
      final initialOrder = session.streams.map((s) => s.id).toList();
      session.select('english-second');
      expect(stored, 'GB');
      expect(session.streams.map((s) => s.id), initialOrder);
      await session.refresh();
      expect(session.streams.map((s) => s.id), initialOrder);
      session.openGame(gameId: 'g2', tourId: 'tour', roundId: 'round');
      expect(session.streams.map((s) => s.id), initialOrder);
      expect(session.selected!.id, 'english-second');
      final next = EventVideoSession(
        repository: FakeVideoRepository(fixtureVideos()),
        preferredCountry: 'DE',
        savedCountry: stored,
      );
      addTearDown(next.dispose);
      next.openGame(gameId: 'g', tourId: 'tour', roundId: 'round');
      await Future<void>.delayed(Duration.zero);
      expect(next.selected!.id, 'english-main');
      expect(next.streams.first.flagCode, 'GB');
      expect(next.playRequested, isFalse);
    },
  );

  test('exact countrymen match precedes language-group fallbacks', () async {
    for (final country in ['AT', 'BR']) {
      final session = EventVideoSession(
        repository: FakeVideoRepository(fixtureVideos()),
        preferredCountry: 'ES',
        savedCountry: country,
      );
      session.openGame(gameId: 'g', tourId: 'tour', roundId: 'round');
      await Future<void>.delayed(Duration.zero);
      expect(session.selected!.id, 'spanish');
      expect(session.streams.first.id, session.selected!.id);
      session.dispose();
    }
  });

  test(
    'countrymen selects first matching flag before remembered language',
    () async {
      final session = EventVideoSession(
        repository: FakeVideoRepository(fixtureVideos()),
        preferredCountry: 'de',
        rememberedLanguage: 'en',
      );
      addTearDown(session.dispose);
      session.openGame(gameId: 'game', tourId: 'tour', roundId: 'round');
      await Future<void>.delayed(Duration.zero);
      expect(session.selected!.id, 'german');
      expect(session.playRequested, isFalse);
      session.select('spanish');
      session.setPreferredCountry('GB');
      await session.refresh();
      expect(session.selected!.id, 'spanish');
      session.openGame(gameId: 'next', tourId: 'tour', roundId: 'round');
      expect(session.selected!.id, 'spanish');
    },
  );

  test(
    'late countrymen preference picks first matching stream until playback',
    () async {
      final session = EventVideoSession(
        repository: FakeVideoRepository(fixtureVideos()),
      );
      addTearDown(session.dispose);
      session.openGame(gameId: 'game', tourId: 'tour', roundId: 'round');
      await Future<void>.delayed(Duration.zero);
      session.setPreferredCountry('DE');
      expect(session.selected!.id, 'german');
      session.setPreferredCountry('GB');
      expect(session.selected!.id, 'english-main');
      session.reportPlayback(true, session.playerRevision);
      session.setPreferredCountry('ES');
      expect(session.selected!.id, 'english-main');
      expect(session.playing, isTrue);
    },
  );

  test('unmatched country uses event default', () async {
    final session = EventVideoSession(
      repository: FakeVideoRepository(fixtureVideos()),
      preferredCountry: 'JP',
      rememberedLanguage: 'es',
    );
    addTearDown(session.dispose);
    session.openGame(gameId: 'game', tourId: 'tour', roundId: 'round');
    await Future<void>.delayed(Duration.zero);
    expect(session.selected!.id, 'english-main');
  });

  test(
    'all supported URL forms normalize and unsafe/future providers fail',
    () {
      for (final url in [
        'https://youtu.be/abcdefghijk',
        'https://m.youtube.com/watch?v=abcdefghijk',
        'https://youtube.com/live/abcdefghijk',
      ]) {
        expect(
          VideoSource.parse(url).url.toString(),
          'https://www.youtube.com/watch?v=abcdefghijk',
        );
      }
      expect(VideoSource.parse('https://twitch.tv/Chess_123').id, 'chess_123');
      expect(VideoSource.parse('https://kick.com/Chess-123').id, 'chess-123');
      for (final url in [
        'http://twitch.tv/chess',
        'https://user:pass@twitch.tv/chess',
        'https://twitch.tv:8000/chess',
        'https://youtube.com/@chess/live',
        'https://twitch.tv/videos/123',
        'https://kick.com/categories',
        'https://youtube.com.evil.test/watch?v=abcdefghijk',
        'javascript:alert(1)',
      ]) {
        expect(
          () => VideoSource.parse(url),
          throwsFormatException,
          reason: url,
        );
      }
    },
  );
  test(
    'normalization skips malformed entries and deduplicates IDs and sources',
    () {
      final data =
          jsonDecode(
                File(
                  'test/fixtures/event_video_streams.json',
                ).readAsStringSync(),
              )['streams']
              as List;
      final streams = EventVideoStream.readList([
        null,
        {},
        ...data,
        data.first,
        {
          'id': 'bad',
          'url': 'https://youtu.be/abcdefghijk',
          'provider': 'kick',
          'label': 'bad',
        },
        {'countryCode': 'XX', 'url': 'https://kick.com/invalid_flag'},
        {'countryCode': 'FR', 'url': 'https://kick.com/french'},
      ]);
      expect(streams.length, 5);
      expect(streams.last.label, 'France');
      expect(streams.last.languageKey, 'country-FR');
    },
  );
  test('language evidence, flags, and web selection order', () {
    final streams = fixtureVideos();
    expect(streams[0].languageKey, 'en');
    expect(streams[0].displayName, 'Studio');
    expect(streams[2].languageKey, 'de');
    expect(streams[3].languageKey, 'es');
    final ranked = orderVideoStreams(streams.reversed.toList());
    expect(ranked.take(2).map((s) => s.id), ['english-main', 'english-second']);
    expect(ranked.last.languageKey, 'es');
  });
  test('audiences deduplicate channels and prefer newest observation', () {
    EventVideoStream stream(
      String id,
      String language,
      String channel,
      int count,
      String date, {
      bool preferred = false,
    }) => EventVideoStream(
      id: id,
      label: id,
      source: VideoSource.parse('https://kick.com/$id'),
      language: language,
      audience: VideoAudience(channel, count, date),
      preferred: preferred,
    );
    final streams = orderVideoStreams([
      stream('de-one', 'de', '1', 100, '2026-09-01'),
      stream('de-two', 'de', '1', 20, '2026-09-02'),
      stream('es-one', 'es', '2', 30, '2026-09-01'),
      stream('es-preferred', 'es', '3', 1, '2026-09-01', preferred: true),
      stream('en', 'en', '4', 0, '2026-09-01'),
    ]);
    expect(streams.map((s) => s.id), [
      'en',
      'es-preferred',
      'es-one',
      'de-one',
      'de-two',
    ]);
  });
  test('test origins are explicit, isolated, and absent by default', () {
    EventVideoConfiguration? config(bool test, String api, String embed) =>
        EventVideoConfiguration.forFlavor(
          test ? AppFlavor.test : AppFlavor.production,
          testApiOrigin: api,
          testEmbedOrigin: embed,
        );
    expect(config(true, '', ''), isNull);
    final production =
        config(
          false,
          'https://api.test.example.com',
          'https://embed.test.example.com',
        )!;
    expect(
      production.apiOrigin.toString(),
      'https://api.broadcast.chessever.com',
    );
    expect(production.embedOrigin.toString(), 'https://chessever.com');
    expect(
      config(
        true,
        'https://api.broadcast.chessever.com',
        'https://embed.test.example.com',
      ),
      isNull,
    );
    expect(
      config(
        true,
        'https://api.example.com/?test=1',
        'https://embed.test.example.com',
      ),
      isNull,
    );
    expect(
      config(
        true,
        'https://api.test.example.com',
        'https://embed.test.example.com',
      ),
      isNotNull,
    );
  });
  test(
    'production defaults resolve streams for iPHk1gu0 without video defines',
    () async {
      final configuration =
          EventVideoConfiguration.forFlavor(AppFlavor.production)!;
      expect(
        configuration.apiOrigin.toString(),
        'https://api.broadcast.chessever.com',
      );
      expect(configuration.embedOrigin.toString(), 'https://chessever.com');
      final snapshot =
          File('test/fixtures/event_video_iPHk1gu0.json').readAsStringSync();
      final repository = HttpEventVideoRepository(
        configuration,
        client: MockClient((request) async {
          expect(
            request.url.toString(),
            'https://api.broadcast.chessever.com/api/broadcast/round/OZAeHb4n/video-streams',
          );
          expect(request.followRedirects, isFalse);
          return http.Response(
            snapshot,
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final session = EventVideoSession(repository: repository);
      addTearDown(session.dispose);
      session.openGame(
        gameId: 'fixture-game',
        tourId: 'iPHk1gu0',
        roundId: 'OZAeHb4n',
      );
      await Future<void>.delayed(Duration.zero);
      expect(session.failed, isFalse);
      expect(session.streams, hasLength(14));
      expect(
        session.streams.map((stream) => stream.id),
        contains('youtube-quTNRNvL-rA'),
      );
      expect(session.showVideo, isTrue);
      expect(session.streamChosen, isFalse);
      expect(session.playRequested, isFalse);
    },
  );

  test(
    'repository uses round endpoint and only falls back when round absent',
    () async {
      final requests = <String>[];
      final config =
          EventVideoConfiguration.forFlavor(
            AppFlavor.test,
            testApiOrigin: 'https://api.test.example.com',
            testEmbedOrigin: 'https://embed.test.example.com',
          )!;
      final repo = HttpEventVideoRepository(
        config,
        client: MockClient((r) async {
          requests.add(r.url.path);
          expect(r.followRedirects, isFalse);
          return http.Response('{"streams":[],"source":null}', 200);
        }),
      );
      await repo.fetch(tourId: 'tour1', roundId: 'round1');
      await repo.fetch(tourId: 'tour1', roundId: '');
      expect(requests, [
        '/api/broadcast/round/round1/video-streams',
        '/api/broadcast/tour1/video-streams',
      ]);
      repo.close();
    },
  );
  test(
    'metadata failures classify permanent responses without redirects',
    () async {
      final config =
          EventVideoConfiguration.forFlavor(
            AppFlavor.test,
            testApiOrigin: 'https://api.test.example.com',
            testEmbedOrigin: 'https://embed.test.example.com',
          )!;
      for (final code in [403, 404, 503, 302]) {
        final repo = HttpEventVideoRepository(
          config,
          client: MockClient((_) async => http.Response('', code)),
        );
        await expectLater(
          repo.fetch(tourId: 'tour', roundId: 'round'),
          throwsA(
            isA<VideoMetadataException>().having(
              (e) => e.permanent,
              'permanent',
              code == 403 || code == 404,
            ),
          ),
        );
        repo.close();
      }
    },
  );
  test(
    'initial pause, country memory, same-event playback, hide and lifecycle',
    () async {
      final repo = FakeVideoRepository(fixtureVideos());
      final session = EventVideoSession(repository: repo, savedCountry: 'ES');
      addTearDown(session.dispose);
      session.openGame(gameId: 'g1', tourId: 'tour', roundId: 'round');
      await Future<void>.delayed(Duration.zero);
      expect(session.selected!.id, 'spanish');
      expect(session.playRequested, isFalse);
      expect(session.showVideo, isTrue);
      session.select('english-main');
      expect(session.playRequested, isTrue);
      session.reportPlayback(true, session.playerRevision);
      final revision = session.playerRevision;
      session.openGame(gameId: 'g2', tourId: 'tour', roundId: 'round');
      expect(session.playing, isTrue);
      expect(session.playerRevision, revision);
      session.select('english-second');
      expect(session.playRequested, isTrue);
      session.reportPlayback(true, revision); // stale old-player event
      expect(session.playing, isFalse);
      session.toggle();
      expect(session.playRequested, isFalse);
      session.toggle();
      expect(session.playRequested, isFalse);
      session.reportPlayback(true, session.playerRevision);
      session.setForeground(false);
      expect(session.playing, isFalse);
      session.setForeground(true);
      expect(session.playRequested, isFalse);
    },
  );
  test(
    'refresh preserves player on temporary failures and clears permanent ones',
    () async {
      final repo = FakeVideoRepository(fixtureVideos());
      final session = EventVideoSession(repository: repo);
      addTearDown(session.dispose);
      session.openGame(gameId: 'g', tourId: 'tour', roundId: 'round');
      await Future<void>.delayed(Duration.zero);
      session.reportPlayback(true, session.playerRevision);
      final revision = session.playerRevision;
      repo.error = const VideoMetadataException(false);
      await session.refresh();
      expect(session.playing, isTrue);
      expect(session.playerRevision, revision);
      repo.error = const VideoMetadataException(true);
      await session.refresh();
      expect(session.hasVideo, isFalse);
      expect(session.playing, isFalse);
    },
  );
  test(
    'metadata refresh freezes rankings and never resets unchanged selection',
    () async {
      final repo = FakeVideoRepository(fixtureVideos());
      final session = EventVideoSession(repository: repo);
      addTearDown(session.dispose);
      session.openGame(gameId: 'g', tourId: 't', roundId: 'r');
      await Future<void>.delayed(Duration.zero);
      final order = session.streams.map((s) => s.id).toList();
      final revision = session.playerRevision;
      repo.streams =
          repo.streams.reversed
              .map(
                (s) => EventVideoStream(
                  id: s.id,
                  label: s.label,
                  source: s.source,
                  countryCode: s.countryCode,
                  language: s.language,
                  preferred: s.id == 'english-second',
                ),
              )
              .toList();
      await session.refresh();
      expect(session.streams.map((s) => s.id), order);
      expect(session.playerRevision, revision);
    },
  );
  test(
    'provider embeds never autoplay on initial load and carry correct parent',
    () {
      for (final stream in fixtureVideos()) {
        final html = videoPlayerHtml(
          stream.source,
          Uri.parse('https://embed.test.example.com'),
          revision: 3,
          play: false,
          muted: false,
          controls: false,
        );
        expect(html, contains('revision:3'));
        expect(html, isNot(contains('autoplay:true')));
        expect(html, isNot(contains('autoplay:1')));
        expect(html, isNot(contains('autoplay=true')));
        expect(html, isNot(contains('playVideo()')));
        expect(html, isNot(contains('p.play()')));
        switch (stream.source.platform) {
          case VideoPlatform.youtube:
            expect(html, contains('controls:0'));
          case VideoPlatform.twitch:
            expect(html, contains('controls:false'));
          case VideoPlatform.kick:
            expect(html, contains('controls=false'));
        }
        if (stream.source.platform == VideoPlatform.twitch) {
          expect(html, contains('parent:["embed.test.example.com"]'));
        }
      }
    },
  );
  test('provider embeds apply the reported mute state on load', () {
    String htmlFor(String url, bool muted) => videoPlayerHtml(
      VideoSource.parse(url),
      Uri.parse('https://embed.test.example.com'),
      revision: 3,
      play: true,
      muted: muted,
      controls: false,
    );
    final youtubeMuted = htmlFor('https://youtu.be/abcdefghijk', true);
    expect(youtubeMuted, contains('mute:1'));
    expect(youtubeMuted, contains('ytPlayer.mute()'));
    expect(youtubeMuted, contains('ytPlayer.playVideo()'));
    expect(youtubeMuted, contains('watchMuted(()=>ytPlayer.isMuted())'));
    final youtubeUnmuted = htmlFor('https://youtu.be/abcdefghijk', false);
    expect(youtubeUnmuted, contains('mute:0'));
    expect(youtubeUnmuted, contains('ytPlayer.unMute()'));
    final twitchMuted = htmlFor('https://twitch.tv/fixture_chess', true);
    expect(twitchMuted, contains('muted:true'));
    expect(twitchMuted, contains('p.setMuted(true)'));
    expect(twitchMuted, contains('p.play()'));
    expect(twitchMuted, contains('watchMuted(()=>p.getMuted())'));
    final twitchUnmuted = htmlFor('https://twitch.tv/fixture_chess', false);
    expect(twitchUnmuted, contains('muted:false'));
    expect(twitchUnmuted, contains('p.setMuted(false)'));
    // Kick cannot read mute inside its frame; the last reported state rides
    // into the embed URL.
    expect(
      htmlFor('https://kick.com/fixture_chess', true),
      contains('muted=true'),
    );
    expect(
      htmlFor('https://kick.com/fixture_chess', false),
      contains('muted=false'),
    );
  });
  test('provider controls stay hidden until the reader reveals them', () {
    String htmlFor(String url, {required bool controls}) => videoPlayerHtml(
      VideoSource.parse(url),
      Uri.parse('https://embed.test.example.com'),
      revision: 3,
      play: true,
      muted: false,
      controls: controls,
    );
    final youtubeHidden = htmlFor(
      'https://youtu.be/abcdefghijk',
      controls: false,
    );
    expect(youtubeHidden, contains('controls:0'));
    expect(
      htmlFor('https://youtu.be/abcdefghijk', controls: true),
      contains('controls:1'),
    );
    expect(
      htmlFor('https://twitch.tv/fixture_chess', controls: false),
      contains('controls:false'),
    );
    expect(
      htmlFor('https://twitch.tv/fixture_chess', controls: true),
      contains('controls:true'),
    );
    expect(
      htmlFor('https://kick.com/fixture_chess', controls: false),
      contains('controls=false'),
    );
    expect(
      htmlFor('https://kick.com/fixture_chess', controls: true),
      contains('controls=true'),
    );
  });
  test('one tap reveals provider controls, keeping playback and mute', () {
    final session = EventVideoSession(
      repository: FakeVideoRepository(fixtureVideos()),
    );
    addTearDown(session.dispose);
    session.openGame(gameId: 'g1', tourId: 'tour', roundId: 'round');
    session.streams = fixtureVideos();
    session.selected = session.streams.first;
    expect(session.controlsVisible, isFalse);
    session.select('english-main');
    expect(session.controlsVisible, isFalse);
    session.reportPlayback(true, session.playerRevision);
    session.reportMuted(true, session.playerRevision);
    final revision = session.playerRevision;
    session.revealControls();
    expect(session.controlsVisible, isTrue);
    expect(session.playRequested, isTrue);
    expect(session.playing, isFalse);
    expect(session.playerRevision, revision + 1);
    expect(session.muted, isTrue);
    // Revealing again is a no-op: from now on the provider owns the taps.
    session.revealControls();
    expect(session.playerRevision, revision + 1);
    // A new choice starts clean again, and hiding the video resets it too.
    session.select('english-second');
    expect(session.controlsVisible, isFalse);
    session.revealControls();
    expect(session.controlsVisible, isTrue);
    session.toggle();
    expect(session.controlsVisible, isFalse);
  });
  test(
    'reported mute state survives stream switches and stale revisions',
    () async {
      final session = EventVideoSession(
        repository: FakeVideoRepository(fixtureVideos()),
      );
      addTearDown(session.dispose);
      session.openGame(gameId: 'g1', tourId: 'tour', roundId: 'round');
      await Future<void>.delayed(Duration.zero);
      expect(session.muted, isFalse);
      session.reportPlayback(true, session.playerRevision);
      session.reportMuted(true, session.playerRevision);
      expect(session.muted, isTrue);
      session.select('english-second');
      expect(session.muted, isTrue);
      expect(session.playRequested, isTrue);
      session.reportMuted(false, session.playerRevision - 1); // stale document
      expect(session.muted, isTrue);
      session.reportMuted(false, session.playerRevision);
      expect(session.muted, isFalse);
    },
  );
  test('choice is required at every switch-on and kept across games', () async {
    final session = EventVideoSession(
      repository: FakeVideoRepository(fixtureVideos()),
    );
    addTearDown(session.dispose);
    session.openGame(gameId: 'g1', tourId: 'tour', roundId: 'round');
    session.streams = fixtureVideos();
    session.selected = session.streams.first;
    expect(session.streamChosen, isFalse);
    session.select('english-main');
    expect(session.streamChosen, isTrue);
    // Same-event game change keeps the choice (and the player).
    session.openGame(gameId: 'g2', tourId: 'tour', roundId: 'round');
    expect(session.streamChosen, isTrue);
    // A new round of the same event keeps the running stream too: swiping or
    // jumping between games never interrupts the broadcast.
    session.openGame(gameId: 'g3', tourId: 'tour', roundId: 'round-2');
    await Future<void>.delayed(Duration.zero);
    expect(session.streamChosen, isTrue);
    expect(session.selected!.id, 'english-main');
    // A new event is a fresh switch-on; streams resolve anew.
    session.openGame(gameId: 'g4', tourId: 'other', roundId: 'round');
    await Future<void>.delayed(Duration.zero);
    expect(session.streamChosen, isFalse);
    session.select('english-main');
    expect(session.streamChosen, isTrue);
    session.toggle();
    session.toggle();
    expect(session.streamChosen, isFalse);
  });
  test('returning from background continues a stream that was live', () {
    final session = EventVideoSession(
      repository: FakeVideoRepository(fixtureVideos()),
    );
    addTearDown(session.dispose);
    session.openGame(gameId: 'g1', tourId: 'tour', roundId: 'round');
    session.streams = fixtureVideos();
    session.selected = session.streams.first;
    session.select('english-main');
    session.reportPlayback(true, session.playerRevision);
    session.setForeground(false);
    expect(session.playRequested, isFalse);
    session.setForeground(true, resumeAfterBackground: true);
    expect(session.playRequested, isTrue);
    // A stream that was not live comes back paused.
    session.stopPlayback();
    session.setForeground(false);
    session.setForeground(true, resumeAfterBackground: true);
    expect(session.playRequested, isFalse);
    // Covering the board with another route still returns paused.
    session.select('english-main');
    session.reportPlayback(true, session.playerRevision);
    session.setForeground(false);
    session.setForeground(true);
    expect(session.playRequested, isFalse);
  });
  test(
    'a stream that disappears from the new round offers the choice again',
    () async {
      final repo = FakeVideoRepository(fixtureVideos());
      final session = EventVideoSession(repository: repo);
      addTearDown(session.dispose);
      session.openGame(gameId: 'g1', tourId: 'tour', roundId: 'round-1');
      await Future<void>.delayed(Duration.zero);
      session.select('english-main');
      session.reportPlayback(true, session.playerRevision);
      expect(session.playing, isTrue);
      expect(session.streamChosen, isTrue);
      // The new round no longer carries the chosen stream, so playback stops
      // and the picker comes back instead of silently switching streams.
      repo.streams =
          fixtureVideos().where((s) => s.id != 'english-main').toList();
      session.openGame(gameId: 'g2', tourId: 'tour', roundId: 'round-2');
      await Future<void>.delayed(Duration.zero);
      expect(session.streamChosen, isFalse);
      expect(session.playing, isFalse);
      expect(session.selected!.id, isNot('english-main'));
    },
  );
}
