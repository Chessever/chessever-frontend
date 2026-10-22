import 'package:chessever2/services/appsflyer_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppsFlyer attribution helpers', () {
    test(
      'a website handoff retains its first qualifying time without changing the actual install time',
      () {
        final payload = deferredAppsFlyerAffiliatePayload({
          'is_deferred': true,
          'deep_link_sub1': 'rookreview',
          'deep_link_sub2': '2026-10-10T00:00:00Z',
        }, DateTime.utc(2026, 10, 22))!;
        expect(payload['install_time'], '2026-10-22T00:00:00.000Z');
        expect(payload['attribution_at'], '2026-10-10T00:00:00.000Z');
        final future = deferredAppsFlyerAffiliatePayload({
          'is_deferred': true,
          'deep_link_sub1': 'rookreview',
          'deep_link_sub2': '2027-01-01T00:00:00Z',
        }, DateTime.utc(2026, 10, 22))!;
        expect(future.containsKey('attribution_at'), isFalse);
      },
    );

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

    test(
      'accepts privacy restricted deferred UDL with only deep_link_sub1',
      () {
        final observed = DateTime.utc(2026, 10, 22);
        final payload = deferredAppsFlyerAffiliatePayload({
          'is_deferred': true,
          'deep_link_sub1': 'RookReview',
        }, observed)!;
        expect(appsFlyerAffiliateCode(payload), 'rookreview');
        expect(appsFlyerIsNonOrganic(payload), isTrue);
        expect(payload['install_time'], observed.toIso8601String());
        expect(
          deferredAppsFlyerAffiliatePayload({
            'is_deferred': false,
            'deep_link_sub1': 'other',
          }, observed),
          isNull,
        );
        expect(
          deferredAppsFlyerAffiliatePayload({
            'deep_link_sub1': 'other',
          }, observed),
          isNull,
        );
        expect(
          deferredAppsFlyerAffiliatePayload({
            'is_deferred': true,
            'deep_link_sub1': '<invalid>',
          }, observed),
          isNull,
        );
      },
    );
    test(
      'callback order cannot erase or replace the first partner or restart its window',
      () {
        final first = {
          'af_status': 'Non-organic',
          'deep_link_sub1': 'rookreview',
          'install_time': '2026-10-20T00:00:00Z',
        };
        expect(
          mergeAppsFlyerInstallAttribution(first, {'af_status': 'Organic'}),
          first,
        );
        expect(
          mergeAppsFlyerInstallAttribution(first, {
            'af_status': 'Non-organic',
            'af_sub1': 'other',
          }),
          first,
        );
        expect(
          mergeAppsFlyerInstallAttribution({
            'af_status': 'Organic',
            'install_time': '2026-10-19T00:00:00Z',
          }, first)['install_time'],
          '2026-10-19T00:00:00Z',
        );
      },
    );

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
