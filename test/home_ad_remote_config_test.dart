import 'dart:async';

import 'package:chessever2/services/home_ad_remote_config.dart';
import 'package:flutter_test/flutter_test.dart';

class _Source implements HomeAdConfigSource {
  final changes = StreamController<bool>.broadcast();
  final ready = Completer<bool>();
  bool fetched = false;
  bool failFetch = false;
  int initializations = 0;

  @override
  Future<bool> initialize() {
    initializations++;
    return ready.future;
  }

  @override
  Future<bool> fetch() async {
    if (failFetch) throw StateError('offline');
    return fetched;
  }

  @override
  Stream<bool> get updates => changes.stream;
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  late _Source source;
  late HomeAdRemoteConfigNotifier notifier;
  setUp(() => source = _Source());
  tearDown(() async {
    if (notifier.mounted) notifier.dispose();
    await source.changes.close();
  });

  test('hidden before configuration and when parameter is false', () async {
    notifier = HomeAdRemoteConfigNotifier(source: source, enabled: true);
    expect(notifier.state, false);
    source.ready.complete(false);
    await _flush();
    expect(notifier.state, false);
  });

  test('fetch enables ad and a published update hides it again', () async {
    source.fetched = true;
    notifier = HomeAdRemoteConfigNotifier(source: source, enabled: true);
    source.ready.complete(false);
    await _flush();
    expect(notifier.state, true);
    source.changes.add(false);
    await _flush();
    expect(notifier.state, false);
    source.changes.add(true);
    await _flush();
    expect(notifier.state, true);
  });

  test('initialization failure keeps ad hidden', () async {
    notifier = HomeAdRemoteConfigNotifier(source: source, enabled: true);
    source.ready.completeError(StateError('Firebase unavailable'));
    await _flush();
    expect(notifier.state, false);
  });

  test('offline fetch retains cached setting, defaulting to hidden', () async {
    source.failFetch = true;
    notifier = HomeAdRemoteConfigNotifier(source: source, enabled: true);
    source.ready.complete(false);
    await _flush();
    expect(notifier.state, false);
    notifier.dispose();
    await source.changes.close();
    source = _Source()..failFetch = true;
    notifier = HomeAdRemoteConfigNotifier(source: source, enabled: true);
    source.ready.complete(true);
    await _flush();
    expect(notifier.state, true);
  });

  test('disabled placement never initializes Firebase', () {
    notifier = HomeAdRemoteConfigNotifier(source: source, enabled: false);
    expect(source.initializations, 0);
    expect(notifier.state, false);
  });

  test(
    'disposal during initialization prevents listener registration',
    () async {
      notifier = HomeAdRemoteConfigNotifier(source: source, enabled: true);
      notifier.dispose();
      source.ready.complete(true);
      await _flush();
      expect(source.changes.hasListener, false);
    },
  );
}
