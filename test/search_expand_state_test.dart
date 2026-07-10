import 'package:chessever2/widgets/liquid_glass/search_expand_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SearchExpandState', () {
    test('starts collapsed with empty query', () {
      const s = SearchExpandState();
      expect(s.expanded, isFalse);
      expect(s.query, isEmpty);
      expect(s.hasQuery, isFalse);
    });

    test('expand / collapse / toggle', () {
      var s = const SearchExpandState();
      s = s.expand();
      expect(s.expanded, isTrue);
      s = s.collapse();
      expect(s.expanded, isFalse);
      s = s.toggle();
      expect(s.expanded, isTrue);
      s = s.toggle();
      expect(s.expanded, isFalse);
    });

    test('collapse can clear query', () {
      final s = const SearchExpandState(expanded: true, query: 'magnus')
          .collapse(clearQuery: true);
      expect(s.expanded, isFalse);
      expect(s.query, isEmpty);
    });

    test('copyWith preserves fields', () {
      final s = const SearchExpandState(expanded: true, query: 'a')
          .copyWith(query: 'ab');
      expect(s.expanded, isTrue);
      expect(s.query, 'ab');
    });
  });

  group('searchExpandTargetWidth', () {
    test('collapsed returns circle size', () {
      expect(
        searchExpandTargetWidth(
          available: 300,
          expanded: false,
          collapsedSize: 40,
        ),
        40,
      );
    });

    test('expanded fills available width', () {
      expect(
        searchExpandTargetWidth(
          available: 300,
          expanded: true,
          collapsedSize: 40,
        ),
        300,
      );
    });
  });

  group('searchExpandWidthFactor', () {
    test('clamps progress', () {
      expect(searchExpandWidthFactor(-1), 0);
      expect(searchExpandWidthFactor(0.5), 0.5);
      expect(searchExpandWidthFactor(2), 1);
    });
  });
}
