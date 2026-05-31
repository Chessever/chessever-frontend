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

  group('broadcast site URL -> parent event', () {
    test('derives parent event from Lichess broadcast site slug', () {
      expect(
        eventTitleFromBroadcastSite(
          'https://lichess.org/broadcast/5-satranc-365-egitim-kampi-ogrenciler-arasi-yildirim-satranc-turnuvasi/round-7/PoRD5Hrr/FpdAFxZU',
        ),
        '5 Satranc 365 Egitim Kampi Ogrenciler Arasi Yildirim Satranc Turnuvasi',
      );
    });

    test('collapses -- separators in broadcast slug', () {
      expect(
        eventTitleFromBroadcastSite(
          'https://lichess.org/broadcast/35th-drogheda-chess-congress--fox-major/round-3/xyDQsv9C/cwI8k8fj',
        ),
        '35th Drogheda Chess Congress Fox Major',
      );
    });

    test('returns null for non-broadcast sites', () {
      expect(eventTitleFromBroadcastSite('Chess.com'), isNull);
      expect(eventTitleFromBroadcastSite('Oslo, NO'), isNull);
      expect(eventTitleFromBroadcastSite(null), isNull);
    });

    // The decisive real-data case: gamebase player-games rows carry NO
    // tour_id/tournament_id/tourSlug; the PGN Event is a round/pairing label
    // and the parent event survives only in the Lichess `Site` URL.
    test('recovers parent event from site when only a round label exists', () {
      expect(
        preferredTwicEventTitle(
          pgnEvent: 'Round 7: Nazli, Sertan - Akal, Muhammed Furkan',
          tourSlug: null,
          tourId: null,
          site:
              'https://lichess.org/broadcast/5-satranc-365-egitim-kampi-ogrenciler-arasi-yildirim-satranc-turnuvasi/round-7/PoRD5Hrr/FpdAFxZU',
          fallback: 'Gamebase',
        ),
        '5 Satranc 365 Egitim Kampi Ogrenciler Arasi Yildirim Satranc Turnuvasi',
      );
    });
  });
}
