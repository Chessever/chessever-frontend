import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final root = Directory.current.path;
  final screenPaths = <String>[
    'lib/screens/library/book_preview_screen.dart',
    'lib/screens/library/folder_contents_screen.dart',
    'lib/screens/library/pgn_import_preview_screen.dart',
    'lib/screens/library/twic_contents_screen.dart',
  ];

  String read(String path) => File('$root/$path').readAsStringSync();

  test('library detail pages use floating full-screen glass chrome', () {
    for (final path in screenPaths) {
      final source = read(path);

      expect(source, contains('GlassFullScreenPage('), reason: path);
      expect(source, isNot(contains('return Scaffold(')), reason: path);
      expect(source, isNot(contains('ScreenWrapper(')), reason: path);
      expect(source, isNot(contains('SliverAppBar')), reason: path);
      expect(source, isNot(contains('appBar:')), reason: path);
      expect(RegExp(r'\bIconButton\(').hasMatch(source), isFalse, reason: path);
      expect(
        RegExp(r'\bsize:\s*40\s*,').hasMatch(source),
        isFalse,
        reason: '$path must keep outer icon controls at least 48px',
      );
    }
  });

  test('search and filter chrome uses the glass kit', () {
    for (final path in screenPaths.skip(1)) {
      final source = read(path);
      expect(source, contains('GlassSearchBar('), reason: path);
    }

    final folder = read(screenPaths[1]);
    final twic = read(screenPaths[3]);
    expect(folder, contains('GlassChip('));
    expect(folder, contains('GlassBadge('));
    expect(twic, contains('GlassChip('));
    expect(twic, contains('GlassBadge('));
  });

  test('custom library motion honors Reduce Motion', () {
    for (final path in screenPaths.skip(1)) {
      expect(read(path), contains('GlassMotion.reduceMotion'), reason: path);
    }
  });
}
