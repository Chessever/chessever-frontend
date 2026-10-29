import 'dart:async';

import 'package:chessever2/screens/feed/news/news_reading_access.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'a paid or rewarded session bypasses the gate; expiry restores the allowance',
    () async {
      final access = NewsReadingAccess();
      var premium = false;
      var prompts = 0;
      Future<bool> open(String key) => access.open(
        key,
        hasPremium: () => premium,
        requestPremium: () async {
          prompts++;
          premium = true;
          return true;
        },
      );
      for (var i = 0; i < 3; i++) {
        expect(await open('$i'), isTrue);
      }
      expect(prompts, 0);
      expect(await open('3'), isTrue);
      expect(prompts, 1);
      for (var i = 4; i < 12; i++) {
        expect(await open('$i'), isTrue);
      }
      expect(prompts, 1);
      premium = false;
      for (var i = 12; i < 15; i++) {
        expect(await open('$i'), isTrue);
      }
      expect(prompts, 1);
      expect(await open('15'), isTrue);
      expect(prompts, 2);
    },
  );

  test(
    'publisher keys are distinct and a failed prompt can be retried',
    () async {
      final access = NewsReadingAccess();
      var prompts = 0;
      Future<bool> open(String key) => access.open(
        key,
        hasPremium: () => false,
        requestPremium: () async {
          prompts++;
          if (prompts == 1) throw StateError('unavailable');
          return false;
        },
      );
      for (final key in ['1', 'rookreview:1', '2']) {
        expect(await open(key), isTrue);
      }
      await expectLater(open('3'), throwsStateError);
      expect(access.canRead('3', hasPremium: false), isFalse);
      expect(await open('3'), isFalse);
      expect(prompts, 2);
      expect(await open('rookreview:1'), isTrue);
      expect(prompts, 2);
    },
  );

  test(
    'concurrent requests cannot spend reads or stack access prompts',
    () async {
      final access = NewsReadingAccess();
      var prompts = 0;
      final result = Completer<bool>();
      Future<bool> open(String key) => access.open(
        key,
        hasPremium: () => false,
        requestPremium: () {
          prompts++;
          return result.future;
        },
      );
      for (var i = 0; i < 3; i++) {
        await open('$i');
      }
      final pending = open('3');
      expect(await open('4'), isFalse);
      expect(await open('3'), isFalse);
      expect(prompts, 1);
      result.complete(false);
      expect(await pending, isFalse);
      expect(access.canRead('3', hasPremium: false), isFalse);
      expect(access.canRead('4', hasPremium: false), isFalse);
    },
  );
}
