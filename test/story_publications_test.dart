import 'package:chessever2/screens/chessboard/video/video_player.dart';
import 'package:chessever2/screens/chessboard/video/video_stream.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/stories/story_models.dart';
import 'package:chessever2/screens/stories/story_publications.dart';
import 'package:chessever2/screens/stories/story_seen_store.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStorySeen implements StorySeenStorage {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}
}

const _collection = Collection(
  id: 'book-id',
  slug: 'book',
  title: 'Study book',
  kind: CollectionKind.book,
  coverUrl: 'https://example.com/book.webp',
  contentVersion: 'v3',
);

void main() {
  test('published lineup preserves server ordering and source collection', () {
    final missed = missedChancesCollection(DateTime(2026, 11, 24));
    final lineup = readStoryLineup(
      [
        {'kind': 'missed_chances'},
        {
          'kind': 'editorial',
          'id': 'featured',
          'revision': 4,
          'mode': 'append',
          'collectionSlug': 'book',
        },
        {
          'kind': 'editorial',
          'id': 'standalone',
          'revision': 2,
          'mode': 'standalone',
          'title': 'Weekend',
        },
        {'kind': 'collection', 'collectionSlug': 'missing'},
      ],
      [_collection],
      missed,
    );
    expect(lineup.map((circle) => circle.title), [
      'Missed chances',
      'Study book',
      'Weekend',
    ]);
    final attached = lineup[1];
    expect(attached.coverUrl, _collection.coverUrl);
    expect(attached.access, CollectionAccess.premium);
    expect(storyPublicationKey(attached.slug), (
      id: 'featured',
      revision: 4,
      sourceSlug: 'book',
    ));
    expect(storyPublicationKey(lineup[2].slug)?.sourceSlug, isNull);
  });

  test(
    'each published slide counts toward the circle and can be resumed',
    () async {
      final seen = StorySeenNotifier(_MemoryStorySeen());
      addTearDown(seen.dispose);
      await Future<void>.delayed(Duration.zero);
      const media = StoryEditorialMedia(
        kind: 'announcement',
        title: 'Round starts at noon',
      );
      final batch = StoryBatch(
        games: const [],
        ordered: const [],
        featuredGame: true,
        publishedFrames: const [
          StoryFrame.media(story: 0, publicationId: 'one', media: media),
          StoryFrame.media(story: 1, publicationId: 'two', media: media),
        ],
      );
      expect(batch.durationOf(0), const Duration(seconds: 6));
      seen.markSeen(_collection, batch, 'one');
      expect(seen.resumeIndex(_collection, batch), 1);
      expect(seen.isSeen(_collection), isFalse);
      seen.markSeen(_collection, batch, 'two');
      expect(seen.isSeen(_collection), isTrue);
    },
  );

  test('a curated puzzle asks for the selected legal move', () {
    final analysis = analyzeStoryJobs(const [
      StoryAnalysisJob(
        id: 'puzzle',
        pgn: '1. e4 e5 2. Nf3 *',
        plies: [2],
        editorialPuzzle: true,
      ),
    ])['puzzle']!;
    expect(analysis.segments.single.puzzle?.answerSan, 'e5');
    expect(analysis.segments.single.ply, 2);
  });

  test('layers keep placement and drop invalid destinations', () {
    final layers = StoryLayer.read([
      {'kind': 'emoji', 'text': '♟️', 'x': 0.2, 'y': 0.7},
      {
        'kind': 'link',
        'text': 'Read more',
        'linkUrl': 'https://chessever.com',
        'x': 1,
        'y': 0,
      },
      {
        'kind': 'link',
        'text': 'Invalid',
        'linkUrl': 'javascript:alert(1)',
        'x': 0,
        'y': 1,
      },
    ]);
    expect(layers.map((layer) => layer.text), ['♟️', 'Read more']);
    expect(layers.first.x, 0.2);
    expect(layers.last.link, Uri.parse('https://chessever.com'));
  });

  test('Short timing is opt-in and respects a YouTube clip window', () {
    final source = VideoSource.parse(
      'https://www.youtube.com/shorts/abcdefghijk?start=5&end=20',
    );
    final origin = Uri.parse('https://chessever.com');
    final story = videoPlayerHtml(
      source,
      origin,
      revision: 1,
      play: true,
      muted: true,
      reportTiming: true,
    );
    final broadcast = videoPlayerHtml(
      source,
      origin,
      revision: 1,
      play: true,
      muted: true,
    );
    expect(
      story,
      contains(
        'const start=5, duration=Math.max(0,Math.min(ytPlayer.getDuration(),20)-start)',
      ),
    );
    expect(story, contains('window.chessInlinePlayback'));
    expect(broadcast, isNot(contains('publishTiming')));
  });
}
