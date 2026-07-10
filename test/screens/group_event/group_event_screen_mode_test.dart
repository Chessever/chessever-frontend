import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('For You is a single-purpose destination', () {
    expect(
      groupEventCategoriesFor(
        GroupEventScreenMode.forYou,
        hasActiveSearch: false,
      ),
      const [GroupEventCategory.forYou],
    );
    expect(
      groupEventCategoriesFor(
        GroupEventScreenMode.forYou,
        hasActiveSearch: true,
      ),
      const [GroupEventCategory.forYou],
    );
  });

  test('Events owns current, past, and destination search', () {
    expect(
      groupEventCategoriesFor(
        GroupEventScreenMode.events,
        hasActiveSearch: false,
      ),
      const [GroupEventCategory.current, GroupEventCategory.past],
    );
    expect(
      groupEventCategoriesFor(
        GroupEventScreenMode.events,
        hasActiveSearch: true,
      ),
      const [
        GroupEventCategory.current,
        GroupEventCategory.past,
        GroupEventCategory.search,
      ],
    );
  });

  test('legacy routed screen retains all categories', () {
    expect(
      groupEventCategoriesFor(GroupEventScreenMode.all, hasActiveSearch: true),
      const [
        GroupEventCategory.forYou,
        GroupEventCategory.current,
        GroupEventCategory.past,
        GroupEventCategory.search,
      ],
    );
  });
}
