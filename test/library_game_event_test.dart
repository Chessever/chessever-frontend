import 'package:chessever2/repository/library/library_game_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('library game event names', () {
    test('rejects round/player pseudo-events', () {
      expect(
        isReadableLibraryEventName(
          'Round 10: Suleymanli, Aydin - Carlsen, Magnus',
          whiteName: 'Suleymanli, Aydin',
          blackName: 'Carlsen, Magnus',
        ),
        isFalse,
      );
    });

    test('rejects pairing events that omit the versus separator', () {
      // Lichess study-chapter imports join the two "Last, First" names with
      // spaces, not " - "/"vs". The pairing must still be rejected.
      expect(
        isReadableLibraryEventName(
          'Game 1: Wee, Yu Heng Lucas John  Xu, Zhihan (samuel)',
          whiteName: 'Wee, Yu Heng Lucas John',
          blackName: 'Xu, Zhihan (samuel)',
        ),
        isFalse,
      );
      expect(
        isReadableLibraryEventName(
          'Round 6: Batsuren, Dambasuren Ivanchuk, Vasyl',
          whiteName: 'Batsuren, Dambasuren',
          blackName: 'Ivanchuk, Vasyl',
        ),
        isFalse,
      );
    });

    test('keeps real titles that merely contain a colon', () {
      // A genuine event name with a colon must stay readable — it never
      // contains both player names.
      expect(
        isReadableLibraryEventName(
          '100 Repertoires: Semi-Slav',
          whiteName: 'Introduction',
          blackName: 'Welcome!',
        ),
        isTrue,
      );
      expect(
        isReadableLibraryEventName(
          'Round Robin Open: 2026',
          whiteName: 'Carlsen, Magnus',
          blackName: 'Nakamura, Hikaru',
        ),
        isTrue,
      );
    });

    test('prefers canonical event over bad metadata event', () {
      final event = chooseLibraryEventName(
        canonicalEventName:
            'FIDE World Team Rapid & Blitz Chess Championships 2026',
        metadataEvent: 'Round 7: Sargsyan, Shant - Carlsen, Magnus',
        whiteName: 'Sargsyan, Shant',
        blackName: 'Carlsen, Magnus',
      );

      expect(event, 'FIDE World Team Rapid & Blitz Chess Championships 2026');
    });

    test('uses a readable slug instead of an opaque id', () {
      final event = chooseLibraryEventName(
        metadataEvent: 'lD2y4p3R',
        tourSlug: 'fide-world-team-rapid-blitz-chess-championships-2026-rapid',
      );

      expect(
        event,
        'Fide World Team Rapid Blitz Chess Championships 2026 Rapid',
      );
    });

    test('extracts event names from lichess broadcast site urls', () {
      final event = chooseLibraryEventName(
        metadataEvent: 'Round 3: Ivanytska, Liudmyla - Gvetadze, Sofio',
        site:
            'https://lichess.org/broadcast/25th-european-womens-chess-championship-2026/round-3/YQBBvjIH/OrWt33nw',
        whiteName: 'Ivanytska, Liudmyla',
        blackName: 'Gvetadze, Sofio',
      );

      expect(event, '25th European Womens Chess Championship 2026');
    });
  });

  group('gamebase card event names', () {
    test('recovers the tournament from the broadcast site url', () {
      expect(
        resolveGamebaseEventName(
          event: 'Round 12: Firouzja, Alireza - Artemiev, Vladislav',
          site:
              'https://lichess.org/broadcast/fide-world-team-championship-2026/round-12/abcd1234/efgh5678',
          whiteName: 'Firouzja, Alireza',
          blackName: 'Artemiev, Vladislav',
        ),
        'Fide World Team Championship 2026',
      );
    });

    test('drops pairing strings when no tournament is recoverable', () {
      // Broadcast slug anonymised to "-/-" at ingest, Site="?": the real
      // tournament is genuinely gone, so fall back to a generic label rather
      // than leaking the pairing onto the card.
      expect(
        resolveGamebaseEventName(
          event: 'Game 1: Wee, Yu Heng Lucas John  Xu, Zhihan (samuel)',
          site: '?',
          whiteName: 'Wee, Yu Heng Lucas John',
          blackName: 'Xu, Zhihan (samuel)',
        ),
        'Gamebase',
      );
    });

    test('keeps a real TWIC tournament event untouched', () {
      expect(
        resolveGamebaseEventName(
          event: 'Cappelle la Grande',
          site: 'Cappelle la Grande FRA',
          whiteName: 'Karpatchev, Aleksandr',
          blackName: 'Murdzia, Piotr',
        ),
        'Cappelle la Grande',
      );
    });
  });

  // Strings below are verbatim from production Gamebase rows (2026-10-12).
  group('round/pairing labels', () {
    test('every shape Lichess exports is recognised without player names', () {
      for (final label in const [
        'Round 6: Del Rio Baena, Dani - Garcia Canals, Gerard',
        'Round 1: Bytomski, Dominik - Maksymilian Jonda',
        'Rd 9 - Some Pairing',
        'Semifinals | Game 3: Yu, Yangyi - Wang, Hao',
        'Tiebreak 1 | Game 1: Bosc, Seraphina - Navrotescu, Andreea',
      ]) {
        expect(looksLikeRoundPairingEvent(label), isTrue, reason: label);
      }
    });

    test('tournament names are left alone', () {
      for (final name in const [
        'Round Robin Open: 2026',
        'CE Equipos Ajedrez Rapido 2026',
        '2026 Titled Tuesday Blitz October 06',
        'Superfinal (m)',
        'Carlsen vs. Caruana | Speed Chess | QF',
        'Linares',
      ]) {
        expect(looksLikeRoundPairingEvent(name), isFalse, reason: name);
      }
    });
  });

  group('gamebase row event title', () {
    const pairing = 'Round 6: Del Rio Baena, Dani - Garcia Canals, Gerard';
    const site =
        'https://lichess.org/broadcast/catalan-age-group-team-championship-2026-sub-18/round-6/rkYWEnda/R3kJFF30';

    test('the server-resolved name wins over the pairing label', () {
      expect(
        gamebaseRowEventTitle({
          'event': pairing,
          'site': site,
          'canonicalEvent': 'Catalan Age-Group Team Championship 2026',
        }),
        'Catalan Age-Group Team Championship 2026',
      );
    });

    test('falls back to the broadcast site when only the pairing is given', () {
      expect(
        gamebaseRowEventTitle({'event': pairing, 'site': site}),
        'Catalan Age Group Team Championship 2026 Sub 18',
      );
    });

    test('names nothing rather than the pairing', () {
      // `/api/miniatures` rows carry neither a site nor a canonical name.
      expect(gamebaseRowEventTitle({'event': pairing}), isNull);
      expect(gamebaseRowEventTitle({'event': '?'}), isNull);
      expect(gamebaseRowEventTitle(const {}), isNull);
    });

    test('keeps real names, single words included', () {
      expect(gamebaseRowEventTitle({'event': 'Linares'}), 'Linares');
      expect(
        gamebaseRowEventTitle({'event': 'Deutsche Ländermeisterschaft 2026'}),
        'Deutsche Ländermeisterschaft 2026',
      );
    });

    test('ignores nested player objects', () {
      expect(
        gamebaseRowEventTitle({
          'event': pairing,
          'site': site,
          'white': {'name': 'Del Rio Baena, Dani'},
          'black': {'name': 'Garcia Canals, Gerard'},
        }),
        'Catalan Age Group Team Championship 2026 Sub 18',
      );
    });
  });

  group('PGN header event title', () {
    test('uses BroadcastName when Event is the pairing', () {
      expect(
        eventTitleFromPgnHeaders(const {
          'Event': 'Round 6: Del Rio Baena, Dani - Garcia Canals, Gerard',
          'White': 'Del Rio Baena, Dani',
          'Black': 'Garcia Canals, Gerard',
          'BroadcastName': 'Catalan Age-Group Team Championship 2026 Sub 18',
        }),
        'Catalan Age-Group Team Championship 2026 Sub 18',
      );
    });

    test('keeps a real Event and reports none when there is none', () {
      expect(
        eventTitleFromPgnHeaders(const {'Event': 'Chicago Open 2026'}),
        'Chicago Open 2026',
      );
      expect(
        eventTitleFromPgnHeaders(const {
          'Event': 'Round 2: Czech, Emil - Manka, Igor',
        }),
        isNull,
      );
      expect(eventTitleFromPgnHeaders(const {'Event': '?'}), isNull);
    });
  });
}
