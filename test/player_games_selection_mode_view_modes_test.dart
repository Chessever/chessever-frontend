import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// "Save to Library" -> "Choose games manually" turns on selection mode for the
/// Player Profile Games tab. The tab renders games in three view modes
/// (`GamesListViewMode.gamesCard`, `.chessBoard`, `.chessBoardGrid`) and every
/// one of them must show the selection badge and toggle on tap. Board and grid
/// cards shipped without it, so selection silently did nothing outside the
/// regular card mode.
void main() {
  late String source;

  setUpAll(() {
    source =
        File(
          'lib/screens/player_profile/tabs/player_games_tab.dart',
        ).readAsStringSync();
  });

  test('every view mode wraps its card in the selection wrapper', () {
    final regions = {
      'regular card mode': _between(
        source,
        'if (entry is _PlayerCardGameEntry) {',
        'if (entry is _PlayerPaginationFooterEntry) {',
      ),
      'chess board mode': _between(
        source,
        'if (entry is _PlayerBoardGameEntry) {',
        'if (entry is _PlayerCardGameEntry) {',
      ),
      'grid mode': _between(
        source,
        'Widget _buildGridGame(',
        'Widget _buildSelectableCardWrapper(',
      ),
    };

    for (final entry in regions.entries) {
      expect(
        entry.value,
        contains('_buildSelectableCardWrapper('),
        reason:
            '${entry.key} must render the selection badge while selection '
            'mode is on',
      );
      expect(
        entry.value,
        contains('_toggleGameSelection('),
        reason: '${entry.key} must toggle selection when a game is tapped',
      );
      expect(
        entry.value,
        contains('isSelectionMode'),
        reason: '${entry.key} must branch on selection mode',
      );
    }
  });

  test('grid cells receive the selection flag from the list builder', () {
    expect(
      _between(source, 'Widget _buildGridGame(', ') {'),
      contains('required bool isSelectionMode'),
      reason:
          'grid cells are built in a helper, so the flag has to be plumbed '
          'through instead of read from an outer scope',
    );
    expect(
      _between(source, 'if (entry is _PlayerGridRowEntry) {', 'if (entry is'),
      contains('isSelectionMode: isSelectionMode'),
      reason: 'the grid row builder must forward selection mode to each cell',
    );
  });

  test('the wrapper intercepts card gestures while selecting', () {
    final wrapper = _between(
      source,
      'Widget _buildSelectableCardWrapper(',
      'Widget _buildPaginationFooter(',
    );

    expect(
      wrapper,
      contains('VoidCallback? onTap'),
      reason:
          'board and grid cards navigate on their own tap, so the wrapper has '
          'to take over the gesture',
    );
    expect(
      wrapper,
      contains('HitTestBehavior.opaque'),
      reason:
          'the overlay must swallow taps and long-presses before the card '
          'opens the chessboard or its context menu',
    );
  });

  test('selection chrome is painted over the card, never around it', () {
    final wrapper = _between(
      source,
      'Widget _buildSelectableCardWrapper(',
      'Widget _buildPaginationFooter(',
    );

    expect(
      wrapper,
      isNot(contains('child: child')),
      reason:
          'a decorated parent with a Border inflates the card by the border '
          'width and re-lays it out; grid cells have a fixed-width board row, '
          'so that overflowed the RenderFlex by 1.2px',
    );
    expect(
      wrapper,
      contains('IgnorePointer'),
      reason:
          'the border/glow layer sits above the card, so it must not eat the '
          'gestures meant for the selection overlay underneath it',
    );
  });
}

String _between(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  expect(startIndex, isNot(-1), reason: 'missing marker: $start');
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(endIndex, isNot(-1), reason: 'missing marker: $end (after $start)');
  return source.substring(startIndex, endIndex);
}
