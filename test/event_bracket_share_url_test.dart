import 'package:chessever2/widgets/event_card/event_context_menu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buildEventShareUrl appends the canonical bracket tab marker', () {
    final url = buildEventShareUrl(
      id: 'fide_world_cup_2025',
      title: 'FIDE World Cup 2025',
      tourId: 'DqmmnYSq',
      tourSlug: 'fide-world-cup-2025--finals',
      tab: kEventBracketTab,
    );

    expect(
      url,
      'https://chessever.com/broadcast/'
      'fide-world-cup-2025--finals/DqmmnYSq?tab=bracket',
    );
  });
}
