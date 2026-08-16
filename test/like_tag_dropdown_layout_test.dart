import 'package:chessever2/screens/chessboard/widgets/like_tag_chip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tag dropdown allows a taller panel without resizing tag rows', () {
    expect(kTagDropdownMaxHeight, 720);
    expect(kTagDropdownItemHeight, 48);
    expect(kTagDropdownMainAxisSpacing, 8);
  });
}
