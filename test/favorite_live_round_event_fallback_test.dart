import 'package:flutter_test/flutter_test.dart';

import 'support/favorite_live_round_test_utils.dart';

void main() {
  group('favorite live round event fallback', () {
    test('sends generic event notification only to starred users without favorites', () {
      final split = splitRoundRecipients(const [
        RecipientCandidate(
          userId: 'starred-user',
          isEventFav: true,
          isPlayerFav: false,
        ),
        RecipientCandidate(
          userId: 'plain-user',
          isEventFav: false,
          isPlayerFav: false,
        ),
      ]);

      expect(split.playerRecipients, isEmpty);
      expect(split.eventRecipients, ['starred-user']);
    });

    test('suppresses generic event fallback when user has favorites in the round', () {
      final split = splitRoundRecipients(const [
        RecipientCandidate(
          userId: 'dual-user',
          isEventFav: true,
          isPlayerFav: true,
        ),
      ]);

      expect(split.playerRecipients, ['dual-user']);
      expect(split.eventRecipients, isEmpty);
    });

    test('does not notify non-starred users for generic event fallback', () {
      final split = splitRoundRecipients(const [
        RecipientCandidate(
          userId: 'non-starred',
          isEventFav: false,
          isPlayerFav: false,
        ),
      ]);

      expect(split.playerRecipients, isEmpty);
      expect(split.eventRecipients, isEmpty);
    });
  });
}

