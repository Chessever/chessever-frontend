import 'package:chessever2/services/deep_link_service.dart';
import 'package:chessever2/services/direct_push_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a collection push names its count once the collection is open', () {
    test('with the title and the count', () {
      expect(
        collectionPushArrivalMessage(added: 4, title: 'Best of 2026'),
        '4 new games just landed in Best of 2026.',
      );
      expect(
        collectionPushArrivalMessage(added: 1, title: 'Best of 2026'),
        '1 new game just landed in Best of 2026.',
      );
      expect(
        collectionPushArrivalMessage(added: 12480, title: 'Mega 2026'),
        '12,480 new games just landed in Mega 2026.',
      );
    });

    test('without a title', () {
      expect(
        collectionPushArrivalMessage(added: 3, title: ' '),
        '3 new games just landed.',
      );
    });

    test('a push with no count says nothing extra', () {
      expect(collectionPushArrivalMessage(added: null, title: 'X'), isNull);
      expect(collectionPushArrivalMessage(added: 0, title: 'X'), isNull);
    });

    test('a collection that cannot open says so', () {
      expect(
        collectionPushFailedMessage('Best of 2026'),
        'Best of 2026 could not be opened right now.',
      );
      expect(
        collectionPushFailedMessage(null),
        'That collection could not be opened right now.',
      );
    });
  });

  group('the phone reports its timezone with its registration', () {
    test('IANA names pass; abbreviations and bare offsets do not', () {
      for (final zone in [
        'Europe/Berlin',
        'Asia/Baku',
        'America/Argentina/Buenos_Aires',
        'America/Port-au-Prince',
        'Etc/GMT-4',
        'UTC',
      ]) {
        expect(DirectPushService.isIanaTimezone(zone), isTrue, reason: zone);
      }
      for (final zone in [
        'CET',
        'GMT+03:00',
        '+04',
        '',
        'Europe/',
        '/Berlin',
      ]) {
        expect(DirectPushService.isIanaTimezone(zone), isFalse, reason: zone);
      }
    });

    test('a platform that fails or answers oddly sends no zone', () async {
      expect(
        await DirectPushService.deviceTimezone(read: () async => 'Asia/Baku'),
        'Asia/Baku',
      );
      expect(
        await DirectPushService.deviceTimezone(read: () async => 'GMT+04:00'),
        isNull,
      );
      expect(
        await DirectPushService.deviceTimezone(
          read: () async => throw StateError('no channel'),
        ),
        isNull,
      );
    });
  });
}
