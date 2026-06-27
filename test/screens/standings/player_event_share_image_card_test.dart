import 'package:chessever2/screens/standings/widgets/player_event_share_image_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('player event share image sizing rules', () {
    test('keeps footer only when it does not compete with many rows', () {
      expect(playerEventShareShouldShowFooter(10), isTrue);
      expect(playerEventShareShouldShowFooter(11), isTrue);
      expect(playerEventShareShouldShowFooter(12), isFalse);
      expect(playerEventShareShouldShowFooter(13), isFalse);
    });

    test('compresses rows for 11 and 13 round events without hiding rows', () {
      expect(playerEventShareRowHeight(9), 54.0);
      expect(playerEventShareRowHeight(11), 50.0);
      expect(playerEventShareRowHeight(13), 47.0);
    });
  });
}
