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
      'utm_source is a normalized fallback behind explicit partner keys',
      () {
        expect(
          appsFlyerAffiliateCode({'utm_source': '  RookReview  '}),
          'rookreview',
        );
        expect(
          appsFlyerAffiliateCode({
            'af_sub1': 'original',
            'deep_link_sub1': 'legacy',
            'utm_source': 'other',
          }),
          'original',
        );
        expect(
          appsFlyerAffiliateCode({
            'deep_link_sub1': 'legacy',
            'utm_source': 'other',
          }),
          'legacy',
        );
        expect(
          appsFlyerAffiliateCode({'af_sub1': ' ', 'utm_source': 'partner'}),
          'partner',
        );
        for (final value in ['', 'null', '<invalid>', 'a' * 49]) {
          expect(appsFlyerAffiliateCode({'utm_source': value}), isNull);
        }
      },
    );

    test('utm_source cannot turn an organic install into an affiliate', () {
      final organic = {'utm_source': 'partner', 'af_status': 'Organic'};
      expect(appsFlyerAffiliateCode(organic), 'partner');
      expect(appsFlyerIsNonOrganic(organic), isFalse);
      expect(appsFlyerIsNonOrganic({'utm_source': 'partner'}), isFalse);
    });

    test(
      'deferred utm_source is canonicalized with the original click time',
      () {
        final observed = DateTime.utc(2026, 11, 9, 12);
        final click = observed.subtract(const Duration(days: 1));
        final payload = deferredAppsFlyerAffiliatePayload({
          'is_deferred': true,
          'utm_source': 'RookReview',
          'deep_link_sub2': click.toIso8601String(),
        }, observed)!;
        expect(payload['deep_link_sub1'], 'rookreview');
        expect(appsFlyerAffiliateCode(payload), 'rookreview');
        expect(appsFlyerIsNonOrganic(payload), isTrue);
        expect(payload['install_time'], observed.toIso8601String());
        expect(payload['attribution_at'], click.toIso8601String());
        expect(
          appsFlyerSignupAttributionTime(
            payload: payload,
            accountCreatedAt: click
                .subtract(const Duration(days: 1))
                .toIso8601String(),
            now: observed,
          ),
          isNull,
        );
        expect(
          appsFlyerSignupAttributionTime(
            payload: payload,
            accountCreatedAt: click
                .add(const Duration(hours: 1))
                .toIso8601String(),
            now: observed,
          ),
          click,
        );
      },
    );

    test(
      'deferred callbacks keep explicit partner priority over utm_source',
      () {
        final payload = deferredAppsFlyerAffiliatePayload({
          'is_deferred': true,
          'af_sub1': 'original',
          'deep_link_sub1': 'legacy',
          'utm_source': 'other',
        }, DateTime.utc(2026, 11, 9))!;
        expect(payload['deep_link_sub1'], 'original');
      },
    );

    test('utm_source on a direct app-open cannot establish a new install', () {
      for (final deferred in [false, null]) {
        expect(
          deferredAppsFlyerAffiliatePayload({
            'is_deferred': deferred,
            'utm_source': 'other',
          }, DateTime.utc(2026, 11, 9)),
          isNull,
        );
      }
    });

    test('the first utm_source partner survives later canonical referrals', () {
      final first = {
        'af_status': 'Non-organic',
        'utm_source': 'original',
        'install_time': '2026-11-09T00:00:00Z',
      };
      expect(
        mergeAppsFlyerInstallAttribution(first, {
          'af_status': 'Non-organic',
          'af_sub1': 'other',
          'install_time': '2026-11-10T00:00:00Z',
        }),
        first,
      );
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

    group('new signup eligibility matches the website', () {
      final click = DateTime.utc(2026, 11, 9, 12);
      final now = click.add(const Duration(hours: 1));
      DateTime? eligible({
        DateTime? signup,
        Map? payload,
        DateTime? checkedAt,
      }) => appsFlyerSignupAttributionTime(
        payload: payload ?? {'install_time': click.toIso8601String()},
        accountCreatedAt: (signup ?? click.add(const Duration(minutes: 10)))
            .toIso8601String(),
        now: checkedAt ?? now,
      );

      test('a new account after the referral qualifies', () {
        expect(eligible(), click);
      });

      test('login to an account predating the referral cannot qualify', () {
        expect(
          eligible(signup: click.subtract(const Duration(days: 1))),
          isNull,
        );
      });

      test('a deferred install retains the original website click time', () {
        expect(
          eligible(
            payload: {
              'attribution_at': click.toIso8601String(),
              'install_time': now.toIso8601String(),
            },
          ),
          click,
        );
        expect(
          eligible(
            signup: click.subtract(const Duration(days: 1)),
            payload: {
              'attribution_at': click.toIso8601String(),
              'install_time': now.toIso8601String(),
            },
          ),
          isNull,
        );
      });

      test('the original referral window cannot restart on a later login', () {
        expect(eligible(checkedAt: click.add(const Duration(days: 14))), click);
        expect(
          eligible(
            checkedAt: click.add(const Duration(days: 14, milliseconds: 1)),
          ),
          isNull,
        );
      });

      test('only allows the website five-minute signup clock tolerance', () {
        expect(
          eligible(signup: click.subtract(const Duration(minutes: 5))),
          click,
        );
        expect(
          eligible(
            signup: click.subtract(const Duration(minutes: 5, milliseconds: 1)),
          ),
          isNull,
        );
      });

      test('missing or malformed dates fail closed', () {
        expect(eligible(payload: {}), isNull);
        expect(eligible(payload: {'install_time': 'not-a-date'}), isNull);
        expect(
          appsFlyerSignupAttributionTime(
            payload: {'install_time': click.toIso8601String()},
            accountCreatedAt: 'not-a-date',
            now: now,
          ),
          isNull,
        );
      });

      test(
        'future account and referral dates beyond tolerance are rejected',
        () {
          expect(eligible(signup: now.add(const Duration(minutes: 6))), isNull);
          expect(
            eligible(
              payload: {
                'install_time': now
                    .add(const Duration(minutes: 6))
                    .toIso8601String(),
              },
            ),
            isNull,
          );
          expect(
            eligible(
              signup: now.add(const Duration(minutes: 5)),
              payload: {
                'install_time': now
                    .add(const Duration(minutes: 5))
                    .toIso8601String(),
              },
            ),
            now.add(const Duration(minutes: 5)),
          );
        },
      );
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
