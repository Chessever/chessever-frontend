import 'package:chessever2/services/lichess_move_annotations_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    LichessMoveAnnotationsService.clearCache();
  });

  tearDown(() {
    LichessMoveAnnotationsService.clearCache();
  });

  group('empty-retry budget', () {
    test('allows a bounded number of soft retries then stops', () {
      const gameId = 'q7ZvsdUF';
      const signature = '4:e4|e5|Nf3|Nc6';

      expect(
        LichessMoveAnnotationsService.shouldScheduleEmptyRetry(
          gameId,
          signature,
        ),
        isTrue,
      );

      for (var i = 0; i < LichessMoveAnnotationsService.maxEmptyRetries; i++) {
        expect(
          LichessMoveAnnotationsService.shouldScheduleEmptyRetry(
            gameId,
            signature,
          ),
          isTrue,
          reason: 'attempt $i',
        );
        LichessMoveAnnotationsService.recordEmptyRetryScheduled(
          gameId,
          signature,
        );
      }

      expect(
        LichessMoveAnnotationsService.shouldScheduleEmptyRetry(
          gameId,
          signature,
        ),
        isFalse,
        reason: 'budget exhausted',
      );
    });

    test('clearCache resets empty-retry budget', () {
      const gameId = 'abcdefgh';
      const signature = '1:e4';
      for (var i = 0; i < LichessMoveAnnotationsService.maxEmptyRetries; i++) {
        LichessMoveAnnotationsService.recordEmptyRetryScheduled(
          gameId,
          signature,
        );
      }
      expect(
        LichessMoveAnnotationsService.shouldScheduleEmptyRetry(
          gameId,
          signature,
        ),
        isFalse,
      );

      LichessMoveAnnotationsService.clearCache();
      expect(
        LichessMoveAnnotationsService.shouldScheduleEmptyRetry(
          gameId,
          signature,
        ),
        isTrue,
      );
    });
  });
}
