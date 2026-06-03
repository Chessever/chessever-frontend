import 'package:chessever2/utils/logger/logger.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talker/talker.dart';

/// Guards the core requirement: error logs must carry the FULL stacktrace so
/// the source of an error is visible and copy-pasteable.
void main() {
  setUp(talker.cleanHistory);

  test('handle() records the exception type and full stacktrace', () {
    StackTrace? thrownStack;
    try {
      throw const FormatException('boom while parsing PGN');
    } catch (e, st) {
      thrownStack = st;
      talker.handle(e, st, 'Parsing failed');
    }

    final entry = talker.history.last;
    final rendered = entry.generateTextMessage();

    // Classified as an exception (red/orange in console).
    expect(entry, isA<TalkerException>());
    // Message + the exact thrown stacktrace are both present, untruncated.
    expect(rendered, contains('Parsing failed'));
    expect(rendered, contains('FormatException'));
    expect(rendered, contains('StackTrace:'));
    expect(rendered, contains(thrownStack.toString().split('\n').first));
  });

  test('loggerProvider.logError still works and prints a stacktrace', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(loggerProvider);
    try {
      throw StateError('bad state');
    } catch (e, st) {
      controller.logError(e, st);
    }

    final entry = talker.history.last;
    expect(entry, isA<TalkerError>());
    expect(entry.generateTextMessage(), contains('StackTrace:'));
  });
}
