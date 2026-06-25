import 'package:chessever2/screens/player_profile/utils/twic_event_identity.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
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
          'Quarter Finals | Game 1: Abdusattorov, Nodirbek - Carlsen, Magnus',
        ),
        isTrue,
      );
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

    test('adds cloud parent slug candidates for Chess.com Titled Tuesday', () {
      final candidates = eventNameToBroadcastSlugCandidates(
        '2026 Titled Tuesday Blitz June 23',
      );
      expect(candidates.first, 'titled-tuesday-june-23-2026');
      expect(
        candidates,
        containsAll(<String>[
          '2026-titled-tuesday-blitz-june-23',
          'titled-tuesday-june-23-2026',
        ]),
      );
    });

    test('normalizes abbreviated Titled Tue ordinal dates', () {
      expect(
        eventNameToBroadcastSlugCandidates('Titled Tue 31st Mar 2026'),
        contains('titled-tuesday-march-31-2026'),
      );
    });

    test('keeps zero-padded Titled Tuesday date variant', () {
      expect(
        eventNameToBroadcastSlugCandidates('Titled Tuesday June 09 2026'),
        containsAll(<String>[
          'titled-tuesday-june-9-2026',
          'titled-tuesday-june-09-2026',
        ]),
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

    test('recovers parent event from site for knockout game labels', () {
      expect(
        preferredTwicEventTitle(
          pgnEvent:
              'Quarter Finals | Game 1: Abdusattorov, Nodirbek - Carlsen, Magnus',
          tourSlug:
              'Quarter Finals | Game 1: Abdusattorov, Nodirbek - Carlsen, Magnus',
          tourId:
              'Quarter Finals | Game 1: Abdusattorov, Nodirbek - Carlsen, Magnus',
          site:
              'https://lichess.org/broadcast/norway-chess-2026/round-1/abcd/efgh',
          fallback: 'Gamebase',
        ),
        'Norway Chess 2026',
      );
    });

    test('broadcast site parent wins over phase titles that look useful', () {
      expect(
        preferredTwicEventTitle(
          pgnEvent: 'Carlsen vs. Caruana | Speed Chess | QF',
          tourSlug: 'Carlsen vs. Caruana | Speed Chess | QF',
          tourId: 'Carlsen vs. Caruana | Speed Chess | QF',
          site:
              'https://lichess.org/broadcast/chesscom-speed-chess-championship--knockout-stage/quarterfinals--3/k7cf6T18/FrdyOwpQ',
          fallback: 'Gamebase',
        ),
        'Chesscom Speed Chess Championship Knockout Stage',
      );
    });

    test('canonical game title collapses same knockout event games', () {
      final game1 = _twicGame(
        id: 'g1',
        event:
            'Quarter Finals | Game 1: Abdusattorov, Nodirbek - Carlsen, Magnus',
      );
      final game2 = _twicGame(
        id: 'g2',
        event:
            'Quarter Finals | Game 2: Carlsen, Magnus - Abdusattorov, Nodirbek',
      );

      expect(twicCanonicalEventTitleForGame(game1), 'Norway Chess 2026');
      expect(
        twicCanonicalEventKeyForGame(game1),
        twicCanonicalEventKeyForGame(game2),
      );
    });
  });
}

GamesTourModel _twicGame({required String id, required String event}) {
  final player = PlayerCard(
    name: 'Player',
    federation: '',
    title: '',
    rating: 2700,
    countryCode: '',
    team: null,
  );
  final pgn =
      '[Event "$event"]\n'
      '[Site "https://lichess.org/broadcast/norway-chess-2026/round-1/abcd/efgh"]\n';

  return GamesTourModel(
    gameId: id,
    source: GameSource.twic,
    whitePlayer: player,
    blackPlayer: player,
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.ongoing,
    roundId: 'twic_profile',
    tourId: event,
    tourSlug: event,
    pgn: pgn,
  );
}
