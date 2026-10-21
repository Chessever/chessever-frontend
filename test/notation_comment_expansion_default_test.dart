import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Source-contract coverage for the private board comment renderer. Device
// rendering and gesture acceptance remain separate from these regressions.
void main() {
  final source = File(
    'lib/screens/chessboard/chess_board_screen_new.dart',
  ).readAsStringSync();

  test('unseen comments start expanded without populating an allowlist', () {
    expect(
      source,
      contains('final Set<String> _collapsedCommentIds = <String>{};'),
    );
    expect(
      source,
      contains('final isExpanded = !_collapsedCommentIds.contains(id);'),
    );
    expect(source, isNot(contains('_expandedCommentIds')));
  });

  test('Show less records collapse and Read more removes it', () {
    expect(
      source,
      contains('''if (isExpanded) {
        _collapsedCommentIds.add(id);
      } else {
        _collapsedCommentIds.remove(id);
      }'''),
    );
    expect(source, contains("isExpanded ? '   Show less' : '   Read more'"));
    expect(source, contains('final displayText = (isLong && !isExpanded)'));
  });

  test('changing the notation tree restores expanded comment defaults', () {
    final reset = source.substring(
      source.indexOf('if (_lastSignature != signature)'),
      source.indexOf('final notationParams = NotationTreeParams('),
    );
    expect(reset, contains('_collapsedCommentIds.clear();'));
  });

  test(
    'short comments and comment editing keep their existing tap contract',
    () {
      expect(source, contains('if (!isLong) return;'));
      expect(source, contains('Future<void>.delayed(_commentDoubleTapTimeout'));
      expect(source, contains('onLongPress: openEditor'));
      expect(source, contains('_toggleCommentExpansion(id, isExpanded);'));
    },
  );
}
