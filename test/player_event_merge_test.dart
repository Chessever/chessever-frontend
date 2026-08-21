import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mergePlayerEventsByCanonical', () {
    test('collapses source variants that resolve to one event card', () {
      final merged = mergePlayerEventsByCanonical([
        PlayerEventData(
          tourId: '2026 Titled Tuesday Blitz July 28 Early',
          tourName: '2026 Titled Tuesday Blitz July 28 Early',
          canonicalKey: 'chesscom:titled-tuesday-early:2026-07-28',
          gamesPlayed: 11,
          score: 8.5,
          startDate: DateTime.utc(2026, 7, 28, 15),
          endDate: DateTime.utc(2026, 7, 28, 18),
        ),
        PlayerEventData(
          tourId: 'Titled Tuesday Late Jul 28 2026',
          tourName: 'Titled Tuesday Late Jul 28 2026',
          canonicalKey: 'chesscom:titled-tuesday-late:2026-07-28',
          gamesPlayed: 4,
          score: 2,
          startDate: DateTime.utc(2026, 7, 28, 20),
          endDate: DateTime.utc(2026, 7, 28, 21),
        ),
      ]);

      expect(merged, hasLength(1));
      expect(merged.single.gamesPlayed, 15);
      expect(merged.single.score, 10.5);
      expect(merged.single.startDate, DateTime.utc(2026, 7, 28, 15));
      expect(merged.single.endDate, DateTime.utc(2026, 7, 28, 21));
    });

    test('keeps unrelated dated events separate', () {
      final merged = mergePlayerEventsByCanonical([
        const PlayerEventData(
          tourId: 'Titled Tuesday July 28 2026',
          tourName: 'Titled Tuesday July 28 2026',
          gamesPlayed: 11,
        ),
        const PlayerEventData(
          tourId: 'Titled Tuesday July 14 2026',
          tourName: 'Titled Tuesday July 14 2026',
          gamesPlayed: 8,
        ),
      ]);

      expect(merged, hasLength(2));
    });

    test('does not confuse an opaque canonical key with another title', () {
      final merged = mergePlayerEventsByCanonical([
        const PlayerEventData(
          tourId: 'First Invitational',
          tourName: 'First Invitational',
          canonicalKey: 'second-invitational',
          gamesPlayed: 5,
        ),
        const PlayerEventData(
          tourId: 'Second Invitational',
          tourName: 'Second Invitational',
          canonicalKey: 'different-source-key',
          gamesPlayed: 7,
        ),
      ]);

      expect(merged, hasLength(2));
    });
  });
}
