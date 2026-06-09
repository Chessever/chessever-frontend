import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android native regression guards', () {
    test('audio service keeps Android off flutter_soloud init/play/deinit', () {
      final source = File(
        'lib/utils/audio_player_service.dart',
      ).readAsStringSync();

      _expectBefore(
        source,
        anchor: 'Future<void> initializeAndLoadAllAssets',
        first: 'if (Platform.isAndroid)',
        second: '_initializeInternal',
        reason: 'Android asset warmup must prepare native SoundPool, not SoLoud.',
      );
      _expectBefore(
        source,
        anchor: 'void playSound',
        first: 'if (Platform.isAndroid)',
        second: '_playWithRecovery',
        reason: 'Android foreground SFX must play through native SoundPool.',
      );
      _expectBefore(
        source,
        anchor: 'Future<void> _playWithRecovery',
        first: 'if (Platform.isAndroid)',
        second: 'await initializeAndLoadAllAssets();',
        reason: 'Internal recovery calls must still route Android away from SoLoud.',
      );
      _expectBefore(
        source,
        anchor: 'Future<void> _initializeInternal',
        first: 'if (Platform.isAndroid)',
        second: 'await SoLoud.instance.init();',
        reason: 'Android must never enter SoLoud.init().',
      );
      _expectBefore(
        source,
        anchor: 'void _teardownPlayer',
        first: 'if (Platform.isAndroid)',
        second: 'player.deinit();',
        reason: 'Android must never enter SoLoud.deinit().',
      );
    });

    test('root startup does not prewarm Stockfish on Android', () {
      final source = File('lib/main.dart').readAsStringSync();

      _expectBefore(
        source,
        anchor: "key: 'startup_stockfish_warmup'",
        first: 'if (!Platform.isAndroid)',
        second: "key: 'startup_stockfish_warmup'",
        reason: 'Android should not start native Stockfish while the user is idle.',
        searchBackwardsForFirst: true,
      );
    });
  });
}

void _expectBefore(
  String source, {
  required String anchor,
  required String first,
  required String second,
  required String reason,
  bool searchBackwardsForFirst = false,
}) {
  final anchorIndex = source.indexOf(anchor);
  expect(anchorIndex, isNonNegative, reason: 'Missing anchor "$anchor".');

  final firstIndex =
      searchBackwardsForFirst
          ? source.lastIndexOf(first, anchorIndex)
          : source.indexOf(first, anchorIndex);
  final secondIndex = source.indexOf(second, anchorIndex);

  expect(firstIndex, isNonNegative, reason: 'Missing guard "$first". $reason');
  expect(secondIndex, isNonNegative, reason: 'Missing target "$second".');
  expect(firstIndex, lessThan(secondIndex), reason: reason);
}
