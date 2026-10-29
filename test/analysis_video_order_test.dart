import 'package:flutter_test/flutter_test.dart';
import 'package:chessever2/utils/analysis_video_order.dart';
import 'package:chessever2/repository/library/library_book_publication.dart';

void main() {
  test(
    'analysis ordering is followed authors, language, newest, stable identity',
    () {
      AnalysisVideoRank rank(
        String id, {
        bool followed = false,
        String language = 'en',
        String date = '2026-01-01',
      }) => (
        followed: followed,
        language: language,
        publishedAt: date,
        label: 'Author',
        id: id,
      );
      final sources = [
        rank('old'),
        rank('new', date: '2026-10-01'),
        rank('language', language: 'tr-TR'),
        rank('followed', followed: true, language: 'de'),
      ];
      sources.sort((a, b) => compareAnalysisVideoRanks(a, b, 'tr'));
      expect(sources.map((v) => v.id), ['followed', 'language', 'new', 'old']);
      expect(
        compareAnalysisVideoRanks(rank('a'), rank('b'), 'en'),
        lessThan(0),
      );
    },
  );
  test(
    'old publication payloads omit video settings; optional maps survive edits',
    () {
      final old = LibraryBookMetadata.fromJson({'title': 'Existing book'});
      expect(old.toJson().containsKey('gameVideos'), false);
      expect(old.toJson().containsKey('gameVideoLanguages'), false);
      final value = LibraryBookMetadata.fromJson({
        'title': 'Existing book',
        'gameVideos': {'game': 'https://youtu.be/abcdefghijk?t=90'},
        'gameVideoLanguages': {'game': 'tr'},
      }).copyWith(author: 'Writer');
      expect(value.toJson()['gameVideos'], {
        'game': 'https://youtu.be/abcdefghijk?t=90',
      });
      expect(value.toJson()['gameVideoLanguages'], {'game': 'tr'});
    },
  );
}
