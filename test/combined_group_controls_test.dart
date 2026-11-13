import 'package:flutter_test/flutter_test.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_section_labels.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_group_expansion.dart';

void main() {
  test('labels match web dropdown category paths and shared prefixes', () {
    expect(
      combinedSwitcherLabels([
        'Festival | Online Qualifiers | Finals',
        'Festival | Main Event | Open',
      ], groupName: 'Festival'),
      ['Online Qualifiers | Finals', 'Main Event | Open'],
    );
    expect(
      combinedSwitcherLabels([
        'August 13, 2026 — First',
        'August 13, 2026 — Second',
      ]),
      ['First', 'Second'],
    );
    expect(
      combinedSwitcherLabels([
        'FESTIVAL — Open',
        'Festival: Women',
      ], groupName: 'Festival'),
      ['Open', 'Women'],
    );
    expect(combinedSwitcherLabels(['Open', 'Opening']), ['Open', 'Opening']);
    expect(combinedSwitcherLabels(['Festival | A', 'Festival | B']), [
      'A',
      'B',
    ]);
  });
  test('each real source round folds independently and retains its choice', () {
    final state = CombinedGroupExpansion();
    addTearDown(state.dispose);
    state.toggle('tour-a-round-1');
    expect(state.state['tour-a-round-1'], isFalse);
    expect(state.state['tour-b-round-1'] ?? true, isTrue);
    expect(state.state['tour-a-round-2'] ?? true, isTrue);
    state.toggle('tour-b-round-1');
    state.toggle('tour-b-round-1');
    expect(state.state['tour-a-round-1'], isFalse);
    state.toggle('tour-a-round-1');
    expect(state.state['tour-a-round-1'], isTrue);
  });
}
