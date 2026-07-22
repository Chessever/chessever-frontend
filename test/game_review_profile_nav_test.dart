import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural regression for the Game Analysis → player profile hop.
///
/// Runtime modal + Navigator cannot be driven here per project rules; this
/// test reads the shipped implementation and asserts the keep-open contract:
/// `_openPlayerProfile` must push [PlayerProfileScreen] without dismissing the
/// review sheet first (no `.pop(` in that function body).
void main() {
  test(
    '_openPlayerProfile pushes profile without popping the review sheet',
    () {
      final file = File(
        'lib/screens/chessboard/game_review/game_review_sheet.dart',
      );
      expect(file.existsSync(), isTrue, reason: 'shipped sheet file missing');

      final source = file.readAsStringSync();
      final start = source.indexOf('void _openPlayerProfile(');
      expect(
        start,
        greaterThanOrEqualTo(0),
        reason: '_openPlayerProfile must exist in game_review_sheet.dart',
      );

      final nextTopLevel = source.indexOf('\nString _playerTitleAndLastName(', start);
      expect(
        nextTopLevel,
        greaterThan(start),
        reason: 'could not bound _openPlayerProfile body',
      );

      final body = source.substring(start, nextTopLevel);
      expect(
        body.contains('PlayerProfileScreen('),
        isTrue,
        reason: 'must still open PlayerProfileScreen',
      );
      expect(
        body.contains('.pop('),
        isFalse,
        reason:
            'must not pop the review sheet before opening profile '
            '(sheet should remain open when user returns)',
      );
      expect(
        body.contains('.push(') || body.contains('.push<'),
        isTrue,
        reason: 'must push the profile route',
      );
    },
  );
}
