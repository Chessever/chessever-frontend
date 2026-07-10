import 'package:chessever2/screens/studies/study_public_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const version =
      'sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

  group('StudyPublicLink', () {
    test('builds canonical Study and exact chapter context URLs', () {
      expect(
        StudyPublicLink(studyId: 'AbCd1234').uri.toString(),
        'https://chessever.com/studies/AbCd1234',
      );
      expect(
        StudyPublicLink(
          studyId: 'AbCd1234',
          chapterId: 'Chapter1',
          ply: 24,
          contentVersion: version,
        ).uri.toString(),
        'https://chessever.com/studies/AbCd1234/chapters/Chapter1?ply=24&v=sha256%3A0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      );
    });

    test('parses HTTPS and registered custom-scheme equivalents', () {
      final https = StudyPublicLink.tryParse(
        Uri.parse(
          'https://chessever.com/studies/AbCd1234/chapters/Chapter1?ply=0&v=$version',
        ),
      );
      final custom = StudyPublicLink.tryParse(
        Uri.parse(
          'com.chessever.app://studies/AbCd1234/chapters/Chapter1?ply=0&v=$version',
        ),
      );

      expect(custom, https);
      expect(https?.studyId, 'AbCd1234');
      expect(https?.chapterId, 'Chapter1');
      expect(https?.ply, 0);
      expect(https?.contentVersion, version);
    });

    test('rejects malformed, ambiguous, and non-public URLs', () {
      final rejected = <String>[
        'http://chessever.com/studies/AbCd1234',
        'https://evil.example/studies/AbCd1234',
        'https://user@chessever.com/studies/AbCd1234',
        'https://chessever.com:444/studies/AbCd1234',
        'https://chessever.com/studies/short',
        'https://chessever.com/studies/AbCd1234/chapters/bad-id',
        'https://chessever.com/studies/AbCd1234?ply=3',
        'https://chessever.com/studies/AbCd1234/chapters/Chapter1?ply=-1',
        'https://chessever.com/studies/AbCd1234?v=SHA256:$version',
        'https://chessever.com/studies/AbCd1234?private=user-1',
        'https://chessever.com/studies/AbCd1234#secret',
        'https://chessever.com/studies/AbCd1234?v=$version&v=$version',
        'com.chessever.app://games/AbCd1234',
      ];

      for (final raw in rejected) {
        expect(StudyPublicLink.tryParse(Uri.parse(raw)), isNull, reason: raw);
      }
    });

    test('constructor rejects invalid IDs, versions, and ply context', () {
      expect(() => StudyPublicLink(studyId: '../private'), throwsArgumentError);
      expect(
        () => StudyPublicLink(studyId: 'AbCd1234', chapterId: 'bad/id'),
        throwsArgumentError,
      );
      expect(
        () => StudyPublicLink(studyId: 'AbCd1234', ply: 0),
        throwsArgumentError,
      );
      expect(
        () => StudyPublicLink(
          studyId: 'AbCd1234',
          contentVersion: 'sha256:not-a-hash',
        ),
        throwsArgumentError,
      );
    });

    test('share text includes only public title, attribution, and URL', () {
      final text = studyShareText(
        link: StudyPublicLink(studyId: 'AbCd1234'),
        title: 'Model games',
      );

      expect(text, contains('Model games'));
      expect(text, contains('Source: Lichess · Shared via ChessEver'));
      expect(text, endsWith('https://chessever.com/studies/AbCd1234'));
      expect(text, isNot(contains('userId')));
      expect(text, isNot(contains('PGN')));
    });
  });
}
