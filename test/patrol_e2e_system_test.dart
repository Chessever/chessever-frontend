import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Patrol E2E system wiring', () {
    test('bundles every committed Patrol suite', () {
      final bundle = File('patrol_test/test_bundle.dart').readAsStringSync();

      expect(bundle, contains("import 'onboarding_smoke_test.dart'"));
      expect(bundle, contains("import 'signed_in_smoke_test.dart'"));
      expect(bundle, contains("import 'signed_in_deep_test.dart'"));
      expect(bundle, contains("import 'vasif_regression_smoke_test.dart'"));

      expect(bundle, contains("group('onboarding_smoke_test'"));
      expect(bundle, contains("group('signed_in_smoke_test'"));
      expect(bundle, contains("group('signed_in_deep_test'"));
      expect(bundle, contains("group('vasif_regression_smoke_test'"));
    });

    test('regular runner scripts expose smoke, regression, and deep tiers', () {
      final smoke = File('tool/patrol_smoke.sh').readAsStringSync();
      final regression = File('tool/patrol_regression.sh').readAsStringSync();
      final deep = File('tool/patrol_deep.sh').readAsStringSync();

      expect(smoke, contains('patrol_test/onboarding_smoke_test.dart'));
      expect(smoke, contains('patrol_test/signed_in_smoke_test.dart'));
      expect(
        regression,
        contains('patrol_test/vasif_regression_smoke_test.dart'),
      );
      expect(deep, contains('patrol_test/signed_in_deep_test.dart'));
    });
  });
}
