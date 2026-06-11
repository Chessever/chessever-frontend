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
            'Keep all direct SoLoud access inside AudioPlayerService so the '
            'package lifecycle is centralized.',
      );
    });

    test('audio service uses flutter_soloud init/play lifecycle', () {
      final source =
          File('lib/utils/audio_player_service.dart').readAsStringSync();

      expect(source, isNot(contains('_prepareAndroidSfx')));
      expect(source, isNot(contains('_playAndroidSfx')));
      expect(source, contains('await SoLoud.instance.init();'));
      expect(source, contains('SoLoud.instance.loadAsset'));
      expect(source, contains('player.play(_resolve(type));'));
      _expectBefore(
        source,
        anchor: 'Future<void> _playWithRecovery',
        first: 'if (Platform.isAndroid)',
        second: '_teardownPlayer();',
        reason:
            'Android failed playback should not start an app-side '
            'deinit/reinit loop.',
      );
    });

    test('root startup does not prewarm Stockfish on Android', () {
      final source = File('lib/main.dart').readAsStringSync();

      _expectBefore(
        source,
        anchor: "key: 'startup_stockfish_warmup'",
        first: 'if (!Platform.isAndroid)',
        second: "key: 'startup_stockfish_warmup'",
        reason:
            'Android should not start native Stockfish while the user is idle.',
        searchBackwardsForFirst: true,
      );
    });

    test('Android native code does not own SFX playback', () {
      final source =
          File(
            'android/app/src/main/kotlin/com/chessEver/app/MainActivity.kt',
          ).readAsStringSync();

      expect(source, isNot(contains('"com.chessever/audio_sfx"')));
      expect(source, isNot(contains('SoundPool')));
      expect(source, isNot(contains('playNativeSfx')));
      expect(source, contains('invokeMethod("playSfx"'));
    });

    test('pubspec keeps .env commented out', () {
      final lines = File('pubspec.yaml').readAsLinesSync();
      final envAssetLines = lines.where(
        (line) => line.trimLeft().contains('- .env'),
      );

      expect(envAssetLines, hasLength(1));
      expect(envAssetLines.single.trimLeft().startsWith('#'), isTrue);
    });

    test('Codemagic dart defines include Gamebase API key', () {
      final source = File('CODEMAGIC_DART_DEFINES.txt').readAsStringSync();

      expect(
        source,
        contains('--dart-define=GAMEBASE_API_KEY="\$GAMEBASE_API_KEY"'),
        reason:
            'Release builds must pass GAMEBASE_API_KEY because GamebaseRepository '
            'reads it with String.fromEnvironment.',
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
