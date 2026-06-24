import 'package:chessever2/utils/number_format_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatTightStatCount', () {
    test('keeps exact comma counts below 10k', () {
      expect(formatTightStatCount(828), '828');
      expect(formatTightStatCount(2323), '2,323');
      expect(formatTightStatCount(8250), '8,250');
    });

    test('uses one-decimal K for five-digit counts', () {
      expect(formatTightStatCount(10000), '10.0K');
      expect(formatTightStatCount(10149), '10.1K');
      expect(formatTightStatCount(11520), '11.5K');
      expect(formatTightStatCount(12953), '13.0K');
    });

    test('uses whole K for 100k+ counts', () {
      expect(formatTightStatCount(100000), '100K');
      expect(formatTightStatCount(250400), '250K');
    });
  });
}
