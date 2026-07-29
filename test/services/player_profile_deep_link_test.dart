import 'dart:io';

import 'package:chessever2/services/player_profile_deep_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'parses canonical website player games links with supported filters',
    () {
      final link = parsePlayerProfileDeepLink(
        Uri.parse(
          'https://chessever.com/player/erigaisi-arjun/35009192/games'
          '?time=blitz&result=loss&color=black&eco=b22',
        ),
      );

      expect(link, isNotNull);
      expect(link!.fideId, 35009192);
      expect(link.timeControl, 'blitz');
      expect(link.result, 'loss');
      expect(link.color, 'black');
      expect(link.eco, 'B22');
    },
  );

  test('parses custom-scheme player games links', () {
    final link = parsePlayerProfileDeepLink(
      Uri.parse('com.chessever.app://player/35009192/games?time=rapid'),
    );

    expect(link, isNotNull);
    expect(link!.fideId, 35009192);
    expect(link.timeControl, 'rapid');
  });

  test(
    'rejects malformed ids, unsupported views, and unknown filter values',
    () {
      expect(
        parsePlayerProfileDeepLink(
          Uri.parse('https://chessever.com/player/not-an-id/games'),
        ),
        isNull,
      );
      expect(
        parsePlayerProfileDeepLink(
          Uri.parse('com.chessever.app://player/35009192/about'),
        ),
        isNull,
      );

      final link = parsePlayerProfileDeepLink(
        Uri.parse(
          'com.chessever.app://player/35009192/games'
          '?time=bullet&result=white&color=blue&eco=S99',
        ),
      );
      expect(link, isNotNull);
      expect(link!.timeControl, isNull);
      expect(link.result, isNull);
      expect(link.color, isNull);
      expect(link.eco, isNull);
    },
  );

  test('deep-link routing opens the player profile games tab with filters', () {
    final service =
        File('lib/services/deep_link_service.dart').readAsStringSync();
    final screen =
        File(
          'lib/screens/player_profile/player_profile_screen.dart',
        ).readAsStringSync();

    expect(service, contains('parsePlayerProfileDeepLink(uri)'));
    expect(service, contains('_navigateToPlayerProfile'));
    expect(service, contains('initialDeepLink: profileDeepLink'));
    expect(screen, contains('this.initialDeepLink'));
    expect(screen, contains('_applyInitialDeepLinkFilters'));
  });
}
