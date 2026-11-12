import 'package:chessever2/utils/release_console.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  setUp(ReleaseConsole.clear);
  tearDown(ReleaseConsole.clear);

  test('is not quiet outside a release build, so tests and debug still print', () {
    expect(ReleaseConsole.quiet, isFalse);
    expect(ReleaseConsole.zoneSpecification, isNull);
  });

  test('an event with nothing buffered is left alone', () {
    final event = SentryEvent();
    ReleaseConsole.attachTo(event);
    expect(event.breadcrumbs, isNull);
  });

  test('buffered lines reach the event as console breadcrumbs', () {
    ReleaseConsole.record('first');
    ReleaseConsole.record('second');

    final event = SentryEvent();
    ReleaseConsole.attachTo(event);

    final crumbs = event.breadcrumbs!;
    expect(crumbs.map((c) => c.message), ['first', 'second']);
    expect(crumbs.every((c) => c.category == 'console'), isTrue);
    expect(crumbs.every((c) => c.level == SentryLevel.debug), isTrue);
  });

  test('keeps only the newest lines', () {
    for (var i = 0; i < ReleaseConsole.capacity + 10; i++) {
      ReleaseConsole.record('line $i');
    }

    final event = SentryEvent();
    ReleaseConsole.attachTo(event);

    final crumbs = event.breadcrumbs!;
    expect(crumbs, hasLength(ReleaseConsole.capacity));
    expect(crumbs.first.message, 'line 10');
    expect(crumbs.last.message, 'line ${ReleaseConsole.capacity + 9}');
  });

  test('merges with the breadcrumbs an event already has, in time order', () {
    final earlier = Breadcrumb(
      message: 'navigation',
      timestamp: DateTime.utc(2000),
    );
    final later = Breadcrumb(message: 'http', timestamp: DateTime.utc(2999));
    ReleaseConsole.record('console line');

    final event = SentryEvent(breadcrumbs: [later, earlier]);
    ReleaseConsole.attachTo(event);

    expect(event.breadcrumbs!.map((c) => c.message), [
      'navigation',
      'console line',
      'http',
    ]);
  });
}
