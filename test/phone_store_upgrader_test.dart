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
}
