import 'package:chessever2/screens/my_space/domain/my_space_shelf_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MySpaceShelfState', () {
    test('represents loading', () {
      const state = MySpaceShelfState<String>.loading();

      expect(state, isA<MySpaceShelfLoading<String>>());
      expect(state, const MySpaceShelfState<String>.loading());
    });

    test('represents loaded data', () {
      const state = MySpaceShelfState<String>.data('loaded');

      expect(state, isA<MySpaceShelfData<String>>());
      expect((state as MySpaceShelfData<String>).data, 'loaded');
      expect(state, const MySpaceShelfState<String>.data('loaded'));
      expect(
        state.hashCode,
        const MySpaceShelfState<String>.data('loaded').hashCode,
      );
    });

    test('represents empty', () {
      const state = MySpaceShelfState<String>.empty();

      expect(state, isA<MySpaceShelfEmpty<String>>());
      expect(state, const MySpaceShelfState<String>.empty());
    });

    test('represents partial data with its non-blocking error', () {
      const state = MySpaceShelfState<String>.partial(
        data: 'usable subset',
        error: 'one source failed',
      );

      expect(state, isA<MySpaceShelfPartial<String>>());
      final partial = state as MySpaceShelfPartial<String>;
      expect(partial.data, 'usable subset');
      expect(partial.error, 'one source failed');
      expect(
        state,
        const MySpaceShelfState<String>.partial(
          data: 'usable subset',
          error: 'one source failed',
        ),
      );
    });

    test('represents an error', () {
      const state = MySpaceShelfState<String>.error('failed');

      expect(state, isA<MySpaceShelfError<String>>());
      expect((state as MySpaceShelfError<String>).error, 'failed');
      expect(state, const MySpaceShelfState<String>.error('failed'));
    });

    test('represents unauthorized', () {
      const state = MySpaceShelfState<String>.unauthorized();

      expect(state, isA<MySpaceShelfUnauthorized<String>>());
      expect(state, const MySpaceShelfState<String>.unauthorized());
    });

    test('represents removed and tombstone as the same explicit state', () {
      const removed = MySpaceShelfState<String>.removed();
      const tombstone = MySpaceShelfState<String>.tombstone();

      expect(removed, isA<MySpaceShelfRemoved<String>>());
      expect(tombstone, isA<MySpaceShelfRemoved<String>>());
      expect(removed, tombstone);
    });

    test('represents offline with cached data', () {
      const state = MySpaceShelfState<String>.offlineWithCache('cached');

      expect(state, isA<MySpaceShelfOfflineWithCache<String>>());
      expect((state as MySpaceShelfOfflineWithCache<String>).data, 'cached');
      expect(state, const MySpaceShelfState<String>.offlineWithCache('cached'));
    });

    test('represents offline without cached data', () {
      const state = MySpaceShelfState<String>.offlineWithoutCache();

      expect(state, isA<MySpaceShelfOfflineWithoutCache<String>>());
      expect(state, const MySpaceShelfState<String>.offlineWithoutCache());
    });

    test('keeps data-bearing variants distinct', () {
      const data = MySpaceShelfState<String>.data('same');
      const cached = MySpaceShelfState<String>.offlineWithCache('same');

      expect(data, isNot(cached));
      expect(
        const MySpaceShelfState<String>.data('one'),
        isNot(const MySpaceShelfState<String>.data('two')),
      );
    });
  });
}
