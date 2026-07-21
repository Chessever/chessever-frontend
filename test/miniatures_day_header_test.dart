// Miniatures day-section headers + collapse-driven pagination.
//
// 1) Headers must never show a games counter built from the in-memory group
//    length (partial page undercounts the real day total under the filter).
// 2) After collapse, when content fits the viewport (or is within one
//    viewport of the end), paging must continue while hasMore — same contract
//    as Countrymen / Favorites Games tabs (`miniaturesListNeedsMoreAfterLayout`).
import 'dart:io';

import 'package:chessever2/screens/library/miniatures/miniatures_day_list_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('miniatureDateHeaderLabel', () {
    test('returns the date label only — never a games counter', () {
      expect(miniatureDateHeaderLabel('Today'), 'Today');
      expect(miniatureDateHeaderLabel('Yesterday'), 'Yesterday');
      expect(
        miniatureDateHeaderLabel('Monday, Jan 5, 2026'),
        'Monday, Jan 5, 2026',
      );
    });

    test('does not incorporate an in-memory subset size into the label', () {
      // Old bug: headers used dateGames.length as if it were the full total.
      const partialInMemoryCount = 3;
      final label = miniatureDateHeaderLabel('Today');
      expect(label.contains('$partialInMemoryCount'), isFalse);
      expect(label.toLowerCase().contains('game'), isFalse);
      expect(label.contains('•'), isFalse);
    });
  });

  group('miniaturesListNeedsMoreAfterLayout', () {
    test('true when content fits the viewport (maxScrollExtent <= 0)', () {
      expect(
        miniaturesListNeedsMoreAfterLayout(
          maxScrollExtent: 0,
          pixels: 0,
          viewportDimension: 800,
        ),
        isTrue,
      );
    });

    test('true when within one viewport of the end', () {
      expect(
        miniaturesListNeedsMoreAfterLayout(
          maxScrollExtent: 1000,
          pixels: 300,
          viewportDimension: 800,
        ),
        isTrue,
      );
    });

    test('false when more than one viewport of content remains below', () {
      expect(
        miniaturesListNeedsMoreAfterLayout(
          maxScrollExtent: 2000,
          pixels: 0,
          viewportDimension: 800,
        ),
        isFalse,
      );
    });

    test(
      'matches Countrymen threshold (not the old fixed 200px gap only)',
      () {
        // Old Miniatures check: maxScroll - pixels < 200 → would NOT load
        // (gap is 400). Countrymen: gap <= viewport → MUST load.
        expect(
          miniaturesListNeedsMoreAfterLayout(
            maxScrollExtent: 500,
            pixels: 100,
            viewportDimension: 800,
          ),
          isTrue,
        );
      },
    );

    test(
      'collapse path: needsMore + hasMore drives a single loadNextPage call',
      () async {
        // Mirrors the UI branch in MiniaturesGamesTab._checkScrollAfterLayoutChange.
        final needsMore = miniaturesListNeedsMoreAfterLayout(
          maxScrollExtent: 0,
          pixels: 0,
          viewportDimension: 700,
        );
        expect(needsMore, isTrue);

        var fetchCount = 0;
        var hasMore = true;
        var isLoading = false;
        Future<void> loadNextPage() async {
          if (isLoading || !hasMore) return;
          fetchCount++;
          isLoading = true;
          hasMore = false;
          isLoading = false;
        }

        if (needsMore && hasMore && !isLoading) {
          await loadNextPage();
        }
        expect(fetchCount, 1);

        if (needsMore && hasMore && !isLoading) {
          await loadNextPage();
        }
        expect(fetchCount, 1);
      },
    );
  });

  group('shipped source contract', () {
    test(
      'Miniatures Games tab does not build headers from dateGames.length',
      () {
        final source = File(
          'lib/screens/library/miniatures/miniatures_games_tab.dart',
        ).readAsStringSync();
        expect(source.contains('gameCount: dateGames.length'), isFalse);
        expect(
          source.contains(r"$gameCount ${gameCount == 1 ? 'game' : 'games'}"),
          isFalse,
        );
        expect(source.contains('miniaturesListNeedsMoreAfterLayout'), isTrue);
        expect(source.contains('miniatureDateHeaderLabel'), isTrue);
      },
    );

    test(
      'scorecard date headers follow the same no-in-memory-counter policy',
      () {
        final source = File(
          'lib/screens/library/miniatures/miniature_player_scorecard_screen.dart',
        ).readAsStringSync();
        expect(source.contains('gameCount: dateGames.length'), isFalse);
        expect(
          source.contains(r"$gameCount ${gameCount == 1 ? 'game' : 'games'}"),
          isFalse,
        );
        expect(source.contains('miniaturesListNeedsMoreAfterLayout'), isTrue);
      },
    );
  });
}
