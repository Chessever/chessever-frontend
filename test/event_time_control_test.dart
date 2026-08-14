import 'package:chessever2/utils/event_time_control.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('timeControlBucketFor', () {
    test('maps every spelling the database and chips actually use', () {
      expect(timeControlBucketFor('standard'), TimeControlBucket.classical);
      expect(timeControlBucketFor('Standard'), TimeControlBucket.classical);
      expect(timeControlBucketFor('classical'), TimeControlBucket.classical);
      expect(timeControlBucketFor('Classical'), TimeControlBucket.classical);
      expect(timeControlBucketFor('rapid'), TimeControlBucket.rapid);
      expect(timeControlBucketFor('Rapid'), TimeControlBucket.rapid);
      expect(timeControlBucketFor('blitz'), TimeControlBucket.blitz);
      expect(timeControlBucketFor('Blitz'), TimeControlBucket.blitz);
      expect(timeControlBucketFor('bullet'), TimeControlBucket.blitz);
      expect(timeControlBucketFor('Bullet'), TimeControlBucket.blitz);
      expect(timeControlBucketFor(null), isNull);
      expect(timeControlBucketFor(''), isNull);
      expect(timeControlBucketFor('unknown'), isNull);
    });
  });

  group('broadcastMatchesTimeControlFilter', () {
    test('Classical chip matches standard and classical events', () {
      const chips = {'standard'};
      expect(broadcastMatchesTimeControlFilter('standard', chips), isTrue);
      expect(broadcastMatchesTimeControlFilter('Classical', chips), isTrue);
      expect(broadcastMatchesTimeControlFilter('rapid', chips), isFalse);
      expect(broadcastMatchesTimeControlFilter(null, chips), isFalse);
    });

    test('Blitz chip matches blitz and bullet events', () {
      const chips = {'blitz'};
      expect(broadcastMatchesTimeControlFilter('blitz', chips), isTrue);
      expect(broadcastMatchesTimeControlFilter('Bullet', chips), isTrue);
      expect(broadcastMatchesTimeControlFilter('rapid', chips), isFalse);
    });

    test('selecting every Time Control chip keeps unknown events', () {
      const chips = {'standard', 'rapid', 'blitz'};
      expect(selectsEveryTimeControlBucket(chips), isTrue);
      expect(broadcastMatchesTimeControlFilter(null, chips), isTrue);
      expect(broadcastMatchesTimeControlFilter('correspondence', chips), isTrue);
      expect(broadcastMatchesTimeControlFilter('blitz', chips), isTrue);
    });

    test('no Time Control chip keeps unknown events', () {
      expect(broadcastMatchesTimeControlFilter(null, const {}), isTrue);
      expect(broadcastMatchesTimeControlFilter('classical', const {}), isTrue);
    });

    test('Blitz+Rapid drops classical and unknown', () {
      const chips = {'blitz', 'rapid'};
      expect(broadcastMatchesTimeControlFilter('blitz', chips), isTrue);
      expect(broadcastMatchesTimeControlFilter('rapid', chips), isTrue);
      expect(broadcastMatchesTimeControlFilter('standard', chips), isFalse);
      expect(broadcastMatchesTimeControlFilter(null, chips), isFalse);
    });
  });

  group('postgrestTimeControlValues', () {
    test('Classical expands to both spellings and casings', () {
      expect(
        postgrestTimeControlValues(const {'standard'}),
        containsAll(['standard', 'classical', 'Standard', 'Classical']),
      );
    });

    test('Blitz expands to bullet as well', () {
      expect(
        postgrestTimeControlValues(const {'blitz'}),
        containsAll(['blitz', 'Blitz', 'bullet', 'Bullet']),
      );
    });

    test('all three chips produce no event-level scoping list', () {
      expect(
        postgrestTimeControlValues(const {'standard', 'rapid', 'blitz'}),
        isEmpty,
      );
    });
  });
}
