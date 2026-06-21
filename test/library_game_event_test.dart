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
}
