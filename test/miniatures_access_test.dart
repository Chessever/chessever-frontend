import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_access.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Fixed "now": Wed 2026-06-03 14:30 local. Free users may open only games
  // whose wall-clock day is Today (2026-06-03); yesterday and older are locked.
  final now = DateTime(2026, 6, 3, 14, 30);

  bool locked(
    DateTime? gameDate, {
    bool isSubscribed = false,
    bool subscriptionLoading = false,
  }) {
    return isMiniatureGameLocked(
      gameDate,
      isSubscribed: isSubscribed,
      subscriptionLoading: subscriptionLoading,
      now: now,
    );
  }

  /// Build a UTC-midnight date matching how Miniatures store bare PGN days.
  DateTime utcDay(int year, int month, int day) =>
      DateTime.utc(year, month, day);

  group('isMiniatureGameLocked — free user Today-only window', () {
    test('game dated today (UTC midnight) is open', () {
      expect(locked(utcDay(2026, 6, 3)), isFalse);
    });

    test('game dated today with a non-midnight timestamp is open', () {
      expect(locked(DateTime.utc(2026, 6, 3, 23, 59)), isFalse);
    });

    test('game dated yesterday is locked', () {
      expect(locked(utcDay(2026, 6, 2)), isTrue);
    });

    test('game dated two days ago is locked', () {
      expect(locked(utcDay(2026, 6, 1)), isTrue);
    });

    test('game dated long ago is locked', () {
      expect(locked(utcDay(2020, 1, 1)), isTrue);
    });

    test('missing / null date is locked', () {
      expect(locked(null), isTrue);
    });
  });

  group('isMiniatureGameLocked — premium and loading bypass', () {
    test('premium user is never locked, even for very old games', () {
      expect(locked(utcDay(2020, 1, 1), isSubscribed: true), isFalse);
    });

    test('premium user is not locked for missing date', () {
      expect(locked(null, isSubscribed: true), isFalse);
    });

    test('while subscription is loading nothing is locked (no flash)', () {
      expect(locked(utcDay(2020, 1, 1), subscriptionLoading: true), isFalse);
    });

    test('loading bypass also covers missing date', () {
      expect(locked(null, subscriptionLoading: true), isFalse);
    });
  });

  group('the Miniatures archive — Today free, earlier days Premium', () {
    test('locks the archive for a free account only', () {
      expect(
        isMiniaturesArchiveLocked(
          isSubscribed: false,
          subscriptionLoading: false,
        ),
        isTrue,
      );
      expect(
        isMiniaturesArchiveLocked(
          isSubscribed: true,
          subscriptionLoading: false,
        ),
        isFalse,
      );
      // No lock flash while the entitlement is still loading.
      expect(
        isMiniaturesArchiveLocked(
          isSubscribed: false,
          subscriptionLoading: true,
        ),
        isFalse,
      );
    });

    test('an archive day is any day before local Today, or no day at all', () {
      expect(isMiniatureArchiveDay(utcDay(2026, 6, 3), now: now), isFalse);
      expect(isMiniatureArchiveDay(utcDay(2026, 6, 2), now: now), isTrue);
      expect(isMiniatureArchiveDay(null, now: now), isTrue);
    });

    test('splits a loaded list at Today, order kept, archive counted', () {
      final loaded = <({String id, DateTime? date})>[
        (id: 'today-a', date: utcDay(2026, 6, 3)),
        (id: 'today-b', date: DateTime.utc(2026, 6, 3, 18)),
        (id: 'yesterday', date: utcDay(2026, 6, 2)),
        (id: 'undated', date: null),
        (id: 'last-year', date: utcDay(2025, 6, 3)),
      ];

      final split = splitMiniaturesAtToday(loaded, (g) => g.date, now: now);

      expect(split.today.map((g) => g.id), ['today-a', 'today-b']);
      expect(split.archived, 3);
    });

    test('a list with nothing from Today yet has no free games', () {
      final split = splitMiniaturesAtToday(
        [utcDay(2026, 6, 1), utcDay(2026, 5, 30)],
        (d) => d,
        now: now,
      );
      expect(split.today, isEmpty);
      expect(split.archived, 2);
    });

    test('a locked list stops paging once the archive is reached', () {
      expect(
        miniaturesPagingStopsAtArchive(
          archiveLocked: true,
          reachedArchive: true,
          newestFirst: true,
        ),
        isTrue,
      );
      // Still inside Today: keep paging for the rest of Today's games.
      expect(
        miniaturesPagingStopsAtArchive(
          archiveLocked: true,
          reachedArchive: false,
          newestFirst: true,
        ),
        isFalse,
      );
      // An open archive always pages.
      expect(
        miniaturesPagingStopsAtArchive(
          archiveLocked: false,
          reachedArchive: true,
          newestFirst: true,
        ),
        isFalse,
      );
      // Out of date order, Today's games can sit on any page.
      expect(
        miniaturesPagingStopsAtArchive(
          archiveLocked: true,
          reachedArchive: true,
          newestFirst: false,
        ),
        isFalse,
      );
    });

    test('the default and phone-filter order is newest first', () {
      expect(
        miniaturesFilterIsNewestFirst(MiniatureGamesFilter.defaultFilter),
        isTrue,
      );
      expect(
        miniaturesFilterIsNewestFirst(
          MiniatureGamesFilter.defaultFilter.copyWith(
            sort: MiniatureGamesSort.rating,
          ),
        ),
        isFalse,
      );
    });

    test('a date range is archive navigation; other filters are not', () {
      const base = MiniatureGamesFilter.defaultFilter;
      expect(miniaturesFilterWalksArchive(base), isFalse);
      expect(
        miniaturesFilterWalksArchive(base.copyWith(maxMoves: 20)),
        isFalse,
      );
      expect(
        miniaturesFilterWalksArchive(base.copyWith(dateFrom: '2024-01-01')),
        isTrue,
      );
      expect(
        miniaturesFilterWalksArchive(base.copyWith(dateTo: '2023-12-31')),
        isTrue,
      );
      expect(
        miniaturesFilterWalksArchive(
          base.copyWith(dateFrom: '2024-01-01').copyWith(clearDates: true),
        ),
        isFalse,
      );
    });
  });
}
