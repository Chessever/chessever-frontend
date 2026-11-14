import 'dart:async';

import 'package:chessever2/services/phone_store_upgrader.dart';
import 'package:chessever2/widgets/custom_upgrade_alert.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:upgrader/upgrader.dart';

class _Store extends UpgraderStore {
  int calls = 0;
  bool fail = false;
  Completer<UpgraderVersionInfo>? pending;

  @override
  Future<UpgraderVersionInfo> getVersionInfo({
    required UpgraderState state,
    required dynamic installedVersion,
    required String? country,
    required String? language,
  }) async {
    calls++;
    if (fail) throw StateError('test store unavailable');
    return pending?.future ??
        Future.value(
          UpgraderVersionInfo(
            appStoreVersion: Upgrader.parseVersion('35.25.4', 'test', false),
          ),
        );
  }
}

class _Controller extends UpgraderStoreController {
  _Controller(this.store);
  UpgraderStore? store;

  @override
  UpgraderStore? getUpgraderStore(UpgraderOS os) => store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PhoneStoreUpgrader upgrader;
  late _Store store;
  late _Controller controller;

  setUp(() {
    store = _Store();
    controller = _Controller(store);
    upgrader = PhoneStoreUpgrader(messages: CustomUpgraderMessages());
    upgrader.storeController = controller;
    upgrader.updateState(
      upgrader.state.copyWith(
        packageInfo: PackageInfo(
          appName: 'ChessEver',
          packageName: 'test.phone',
          version: '35.25.3',
          buildNumber: '3504',
        ),
      ),
    );
  });
  tearDown(() => upgrader.dispose());

  test('concurrent checks coalesce into one store request', () async {
    store.pending = Completer<UpgraderVersionInfo>();
    final first = upgrader.updateVersionInfo();
    final second = upgrader.updateVersionInfo();
    expect(identical(first, second), isTrue);
    expect(store.calls, 1);
    store.pending!.complete(
      UpgraderVersionInfo(
        appStoreVersion: Upgrader.parseVersion('35.25.4', 'test', false),
      ),
    );
    expect(await first, isNotNull);
    expect(await second, isNotNull);
    store.pending = null;
    await upgrader.updateVersionInfo();
    expect(store.calls, 2);
  });

  test('throwing store clears old offer; later check can recover', () async {
    await upgrader.updateVersionInfo();
    expect(upgrader.currentAppStoreVersion, '35.25.4');
    store.fail = true;
    expect(await upgrader.updateVersionInfo(), isNull);
    expect(upgrader.versionInfo, isNull);
    store.fail = false;
    await upgrader.updateVersionInfo();
    expect(upgrader.currentAppStoreVersion, '35.25.4');
  });

  test(
    'null check result cannot retain stale info via Upgrader.copyWith',
    () async {
      await upgrader.updateVersionInfo();
      controller.store = null;
      expect(await upgrader.updateVersionInfo(), isNull);
      expect(upgrader.currentAppStoreVersion, isNull);
    },
  );

  test(
    'adapter leaves resume ownership to shell, preventing a second check',
    () async {
      await upgrader.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(store.calls, 0);
    },
  );

  group('PhoneAppStore', () {
    Map<String, Object?> lookup({String? minimumOs}) => {
      'resultCount': 1,
      'results': [
        {
          'version': '39.0.0',
          'trackViewUrl': 'https://apps.apple.com/app/id1',
          'minimumOsVersion': ?minimumOs,
        },
      ],
    };

    Future<UpgraderVersionInfo> check({
      required String device,
      String? minimumOs,
    }) =>
        PhoneAppStore(
          lookup: (state, country, language) async =>
              lookup(minimumOs: minimumOs),
          deviceOsVersion: () => device,
        ).getVersionInfo(
          state: upgrader.state,
          installedVersion: Upgrader.parseVersion('38.11.3', 'test', false),
          country: 'US',
          language: 'en',
        );

    test('reports the store build when this iOS can install it', () async {
      final info = await check(
        device: 'Version 17.4 (Build 21E213)',
        minimumOs: '17.0',
      );
      expect(info.appStoreVersion.toString(), '39.0.0');
      expect(info.appStoreListingURL, 'https://apps.apple.com/app/id1');
    });

    test('hides a build this iOS cannot install', () async {
      final info = await check(
        device: 'Version 16.7.10 (Build 20H350)',
        minimumOs: '17.0',
      );
      expect(info.appStoreVersion, isNull);
      expect(info.appStoreListingURL, isNull);
    });

    test('a missing minimum OS never hides the update', () async {
      final info = await check(device: 'Version 16.1 (Build 20B82)');
      expect(info.appStoreVersion.toString(), '39.0.0');
    });

    test('canInstallOn compares numerically and tolerates gaps', () {
      expect(canInstallOn(deviceOs: 'Version 17.0', minimumOs: '17.0'), isTrue);
      expect(canInstallOn(deviceOs: '16.10', minimumOs: '16.9'), isTrue);
      expect(canInstallOn(deviceOs: '16.4.1', minimumOs: '16.5'), isFalse);
      expect(canInstallOn(deviceOs: '', minimumOs: '17.0'), isTrue);
      expect(canInstallOn(deviceOs: '17.4', minimumOs: null), isTrue);
    });
  });
}
