import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('player sharing discovery contract', () {
    test('player profile keeps screenshot sharing without visible share action', () {
      final source = File(
        'lib/screens/player_profile/player_profile_screen.dart',
      ).readAsStringSync();

      expect(source, contains('return ScreenshotShareNudge('));
      expect(source, contains('onShare:'));
      expect(source, isNot(contains('Icons.ios_share')));
      expect(source, contains('semanticsLabel: \'Favorite\''));
    });

    test(
      'event scorecard keeps screenshot sharing and always exposes favorite',
      () {
        final source = File(
          'lib/screens/standings/score_card_screen.dart',
        ).readAsStringSync();

        expect(source, contains('return ScreenshotShareNudge('));
        expect(
          source,
          contains('enabled: hasEventContext && playerGames.isNotEmpty'),
        );
        expect(source, contains('onShare: sharePlayerProfile'));
        expect(source, isNot(contains('Icons.ios_share')));
        expect(source, isNot(contains('onShareProfile')));
        expect(source, isNot(contains('if (isForYouView)')));
        expect(source, contains('semanticsLabel: \'Favorite Icon\''));
      },
    );
  });
}
