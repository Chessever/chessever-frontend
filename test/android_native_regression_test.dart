import 'dart:convert';
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
      final source = File(
        'lib/utils/audio_player_service.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('_prepareAndroidSfx')));
      expect(source, isNot(contains('_playAndroidSfx')));
      expect(source, contains('await SoLoud.instance.init();'));
      expect(source, contains('SoLoud.instance.loadAsset'));
      expect(source, contains('player.play(_resolve(type));'));
      expect(source, contains('Stopwatch()..start()'));
      expect(source, isNot(contains('DateTime.now()')));
      expect(source, contains('handle.isError'));
      expect(source, contains('handle.id <= 0'));
      expect(source, contains('player.getIsValidVoiceHandle(handle)'));
      expect(source, contains('prepareForForegroundPlayback()'));
      expect(
        source,
        matches(
          RegExp(
            r'await _recoverAndroidPlayback\(\s*type,\s*ticket: ticket,\s*'
            r'fallback: fallback,\s*classTicket: classTicket,?'
            // A layered voice (a race loop) threads its playback shape too.
            r'(?:\s*voice: voice,?)?\s*\);',
          ),
        ),
      );
      expect(source, contains('Future<void> _recoverAndroidSfxAssets()'));
      expect(source, contains('Future<void> _reloadAndroidSfxAssets()'));
      expect(
        source,
        contains('Future<void> _waitForAndroidRecoveryIfNeeded()'),
      );
      expect(source, contains('await _waitForAndroidRecoveryIfNeeded();'));
      expect(source, contains('await androidRecovery;'));
      expect(source, contains('final inFlightInitialization = _initializing;'));
      expect(source, contains('await inFlightInitialization;'));
      expect(source, contains('await player.disposeAllSources();'));
      expect(source, contains('bool _isBackgrounded = false;'));
      expect(source, contains('Future<void> _hibernateForBackground()'));
      expect(source, contains('_scheduleBackgroundHibernate();'));
      expect(source, contains('ForegroundTaskScheduler.cancel('));
      expect(source, contains('ForegroundTaskScheduler.schedule('));
      expect(source, contains('if (_isBackgrounded) return;'));
      _expectBefore(
        source,
        anchor: 'void didChangeAppLifecycleState',
        first: '_isBackgrounded = true;',
        second: '_scheduleBackgroundHibernate();',
        reason:
            'Mobile backgrounding must stop new audio work before native '
            'SoLoud callbacks can survive a long sleep.',
      );
      _expectBefore(
        source,
        // Completes with the voice it started, for the race's layered loops.
        anchor: 'Future<SoundHandle?> _playWithRecovery',
        first: 'if (Platform.isAndroid)',
        second: '_teardownPlayer();',
        reason:
            'Android failed playback should not start an app-side '
            'deinit/reinit loop.',
      );
    });

    test('chessboard keeps the SFX listener recoverable', () {
      final source = File(
        'lib/screens/chessboard/chess_board_screen_new.dart',
      ).readAsStringSync();

      expect(source, contains('_audioSub?.closed == false'));
      expect(source, contains('fireImmediately: true'));
      expect(source, contains('_ensureAudioListener(params);'));
      expect(
        source,
        contains('AudioPlayerService.instance.prepareForForegroundPlayback()'),
      );
      expect(source, contains('_currentPageIndex.clamp('));
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

    test('Android native SFX stays scoped to live PiP moves', () {
      final source = File(
        'android/app/src/main/kotlin/com/chessEver/app/MainActivity.kt',
      ).readAsStringSync();

      expect(source, isNot(contains('"com.chessever/audio_sfx"')));
      expect(source, isNot(contains('playNativeSfx')));
      expect(source, isNot(contains('invokeMethod("playSfx"')));
      // Foreground sound stays in the audio service. PiP needs its own pool
      // while Flutter is suspended, guarded by both PiP state and preference.
      expect(
        source,
        matches(
          RegExp(
            r'if \(isCurrentlyInPip\(\) &&\s*'
            r'payload\["soundEnabled"\] == true &&[^{]+\{\s*'
            r'lastSoundedMove = newMove[\s\S]+?playPipSfx\(captured\)',
          ),
        ),
      );
      expect(source, contains('sfxPool?.release()'));
      expect(source, contains('sfxPool = null'));
    });

    test('pubspec keeps .env commented out', () {
      final lines = File('pubspec.yaml').readAsLinesSync();
      final envAssetLines = lines.where(
        (line) => line.trimLeft().contains('- .env'),
      );

      expect(envAssetLines, hasLength(1));
      expect(envAssetLines.single.trimLeft().startsWith('#'), isTrue);
    });

    test('push dependencies no longer include the OneSignal SDK', () {
      expect(
        File('pubspec.yaml').readAsStringSync(),
        isNot(contains('onesignal_flutter:')),
      );
      expect(
        File('pubspec.lock').readAsStringSync(),
        isNot(contains('onesignal_flutter:')),
      );
      expect(
        File('android/app/build.gradle.kts').readAsStringSync(),
        isNot(contains('com.onesignal:OneSignal')),
      );
      for (final path in [
        'ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved',
        'ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved',
      ]) {
        final resolved =
            jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
        expect(
          (resolved['pins'] as List).where(
            (pin) => pin['identity'] == 'onesignal-xcframework',
          ),
          isEmpty,
        );
      }
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

  final firstIndex = searchBackwardsForFirst
      ? source.lastIndexOf(first, anchorIndex)
      : source.indexOf(first, anchorIndex);
  final secondIndex = source.indexOf(second, anchorIndex);

  expect(firstIndex, isNonNegative, reason: 'Missing guard "$first". $reason');
  expect(secondIndex, isNonNegative, reason: 'Missing target "$second".');
  expect(firstIndex, lessThan(secondIndex), reason: reason);
}
