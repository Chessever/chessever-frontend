import 'package:chessever2/widgets/event_card/event_card_meta_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatEventAverageRating', () {
    test('drops the average marker for events spanning different months', () {
      expect(
        formatEventAverageRating(
          elo: 2486,
          startDate: DateTime(2026, 7, 16),
          endDate: DateTime(2026, 8, 1),
        ),
        '2486',
      );
    });

    test('keeps the average marker for events contained in one month', () {
      expect(
        formatEventAverageRating(
          elo: 2486,
          startDate: DateTime(2026, 7, 16),
          endDate: DateTime(2026, 7, 30),
        ),
        'Ø 2486',
      );
    });

    test('keeps the average marker when the date range is incomplete', () {
      expect(
        formatEventAverageRating(
          elo: 2486,
          startDate: DateTime(2026, 7, 16),
          endDate: null,
        ),
        'Ø 2486',
      );
    });
  });
}
