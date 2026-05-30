import 'package:chessever2/screens/player_profile/utils/twic_event_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TWIC event identity', () {
    test('detects round/pairing display labels', () {
      expect(
        isTwicRoundDisplayTitle('Round 13: Yilmaz, Mustafa - Gurel, Ediz'),
        isTrue,
      );
      expect(isTwicRoundDisplayTitle('Rd 9 - Some Pairing'), isTrue);
      expect(
        isTwicRoundDisplayTitle(
          "5. Chess 365 Training Camp Instructors' Chess Tournament",
        ),
        isFalse,
      );
    });

    test('prefers canonical event when PGN Event is only a round label', () {
      expect(
        preferredTwicEventTitle(
          pgnEvent: 'Round 13: Yilmaz, Mustafa - Gurel, Ediz',
          tourSlug: "5. Chess 365 Training Camp Instructors' Chess Tournament",
          tourId: 'twic-event-id',
        ),
        "5. Chess 365 Training Camp Instructors' Chess Tournament",
      );
    });

    test('keeps real PGN event title when it is not a round label', () {
      expect(
        preferredTwicEventTitle(
          pgnEvent: 'Chicago Open 2026',
          tourSlug: 'fallback-event',
          tourId: 'fallback-id',
        ),
        'Chicago Open 2026',
      );
    });
  });
}
