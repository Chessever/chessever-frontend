import 'dart:async';

import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// The gate between a removal's delete and its Undo's write: a put-back row
/// is written only once every delete of that pin has answered.
void main() {
  test(
    'settled waits for the delete on the wire, and only for that pin',
    () async {
      final deletes = SpacePendingDeletes();
      final wire = Completer<void>();
      final run = deletes.run('a', () => wire.future);
      expect(deletes.contains('a'), isTrue);
      expect(deletes.contains('b'), isFalse);

      var settled = false;
      unawaited(deletes.settled('a').then((_) => settled = true));
      var other = false;
      unawaited(deletes.settled('b').then((_) => other = true));
      await Future<void>.delayed(Duration.zero);
      expect(settled, isFalse);
      expect(other, isTrue);

      wire.complete();
      await run;
      await Future<void>.delayed(Duration.zero);
      expect(settled, isTrue);
      expect(deletes.contains('a'), isFalse);
    },
  );

  test('a second removal of the same pin is waited for with the first, '
      'however they answer', () async {
    final deletes = SpacePendingDeletes();
    final first = Completer<void>();
    final second = Completer<void>();
    unawaited(deletes.run('a', () => first.future));
    unawaited(deletes.run('a', () => second.future));

    var settled = false;
    unawaited(deletes.settled('a').then((_) => settled = true));
    second.complete();
    await Future<void>.delayed(Duration.zero);
    // The first is still on the wire: a write now could land before it.
    expect(settled, isFalse);
    expect(deletes.contains('a'), isTrue);

    first.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(settled, isTrue);
    expect(deletes.contains('a'), isFalse);
  });

  test('a delete that fails still opens the gate', () async {
    final deletes = SpacePendingDeletes();
    final run = deletes.run('a', () async => throw StateError('offline'));
    await expectLater(run, throwsStateError);
    await deletes.settled('a');
    expect(deletes.contains('a'), isFalse);
  });
}
