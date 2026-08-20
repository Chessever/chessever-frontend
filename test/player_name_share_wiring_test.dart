import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural cover for the three named screens: the app-bar identity is the
/// share control, wired to the existing preview, with no restored share icon
/// and no leftover tap gates.
void main() {
  const screens = <String, String>{
    'player profile': 'lib/screens/player_profile/player_profile_screen.dart',
    'individual scorecard': 'lib/screens/standings/score_card_screen.dart',
    'team scorecard':
        'lib/screens/tour_detail/team_tour/team_score_card_screen.dart',
  };

  test('each named screen taps the identity into showShareImagePreview', () {
    for (final entry in screens.entries) {
      final src = File(entry.value).readAsStringSync();
      expect(
        src.contains('PlayerNameShareTarget'),
        isTrue,
        reason: '${entry.key} must wrap the app-bar name',
      );
      expect(
        src.contains('showShareImagePreview'),
        isTrue,
        reason: '${entry.key} must open the existing Share Preview sheet',
      );
      expect(
        src.contains('Icons.share'),
        isFalse,
        reason: '${entry.key} must not restore a share-icon button',
      );
      expect(
        src.contains('Icons.arrow_outward'),
        isFalse,
        reason: '${entry.key} must not add an extra share glyph',
      );
    }
  });

  test('scorecard name tap is not gated on event context', () {
    final src = File(screens['individual scorecard']!).readAsStringSync();
    expect(src.contains('enableNameActions'), isFalse);
    expect(src.contains('enableNameActions: hasEventContext'), isFalse);
  });

  test('team name tap is not gated on a resolved share URL', () {
    final src = File(screens['team scorecard']!).readAsStringSync();
    expect(src.contains('shareUrl != null'), isFalse);
    expect(src.contains('buildTeamEventShareUrl'), isTrue);
  });
}
