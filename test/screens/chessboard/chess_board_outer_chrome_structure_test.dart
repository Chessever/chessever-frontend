import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _section(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, greaterThanOrEqualTo(0), reason: 'Missing $start');
  expect(endIndex, greaterThan(startIndex), reason: 'Missing $end');
  return source.substring(startIndex, endIndex);
}

void main() {
  final boardSource =
      File(
        'lib/screens/chessboard/chess_board_screen_new.dart',
      ).readAsStringSync();
  final bottomControlsSource =
      File(
        'lib/screens/chessboard/widgets/chess_board_bottom_nav_bar.dart',
      ).readAsStringSync();

  test('loaded and loading board pages reserve no material chrome strips', () {
    final gamePage = _section(
      boardSource,
      'class _GamePage',
      'class _LoadingScreen',
    );
    final loadingPage = _section(
      boardSource,
      'class _LoadingScreen',
      'class _BoardTopChrome',
    );

    for (final page in <String>[gamePage, loadingPage]) {
      expect(page, contains('GlassFullScreenPage('));
      expect(page, isNot(contains('appBar:')));
      expect(page, isNot(contains('bottomNavigationBar:')));
      expect(page, isNot(contains('Scaffold(')));
      expect(page, contains('topOverlay:'));
      expect(page, contains('_boardTopContentInset('));
    }

    expect(gamePage, contains('bottomOverlay: _BottomNavBar('));
    expect(gamePage, contains('viewPadding.bottom + bottomControlExtent + 10'));
    expect(
      gamePage,
      contains('isActivePage: currentGameIndex == currentPageIndex'),
      reason: 'Only the visible PageView page may own shared like-flight keys.',
    );
    expect(loadingPage, contains('SingleChildScrollView('));
  });

  test('board top actions are coherent floating glass islands', () {
    final topChrome = _section(
      boardSource,
      'class _BoardTopChrome',
      'class _ResolvedAppBarShareData',
    );
    final topChromeState = _section(
      boardSource,
      'class _BoardTopChromeState',
      'class _TagAwareAppBarActions',
    );

    expect(topChromeState, contains('ScreenshotShareNudge('));
    expect(topChromeState, contains('GlassIslandTopBar('));
    expect(topChromeState, contains('GlassBackButton('));
    expect(topChromeState, contains('GlassTitleChip('));
    expect(topChromeState, contains('GlassContainer('));
    expect(topChromeState, contains('E2eIds.boardGameSelector'));
    expect(topChromeState, contains('_TabletSafePopupMenu<String>('));
    expect(topChromeState, contains("tooltip: 'More game actions'"));
    expect(topChrome, isNot(contains('PreferredSizeWidget')));
    expect(topChromeState, isNot(contains('child: AppBar(')));
  });

  test('board controls are one bounded semantic glass island', () {
    expect(bottomControlsSource, contains('GlassContainer('));
    expect(
      bottomControlsSource,
      contains("ValueKey<String>('board-floating-bottom-controls')"),
    );
    expect(bottomControlsSource, contains("label: 'Chess board controls'"));
    expect(bottomControlsSource, contains("label: 'Flip board'"));
    expect(bottomControlsSource, contains('E2eIds.boardGamebaseToggle'));
    expect(bottomControlsSource, contains('E2eIds.boardEngineToggle'));
    expect(bottomControlsSource, contains('E2eIds.boardMoveBack'));
    expect(bottomControlsSource, contains('E2eIds.boardMoveForward'));
    expect(bottomControlsSource, isNot(contains('SafeArea(')));
    expect(bottomControlsSource, isNot(contains('width: fullWidth')));
    expect(bottomControlsSource, isNot(contains('bottomNavigationBar:')));
  });
}
