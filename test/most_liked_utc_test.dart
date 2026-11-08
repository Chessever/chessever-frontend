import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('same instant has identical UTC windows on every device', () {
    final instant = DateTime.utc(2027, 1, 1, 0, 30);
    for (final period in MostLikedPeriod.values) {
      final utc = MostLikedQuery(period, instant);
      final local = MostLikedQuery(period, instant.toLocal());
      expect(local, utc);
      expect(local.start.isUtc, isTrue);
      expect(local.end.isUtc, isTrue);
      expect(local.start.hour, 0);
      expect(local.end.hour, 0);
      expect(local.window.from.toIso8601String().endsWith('Z'), isTrue);
      expect(local.label(instant.toLocal()), utc.label(instant));
    }
  });

  test('cutoffs have no gap at day, Monday, month and year boundaries', () {
    final boundaries = {
      MostLikedPeriod.today: DateTime.utc(2026, 11, 8),
      MostLikedPeriod.week: DateTime.utc(2026, 11, 9),
      MostLikedPeriod.month: DateTime.utc(2026, 12, 1),
      MostLikedPeriod.year: DateTime.utc(2027),
    };
    for (final entry in boundaries.entries) {
      final before = entry.value.subtract(const Duration(microseconds: 1));
      final old = MostLikedQuery(entry.key, before.toLocal());
      final next = MostLikedQuery(entry.key, entry.value.toLocal());
      expect(old.end, next.start);
      expect(next.start, entry.value);
      expect(old.isCurrent(entry.value.toLocal()), isFalse);
      expect(next.isCurrent(entry.value.toLocal()), isTrue);
      expect(old.next(entry.value.toLocal()), next);
      expect(next.previous, old);
    }
  });

  test('DST days remain exactly 24 hours and weeks exactly seven days', () {
    for (final day in [DateTime.utc(2026, 3, 8), DateTime.utc(2026, 11, 1)]) {
      final today = MostLikedQuery(MostLikedPeriod.today, day.toLocal());
      final week = MostLikedQuery(MostLikedPeriod.week, day.toLocal());
      expect(today.end.difference(today.start), const Duration(days: 1));
      expect(week.end.difference(week.start), const Duration(days: 7));
    }
  });

  test('UTC shared date stays pinned and leap day navigation is retained', () {
    final date = DateTime.parse('2028-02-29T00:00:00Z');
    final query = MostLikedQuery(MostLikedPeriod.today, date);
    expect(query.start, date);
    expect(query.end, DateTime.utc(2028, 3, 1));
    expect(
      mostLikedShareUri(
        MostLikedPeriod.today,
        date: query.start,
      ).queryParameters['date'],
      '2028-02-29',
    );
    expect(
      MostLikedQuery(MostLikedPeriod.today, kMostLikedFirstDay).previous,
      isNull,
    );
  });
}
