import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/navigation/space_shortcut_navigator.dart'
    show resolveSpaceLine;
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:chessever2/widgets/search/search_overlay_widget.dart';
import 'package:flutter_test/flutter_test.dart';

SpaceShortcut _draftFor(OpeningSearchSuggestion suggestion) =>
    openingSearchSpaceDraft(suggestion.selection, name: suggestion.fullTitle);

void main() {
  test('named lines sharing one ECO code pin as distinct positions', () {
    final lines = searchOpeningSuggestions('Najdorf')
        .where((s) => s.filter.code == 'B90' && !s.isAggregate)
        .toList(growable: false);
    expect(lines.length, greaterThan(1));

    final drafts = lines.map(_draftFor).toList(growable: false);
    for (final draft in drafts) {
      expect(draft.kind, SpaceShortcutKind.position);
      expect(draft.key, isNot('opening:B90'));
    }
    expect(drafts.map((d) => d.key).toSet(), hasLength(drafts.length));
  });

  test('a named line pins the exact line it names', () {
    final line = searchOpeningSuggestions('English Attack').firstWhere(
      (s) => s.filter.code == 'B90' && !s.isAggregate,
    );
    final draft = _draftFor(line);
    final resolved = resolveSpaceLine(moves: line.movePath)!;

    // The same FEN identity the explorer and board notation pins use, and
    // the full UCI line the position opener replays.
    expect(draft.targetId, resolved.fen);
    expect(draft.params['moves'], resolved.ucis);
    expect(resolved.ucis, hasLength(line.movePath.length));
  });

  test('aggregate code and family rows keep the bare code key', () {
    final code = openingSearchSpaceDraft(
      OpeningSearchSelection.forFilter(GameEcoFilter.forCode('B90')),
      name: 'Sicilian, Najdorf',
    );
    expect(code.key, 'opening:B90');

    final family = searchOpeningSuggestions('Najdorf').firstWhere(
      (s) => s.isFamily,
    );
    final familyDraft = _draftFor(family);
    expect(familyDraft.kind, SpaceShortcutKind.opening);
    expect(familyDraft.targetId, family.codeLabel);
  });

  test('a named line whose moves do not replay falls back to its code', () {
    // The catalog carries a few long-algebraic moves ("Ne2-g3"); a partial
    // replay must never be saved as a shallower position.
    final draft = openingSearchSpaceDraft(
      OpeningSearchSelection(
        filter: GameEcoFilter.forCode('C15'),
        hierarchyLabel: 'French › Winawer › Alatortsev variation',
        movePath: const ['e4', 'e6', 'd4', 'd5', 'Nc3', 'Bb4', 'Ne2-g3'],
        isAggregate: false,
      ),
      name: 'French, Winawer, Alatortsev variation',
    );
    expect(draft.key, 'opening:C15');
  });
}
