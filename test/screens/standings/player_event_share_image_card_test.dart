import 'package:chessever2/screens/standings/widgets/player_event_share_image_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatShareScore', () {
    test('renders whole scores without a trailing decimal', () {
      expect(PlayerEventShareImageCard.formatShareScore(9, 11), '9/11');
    });

    test('keeps the half point for fractional scores', () {
      expect(PlayerEventShareImageCard.formatShareScore(8.5, 11), '8.5/11');
    });

    test('handles a zero score', () {
      expect(PlayerEventShareImageCard.formatShareScore(0, 7), '0/7');
    });
  });
  group('share image copy', () {
    test('uses clean player rating and brand slogan copy', () {
      expect(PlayerEventShareImageCard.formatHeaderRating(2529), '2529');
      expect(
        PlayerEventShareImageCard.formatHeaderRating(2529),
        isNot(contains('FIDE')),
      );
      expect(PlayerEventShareImageCard.footerSlogan, 'Follow Chess Better');
    });
  });
}
