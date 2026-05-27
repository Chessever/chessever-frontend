import 'package:chessever2/utils/time_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TimeUtils.formatDateRange', () {
    test(
      'shows a single date when start and end are the same calendar day',
      () {
        final start = DateTime(2026, 5, 23, 9);
        final end = DateTime(2026, 5, 23, 18);

        expect(TimeUtils.formatDateRange(start, end), 'May 23, 2026');
      },
    );

    test('keeps a compact range for multi-day events in the same month', () {
      final start = DateTime(2026, 5, 23);
      final end = DateTime(2026, 5, 25);

      expect(TimeUtils.formatDateRange(start, end), 'May 23 - 25, 2026');
    });
  });
}
