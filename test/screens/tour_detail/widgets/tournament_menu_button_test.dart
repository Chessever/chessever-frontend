import 'package:chessever2/screens/tour_detail/widgets/tournament_menu_button.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('areAllVisibleSectionsCollapsed', () {
    test('treats missing round state as expanded by default', () {
      expect(
        areAllVisibleSectionsCollapsed(
          visibleRoundIds: const ['round-1', 'round-2'],
          visibleMatchKeys: const [],
          roundExpansionState: const {},
          matchExpansionState: const {},
        ),
        isFalse,
      );
    });

    test('returns true when every visible round is collapsed', () {
      expect(
        areAllVisibleSectionsCollapsed(
          visibleRoundIds: const ['round-1', 'round-2'],
          visibleMatchKeys: const [],
          roundExpansionState: const {'round-1': false, 'round-2': false},
          matchExpansionState: const {},
        ),
        isTrue,
      );
    });

    test('requires visible knockout matches to be collapsed as well', () {
      expect(
        areAllVisibleSectionsCollapsed(
          visibleRoundIds: const ['round-1'],
          visibleMatchKeys: const ['match-a'],
          roundExpansionState: const {'round-1': false},
          matchExpansionState: const {},
        ),
        isFalse,
      );

      expect(
        areAllVisibleSectionsCollapsed(
          visibleRoundIds: const ['round-1'],
          visibleMatchKeys: const ['match-a'],
          roundExpansionState: const {'round-1': false},
          matchExpansionState: const {'match-a': false},
        ),
        isTrue,
      );
    });
  });
}
