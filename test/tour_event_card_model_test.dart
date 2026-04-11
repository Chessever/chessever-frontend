import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GroupEventCardModel.getCategory', () {
    final now = DateTime.now();

    test('returns live when the strict live resolver marks the event live', () {
      final result = GroupEventCardModel.getCategory(
        groupId: 'event-1',
        groupName: 'Event One',
        startDate: now.subtract(const Duration(days: 2)),
        endDate: now.subtract(const Duration(hours: 6)),
        liveGroupIds: const ['event-1'],
      );

      expect(result, TourEventCategory.live);
    });
  });
}
