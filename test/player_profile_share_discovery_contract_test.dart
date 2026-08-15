import 'dart:io';

import 'package:chessever2/screens/standings/providers/player_utils_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('player sharing discovery contract', () {
    test(
      'player profile keeps screenshot sharing without visible share action',
      () {
        final source =
            File(
              'lib/screens/player_profile/player_profile_screen.dart',
            ).readAsStringSync();

        expect(source, contains('return ScreenshotShareNudge('));
        expect(source, contains('onShare:'));
        expect(source, isNot(contains('Icons.ios_share')));
        expect(source, contains('semanticsLabel: \'Favorite\''));
        expect(
          source,
          contains('effectiveFederation: effectiveFederation'),
          reason: 'the profile header should receive the resolved federation',
        );
        expect(
          source,
          contains('FederationFlag('),
          reason: 'the profile header should show the player federation flag',
        );
        expect(
          source,
          contains('formatPlayerDisplayName(effectiveName)'),
          reason: 'the profile header should use the shared natural name order',
        );
      },
    );

    test(
      'event scorecard keeps screenshot sharing and always exposes favorite',
      () {
        final source =
            File(
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
        expect(
          source,
          contains('formatPlayerDisplayName(name)'),
          reason: 'the event scorecard should use First Last display order',
        );
      },
    );
  });

  group('player header display name', () {
    test('converts canonical comma order to natural order', () {
      expect(formatPlayerDisplayName('Aronian, Levon'), 'Levon Aronian');
    });

    test('preserves names already in natural order', () {
      expect(formatPlayerDisplayName('Levon Aronian'), 'Levon Aronian');
    });

    test('preserves multi-part given and family names', () {
      expect(
        formatPlayerDisplayName('Van Foreest, Jorden'),
        'Jorden Van Foreest',
      );
    });
  });
}
