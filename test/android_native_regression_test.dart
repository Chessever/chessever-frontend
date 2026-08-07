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
      expect(source, contains('Stopwatch()..start()'));
      expect(source, isNot(contains('DateTime.now()')));
      expect(source, contains('handle.isError'));
      expect(source, contains('handle.id <= 0'));
      expect(source, contains('player.getIsValidVoiceHandle(handle)'));
      expect(source, contains('prepareForForegroundPlayback()'));
      expect(source, contains('_recoverAndroidPlayback(type);'));
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
        anchor: 'Future<void> _playWithRecovery',
        first: 'if (Platform.isAndroid)',
        second: '_teardownPlayer();',
        reason:
            'Android failed playback should not start an app-side '
            'deinit/reinit loop.',
      );
    });

    test('chessboard keeps the SFX listener recoverable', () {
      final source =
          File(
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

    // The click-loss fixes that matter to this app landed across 5.5.3
    // (native SDK clears `unprocessedOpenedNotifs` after replaying to a new
    // listener), 5.5.4 (unsubscribe the click listener when the Flutter engine
    // detaches) and 5.5.6 (guard `getNotifications()` in
    // `onDetachedFromEngine`). 5.5.8's `firebase_messaging` fix does not apply
    // here — this app ships `firebase_core` only — so 5.5.6 is the real floor;
    // the guard keeps 5.5.8 as a safe round number above it.
    test('OneSignal keeps Android notification click delivery fix', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final lockfile = File('pubspec.lock').readAsStringSync();
      final constraint = RegExp(
        r'^  onesignal_flutter: \^([0-9]+\.[0-9]+\.[0-9]+)$',
        multiLine: true,
      ).firstMatch(pubspec)?.group(1);
      final locked = RegExp(
        r'  onesignal_flutter:\n(?:.*\n){0,8}?    version: "([0-9]+\.[0-9]+\.[0-9]+)"',
      ).firstMatch(lockfile)?.group(1);

      expect(
        _isAtLeast(constraint, '5.5.8'),
        isTrue,
        reason:
            'OneSignal 5.5.3-5.5.6 fix lost Android notification click events '
            'on engine detach/reattach. The direct constraint must not permit '
            'the affected 5.4.0 SDK.',
      );
      expect(
        _isAtLeast(locked, '5.5.8'),
        isTrue,
        reason:
            'The lockfile must retain the Android notification click delivery '
            'fixes. Keep ios/Podfile.lock in step: the plugin pins an exact '
            'OneSignalXCFramework version, so a stale pod lock fails '
            '`pod install` outright.',
      );

      // PR #290 bumped the Dart package but left ios/Podfile.lock pinned at
      // OneSignalXCFramework 5.4.0, which makes `pod install` fail resolution
      // instead of silently drifting. Keep the two locks moving together.
      final podfileLock = File('ios/Podfile.lock').readAsStringSync();
      final pod =
          RegExp(
            r'^  - OneSignalXCFramework \(([0-9]+\.[0-9]+\.[0-9]+)\):',
            multiLine: true,
          ).firstMatch(podfileLock)?.group(1);

      expect(
        _isAtLeast(pod, '5.5.5'),
        isTrue,
        reason:
            'onesignal_flutter 5.6.7 pins OneSignalXCFramework 5.5.5. Run '
            '`pod update OneSignalXCFramework` in ios/ after bumping the '
            'Dart package, or the iOS build fails to resolve.',
      );
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

bool _isAtLeast(String? version, String minimum) {
  if (version == null) return false;
  final actualParts = version.split('.').map(int.parse).toList();
  final minimumParts = minimum.split('.').map(int.parse).toList();
  for (var index = 0; index < minimumParts.length; index++) {
    if (actualParts[index] != minimumParts[index]) {
      return actualParts[index] > minimumParts[index];
    }
  }
  return true;
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
