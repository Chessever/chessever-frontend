import 'package:chessever2/services/appsflyer_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppsFlyer attribution helpers', () {
    test('only treats non-organic payloads as affiliate-eligible', () {
      expect(
        appsFlyerIsNonOrganic({
          'af_status': 'Non-organic',
          'af_sub1': 'partner',
        }),
        isTrue,
      );
      expect(
        appsFlyerIsNonOrganic({'af_status': 'Organic', 'af_sub1': 'partner'}),
        isFalse,
      );
      expect(appsFlyerIsNonOrganic({'af_sub1': 'partner'}), isFalse);
    });

    test('extracts affiliate code from supported OneLink fields', () {
      expect(appsFlyerAffiliateCode({'af_sub1': 'gotham'}), 'gotham');
      expect(appsFlyerAffiliateCode({'deep_link_sub1': 'hikaru'}), 'hikaru');
      expect(appsFlyerAffiliateCode({'af_sub1': '  '}), isNull);
    });

    test('parses AppsFlyer install timestamps as UTC', () {
      expect(
        parseAppsFlyerInstallTime('2026-04-20 12:30:10.123')?.toIso8601String(),
        '2026-04-20T12:30:10.123Z',
      );
      expect(
        parseAppsFlyerInstallTime('1776688210123')?.toIso8601String(),
        '2026-04-20T12:30:10.123Z',
      );
    });
  });
}
