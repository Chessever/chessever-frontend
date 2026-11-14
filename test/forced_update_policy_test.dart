import 'package:chessever2/services/forced_update_policy.dart';
import 'package:chessever2/services/phone_store_upgrader.dart';
import 'package:chessever2/widgets/custom_upgrade_alert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:upgrader/upgrader.dart';

void main() {
  group('requiresMajorUpdate', () {
    bool major(
      String? installed,
      String? offered, [
      ForcedUpdatePolicy policy = ForcedUpdatePolicy.fallback,
    ]) => requiresMajorUpdate(
      installedVersion: installed,
      offeredVersion: offered,
      policy: policy,
    );

    test('a new major version in the store is mandatory by default', () {
      expect(major('38.11.3', '39.0.0'), isTrue);
      expect(major('38.11.3', '40.2.1'), isTrue);
    });

    test('minor and patch releases stay optional', () {
      expect(major('38.11.3', '38.12.0'), isFalse);
      expect(major('38.11.3', '38.11.4'), isFalse);
    });

    test('an older store version is never a major update', () {
      expect(major('39.0.0', '38.12.0'), isFalse);
      expect(major('38.11.3', null), isFalse);
    });

    test('the rule can be switched off remotely', () {
      const off = ForcedUpdatePolicy(forceOnMajor: false);
      expect(major('38.11.3', '39.0.0', off), isFalse);
    });

    test('unreadable versions are never mandatory', () {
      expect(major(null, '39.0.0'), isFalse);
      expect(major('', '39.0.0'), isFalse);
      expect(major('38.11.3', 'not a version'), isFalse);
    });
  });

  group('applyMinAppVersion', () {
    late PhoneStoreUpgrader upgrader;

    setUp(() {
      upgrader = PhoneStoreUpgrader(messages: CustomUpgraderMessages());
      upgrader.updateState(
        upgrader.state.copyWith(
          packageInfo: PackageInfo(
            appName: 'ChessEver',
            packageName: 'test.phone',
            version: '38.11.3',
            buildNumber: '3875',
          ),
        ),
      );
    });

    void storeTag(String? minimum) => upgrader.updateState(
      upgrader.state.copyWith(
        versionInfo: UpgraderVersionInfo(
          appStoreVersion: Upgrader.parseVersion('39.0.0', 'test', false),
          minAppVersion: minimum == null
              ? null
              : Upgrader.parseVersion(minimum, 'test', false),
        ),
      ),
    );

    test('a remote minimum above the install blocks', () {
      applyMinAppVersion(
        upgrader,
        const ForcedUpdatePolicy(minimumVersion: '38.12.0'),
      );
      expect(upgrader.belowMinAppVersion(), isTrue);
      expect(upgrader.blocked(), isTrue);
    });

    test('a short remote minimum reads as major.0.0', () {
      applyMinAppVersion(
        upgrader,
        const ForcedUpdatePolicy(minimumVersion: ' 39 '),
      );
      expect(upgrader.state.minAppVersion.toString(), '39.0.0');
      expect(upgrader.blocked(), isTrue);
    });

    test('the remote minimum overrides the store listing tag', () {
      storeTag('39.0.0');
      applyMinAppVersion(
        upgrader,
        const ForcedUpdatePolicy(minimumVersion: '38.0.0'),
      );
      expect(upgrader.blocked(), isFalse);
    });

    test('clearing the remote minimum hands back to the store tag', () {
      storeTag('39.0.0');
      applyMinAppVersion(
        upgrader,
        const ForcedUpdatePolicy(minimumVersion: '38.0.0'),
      );
      applyMinAppVersion(upgrader, ForcedUpdatePolicy.fallback);
      expect(upgrader.state.minAppVersion, isNull);
      expect(upgrader.blocked(), isTrue);
    });

    test('a typo clears the minimum instead of blocking', () {
      applyMinAppVersion(
        upgrader,
        const ForcedUpdatePolicy(minimumVersion: '38.12.0'),
      );
      applyMinAppVersion(
        upgrader,
        const ForcedUpdatePolicy(minimumVersion: 'soon'),
      );
      expect(upgrader.state.minAppVersion, isNull);
      expect(upgrader.blocked(), isFalse);
    });
  });

  group('forcedUpdatePolicyFrom', () {
    test('unpublished keys give the fallback', () {
      expect(forcedUpdatePolicyFrom(), ForcedUpdatePolicy.fallback);
    });

    test('blank minimum means none', () {
      expect(forcedUpdatePolicyFrom(minimumVersion: '  ').minimumVersion, null);
    });

    test('minimum is trimmed', () {
      expect(
        forcedUpdatePolicyFrom(minimumVersion: ' 38.12.0\n').minimumVersion,
        '38.12.0',
      );
    });

    test('only an explicit false or 0 turns the major rule off', () {
      for (final off in ['false', 'FALSE', ' 0 ']) {
        expect(forcedUpdatePolicyFrom(forceOnMajor: off).forceOnMajor, isFalse);
      }
      for (final on in ['true', '1', '', 'yes', 'flase']) {
        expect(forcedUpdatePolicyFrom(forceOnMajor: on).forceOnMajor, isTrue);
      }
    });
  });
}
