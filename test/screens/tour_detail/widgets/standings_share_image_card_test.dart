import 'package:chessever2/screens/tour_detail/widgets/standings_share_image_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('standings share image row rules', () {
    test('keeps footer for events with ten or fewer players', () {
      expect(standingsShareRowLimit(10), 10);
      expect(standingsShareShowsFooter(10), isTrue);
    });

    test('fits all twelve-player round robins without forcing footer', () {
      expect(standingsShareRowLimit(12), 12);
      expect(standingsShareShowsFooter(12), isFalse);
    });

    test('caps larger events at twelve clean rows', () {
      expect(standingsShareRowLimit(14), 12);
      expect(standingsShareShowsFooter(14), isFalse);
    });
  });
}
