import 'package:flutter_test/flutter_test.dart';
import 'package:chessever2/screens/chessboard/video/video_session.dart';
import 'package:chessever2/screens/chessboard/video/video_stream.dart';
import 'event_video_test.dart' show FakeVideoRepository, fixtureVideos;

List<EventVideoStream> analyses(String game, int start) =>
    EventVideoStream.readList([
      {
        'id': 'analysis-$game',
        'kind': 'analysis',
        'label': 'Coach One',
        'authorName': 'Coach One',
        'authorAvatarUrl': 'https://images.example.com/coach.webp',
        'provider': 'youtube',
        'url': 'https://youtu.be/abcdefghijk?t=$start&end=${start + 60}&mute=1',
      },
    ]);

void main() {
  test(
    'completed games list analyses first, live games retain broadcast order',
    () async {
      final session = EventVideoSession(
        repository: FakeVideoRepository(fixtureVideos()),
      );
      addTearDown(session.dispose);
      session.openGame(gameId: 'g1', tourId: 'event', roundId: 'round');
      await Future<void>.delayed(Duration.zero);
      final broadcasts = session.streams.map((s) => s.id).toList();
      session.setCompleted(true);
      session.setAnalysisStreams(analyses('g1', 90));
      expect(session.streams.first.isAnalysis, isTrue);
      expect(session.selected!.isAnalysis, isTrue);
      session.activateStream(broadcasts.first);
      session.setAnalysisStreams(analyses('g1', 100));
      expect(session.selected!.id, broadcasts.first);
      session.setCompleted(false);
      expect(
        session.streams.take(broadcasts.length).map((s) => s.id),
        broadcasts,
      );
    },
  );

  test('legacy broadcasts keep accepting ignored query parameters', () {
    expect(
      VideoSource.parse('https://youtu.be/abcdefghijk?t=live').id,
      'abcdefghijk',
    );
    expect(
      () => VideoSource.parse(
        'https://youtu.be/abcdefghijk?t=live',
        strict: true,
      ),
      throwsFormatException,
    );
  });

  test(
    'an author source is available on a detached board and its tap starts the segment',
    () {
      final session = EventVideoSession(repository: null);
      addTearDown(session.dispose);
      session.openGame(gameId: 'g1', tourId: '', roundId: '');
      session.setAnalysisStreams(analyses('g1', 120));
      expect(session.hasVideo, isTrue);
      expect(session.selected!.authorName, 'Coach One');
      expect(
        session.selected!.authorAvatarUrl,
        'https://images.example.com/coach.webp',
      );
      expect(session.selected!.source.url.queryParameters['start'], '120');
      final revision = session.playerRevision;
      session.activateStream('analysis-g1');
      expect(session.playerRevision, greaterThan(revision));
      expect(session.playRequested, isTrue);
      expect(session.muted, isTrue);
      session.openGame(gameId: 'g2', tourId: '', roundId: '');
      expect(session.hasVideo, isFalse);
      expect(session.playRequested, isFalse);
      session.setAnalysisStreams(analyses('g2', 300));
      expect(session.selected!.source.url.queryParameters['start'], '300');
    },
  );

  test(
    'broadcast and author sources coexist, and removing access drops recorded playback',
    () async {
      final repo = FakeVideoRepository(fixtureVideos());
      final session = EventVideoSession(repository: repo);
      addTearDown(session.dispose);
      session.openGame(gameId: 'g1', tourId: 'event', roundId: 'round');
      await Future<void>.delayed(Duration.zero);
      final count = session.streams.length;
      session.setAnalysisStreams(analyses('g1', 120));
      expect(session.streams.length, count + 1);
      session.activateStream('analysis-g1');
      await session.refresh();
      expect(session.selected!.id, 'analysis-g1');
      session.setAnalysisStreams(const []);
      expect(session.streams.length, count);
      expect(session.selected!.isAnalysis, isFalse);
      expect(session.playRequested, isFalse);
    },
  );

  test(
    'two authors can reference the same recording without losing their source circles',
    () {
      final streams = EventVideoStream.readList([
        for (final name in ['Author One', 'Author Two'])
          {
            'id': name.replaceAll(' ', '-'),
            'kind': 'analysis',
            'authorName': name,
            'label': name,
            'url': 'https://youtu.be/abcdefghijk?t=120',
          },
      ]);
      expect(streams, hasLength(2));
      expect(streams.map((s) => s.languageKey).toSet(), hasLength(2));
    },
  );
}
