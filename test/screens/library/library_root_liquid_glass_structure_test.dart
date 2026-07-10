import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current.path;
  final path = 'lib/screens/library/library_screen.dart';

  String readScreen() => File('$root/$path').readAsStringSync();

  test('Library root uses one full-screen canvas with floating controls', () {
    final source = readScreen();

    expect(source, contains('GlassFullScreenPage('));
    expect(source, contains('topOverlay: Align('));
    expect(source, contains('content: Center('));
    expect(source, contains('GlassIslandTopBar('));
    expect(source, contains('GlassIslandSearch('));
    expect(source, isNot(contains('return ScreenWrapper(')));
    expect(source, isNot(contains('children: [_buildTopBar()')));
    expect(source, isNot(contains('SliverAppBar')));
    expect(source, isNot(contains('appBar:')));
  });

  test('Library floating controls are accessible and at least 48pt', () {
    final source = readScreen();

    for (final label in <String>[
      'Open library search',
      'Open Opening Explorer',
      'Open Board Editor',
      'Add to Library',
    ]) {
      expect(source, contains(label), reason: label);
    }

    for (final id in <String>[
      'E2eIds.libraryRoot',
      'E2eIds.librarySearchField',
      'E2eIds.libraryOpeningExplorerButton',
      'E2eIds.libraryBoardEditorButton',
      'E2eIds.libraryCreateFolderButton',
    ]) {
      expect(source, contains(id), reason: id);
    }

    expect(source, contains('collapsedSize: 48'));
    expect(RegExp(r'\bsize:\s*48\s*,').allMatches(source).length, 3);
    expect(RegExp(r'\bsize:\s*40\s*,').hasMatch(source), isFalse);
    expect(source, contains('MediaQuery.textScalerOf(context)'));
    expect(source, contains('GlassMotion.reduceMotion(context)'));
  });

  test('Library workflows remain connected to their existing contracts', () {
    final source = readScreen();

    for (final contract in <String>[
      'libraryFoldersStreamProvider',
      'subscribedBooksProvider',
      'bottomNavBarReTapRequestProvider',
      'AddToLibraryChoice.createDatabase',
      'AddToLibraryChoice.importPgn',
      'AddToLibraryChoice.pickPgnFile',
      'PgnFileIntakeService.instance.ingestPgnFileFromContext',
      'PgnImportPreviewScreen(',
      'FolderContentsScreen(',
      'TwicContentsScreen(',
      'GamebaseExplorerScreen.scoped()',
      'BoardEditorScreen()',
      'RefreshIndicator(',
    ]) {
      expect(source, contains(contract), reason: contract);
    }
  });
}
