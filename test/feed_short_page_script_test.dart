// The Shorts players' page runs its own script: it is what keeps a Short
// playing (asks again, falls back to muted, asks for its sound back) and
// what leaves a Short the viewer paused alone. A widget test cannot run it,
// so it is run under Node against a stand-in for YouTube's player
// (test/support/feed_short_page.js). Skipped where Node is not installed.

import 'dart:io';

import 'package:chessever2/screens/feed/widgets/feed_short_player.dart';
import 'package:flutter_test/flutter_test.dart';

bool _hasNode() {
  try {
    return Process.runSync('node', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  test(
    "the players' page plays, asks again and falls back as written",
    () async {
      final dir = await Directory.systemTemp.createTemp('feed_short_page');
      addTearDown(() => dir.delete(recursive: true));
      final page = File('${dir.path}/page.html')
        ..writeAsStringSync(
          feedShortPlayerHtml(Uri.parse('https://embed.test.example.com')),
        );
      final result = await Process.run('node', [
        'test/support/feed_short_page.js',
        page.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      // Every scene ran and none was skipped over.
      final scenes = '${result.stdout}'.trim().split('\n');
      expect(scenes.length, greaterThanOrEqualTo(18));
      expect(scenes.every((scene) => scene.startsWith('ok ')), isTrue);
    },
    skip: _hasNode() ? false : 'Node is not installed',
  );
}
