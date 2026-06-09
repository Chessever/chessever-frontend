import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android native regression guards', () {
    test('flutter_soloud remains isolated to the audio service', () {
      final offenders = <String>[];

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final normalizedPath = entity.path.replaceAll('\\', '/');
        if (normalizedPath == 'lib/utils/audio_player_service.dart') continue;

        final source = entity.readAsStringSync();
        if (RegExp(
          r'\b(flutter_soloud|SoLoud|AudioSource|LoadMode)\b',
        ).hasMatch(source)) {
          offenders.add(normalizedPath);
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Keep all SoLoud access inside AudioPlayerService so Android can '
            'be guarded behind the native SoundPool path.',
      );
    });

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

    test('Android native SFX channel is backed by SoundPool', () {
      final source = File(
        'android/app/src/main/kotlin/com/chessEver/app/MainActivity.kt',
      ).readAsStringSync();

      expect(source, contains('"com.chessever/audio_sfx"'));
      expect(source, contains('SoundPool.Builder'));
      expect(source, contains('playNativeSfx'));
    });

    test('Android SoundPool is not eagerly loaded during Activity startup', () {
      final source = File(
        'android/app/src/main/kotlin/com/chessEver/app/MainActivity.kt',
      ).readAsStringSync();
      final onCreate = _methodBody(source, 'override fun onCreate');

      expect(
        onCreate,
        isNot(contains('initSounds()')),
        reason:
            'SFX should lazy-prepare through Dart startup/play paths, not '
            'during Activity.onCreate.',
      );
    });

    test('pubspec keeps .env commented out', () {
      final lines = File('pubspec.yaml').readAsLinesSync();
      final uncommentedEnvAssets = lines.where(
        (line) => line.trimLeft().startsWith('- .env'),
      );

      expect(uncommentedEnvAssets, isEmpty);
      expect(lines.any((line) => line.trim() == '# - .env'), isTrue);
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

String _methodBody(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNonNegative, reason: 'Missing method "$signature".');

  final openBrace = source.indexOf('{', start);
  expect(openBrace, isNonNegative, reason: 'Missing body for "$signature".');

  var depth = 0;
  for (var i = openBrace; i < source.length; i++) {
    final char = source[i];
    if (char == '{') depth++;
    if (char == '}') {
      depth--;
      if (depth == 0) {
        return source.substring(openBrace + 1, i);
      }
    }
  }

  fail('Could not find end of method "$signature".');
}
