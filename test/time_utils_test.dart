import 'package:chessever2/utils/time_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TimeUtils.formatDateRange', () {
    test('formats same-day start and end as a single date', () {
      final result = TimeUtils.formatDateRange(
        DateTime(2026, 5, 23, 9),
        DateTime(2026, 5, 23, 18),
      );

      expect(result, 'May 23, 2026');
    });

    test('keeps true multi-day ranges', () {
      final result = TimeUtils.formatDateRange(
        DateTime(2026, 5, 23),
        DateTime(2026, 5, 25),
      );

      expect(result, 'May 23 - 25, 2026');
    });
  });
}
