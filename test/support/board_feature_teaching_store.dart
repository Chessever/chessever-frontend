import 'package:chessever2/screens/chessboard/utils/board_feature_teaching_tracker.dart';

export 'package:chessever2/screens/chessboard/utils/board_feature_teaching_tracker.dart';

/// Board fixtures isolate optional education from platform storage and timers.
class QuietBoardTeachingStore implements BoardFeatureTeachingStore {
  Map<String, Object?> _value = {
    'features': {
      'like': {'disabled': true},
      'notationSwipe': {'disabled': true},
    },
  };

  @override
  Future<Map<String, Object?>?> read() async => _value;

  @override
  Future<void> write(Map<String, Object?> value) async => _value = value;
}
