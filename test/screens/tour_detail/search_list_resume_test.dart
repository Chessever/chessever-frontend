import 'package:chessever2/screens/tour_detail/games_tour/widgets/search_list_resume.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// The Games list across a search: the reader's place in every game is kept
/// while the hits stand in for it, and handed back as the search ends.

class _Positions implements ItemPositionsListener {
  @override
  final ValueNotifier<Iterable<ItemPosition>> itemPositions =
      ValueNotifier<Iterable<ItemPosition>>(const []);

  void show(List<(int, double, double)> items) => itemPositions.value = [
    for (final (index, leading, trailing) in items)
      ItemPosition(
        index: index,
        itemLeadingEdge: leading,
        itemTrailingEdge: trailing,
      ),
  ];
}

void main() {
  group('ListResumePoint.capture', () {
    test('takes the first item still on screen, as it sits', () {
      final positions = _Positions()
        ..show([(9, 0.2, 0.5), (7, -0.3, -0.05), (8, -0.05, 0.2)]);
      expect(
        ListResumePoint.capture(positions),
        const ListResumePoint(index: 8, alignment: -0.05),
      );
    });

    test('a list at its top, or never laid out, has nothing to keep', () {
      final positions = _Positions();
      expect(ListResumePoint.capture(positions), isNull);
      positions.show([(0, 0.01, 0.3), (1, 0.3, 0.6)]);
      expect(ListResumePoint.capture(positions), isNull);
    });

    test('clamps to a shorter list', () {
      const point = ListResumePoint(index: 40, alignment: -0.1);
      expect(
        point.clampedTo(12),
        const ListResumePoint(index: 11, alignment: -0.1),
      );
    });
  });

  group('SearchListResume', () {
    test('hands the place back once the hits have gone, once', () {
      final positions = _Positions()..show([(20, -0.1, 0.2), (21, 0.2, 0.5)]);
      final resume = SearchListResume();

      // Every game, read from the reader's place: nothing to restore.
      expect(resume.resolve(searching: false, positions: positions), isNull);
      // The hits come in, from their top; the place is kept.
      expect(resume.resolve(searching: true, positions: positions), isNull);
      positions.show([(0, 0.0, 0.3)]);
      expect(resume.resolve(searching: true, positions: positions), isNull);

      // The search ends: every game, where the reader was.
      const place = ListResumePoint(index: 20, alignment: -0.1);
      expect(resume.resolve(searching: false, positions: positions), place);
      // Every build of that list says the same until it is built.
      expect(resume.resolve(searching: false, positions: positions), place);
      resume.consumed();
      expect(resume.resolve(searching: false, positions: positions), isNull);
    });

    test('a new search keeps the place the reader is in now', () {
      final positions = _Positions()..show([(5, -0.2, 0.1)]);
      final resume = SearchListResume()
        ..resolve(searching: false, positions: positions)
        ..resolve(searching: true, positions: positions);
      expect(
        resume.resolve(searching: false, positions: positions),
        const ListResumePoint(index: 5, alignment: -0.2),
      );
      resume.consumed();

      positions.show([(30, -0.4, 0.05), (31, 0.05, 0.3)]);
      resume.resolve(searching: true, positions: positions);
      expect(
        resume.resolve(searching: false, positions: positions),
        const ListResumePoint(index: 30, alignment: -0.4),
      );
    });
  });
}
