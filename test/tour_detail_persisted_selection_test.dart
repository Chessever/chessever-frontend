import 'package:chessever2/screens/tour_detail/provider/tour_detail_repo_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parsePersistedTourSelection', () {
    test('reads the JSON payload the repo writes', () {
      const raw =
          '{"tourId":"gVby6S8V","savedAt":"2026-08-19T12:00:00.000Z"}';
      final parsed = parsePersistedTourSelection(raw);
      expect(parsed, isNotNull);
      expect(parsed!.tourId, 'gVby6S8V');
      expect(parsed.savedAt.toUtc(), DateTime.utc(2026, 8, 19, 12));
    });

    test('accepts Map from jsonDecode, not only Map<String, dynamic>', () {
      const raw = '{"tourId":"tour-a","savedAt":"2026-08-19T12:00:00.000Z"}';
      expect(parsePersistedTourSelection(raw)?.tourId, 'tour-a');
    });

    test('rejects legacy plain-string values so they expire', () {
      expect(parsePersistedTourSelection('gVby6S8V'), isNull);
    });
  });

  group('isPersistedTourSelectionFresh', () {
    test('keeps a pick inside the 12-hour window', () {
      final savedAt = DateTime.utc(2026, 8, 19, 1);
      final selection = PersistedTourSelection(
        tourId: 'gVby6S8V',
        savedAt: savedAt,
      );
      expect(
        isPersistedTourSelectionFresh(
          selection,
          now: savedAt.add(const Duration(hours: 11, minutes: 59)),
        ),
        isTrue,
      );
    });

    test('expires a pick after 12 hours', () {
      final savedAt = DateTime.utc(2026, 8, 19, 1);
      final selection = PersistedTourSelection(
        tourId: 'gVby6S8V',
        savedAt: savedAt,
      );
      expect(
        isPersistedTourSelectionFresh(
          selection,
          now: savedAt.add(const Duration(hours: 12, minutes: 1)),
        ),
        isFalse,
      );
    });
  });
}
