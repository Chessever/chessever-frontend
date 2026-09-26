import 'dart:async';

import 'package:chessever2/utils/owned_stream.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A stream source that records whether anything is still subscribed, the way
/// a Supabase Realtime `.stream()` keeps its channel joined while listened.
class _Source<T> {
  _Source() {
    controller = StreamController<T>(
      onListen: () => listens++,
      onCancel: () => cancels++,
    );
  }

  late final StreamController<T> controller;
  int listens = 0;
  int cancels = 0;

  bool get isSubscribed => controller.hasListener;
}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('Riverpod keeps a raw StreamProvider source subscribed after disposal '
      'during loading (the leak ownedStream exists for)', () async {
    final source = _Source<int>();
    final provider = StreamProvider.autoDispose<int>(
      (ref) => source.controller.stream,
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.listen(provider, (_, __) {}).close();
    await _settle();
    source.controller.add(1);
    await _settle();

    expect(
      source.isSubscribed,
      isTrue,
      reason:
          'Riverpod now cancels this source by itself. ownedStream is no '
          'longer required for correctness; update its doc comment and this '
          'test before removing it.',
    );
  });

  test('disposal before the first value cancels the source', () async {
    final source = _Source<int>();
    final provider = StreamProvider.autoDispose<int>(
      (ref) => ownedStream(ref, source.controller.stream),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final subscription = container.listen(provider, (_, __) {});
    await _settle();
    expect(source.isSubscribed, isTrue);

    subscription.close();
    await _settle();

    expect(source.isSubscribed, isFalse);
    expect(source.cancels, 1);
  });

  test('disposal after values cancels the source', () async {
    final source = _Source<int>();
    final provider = StreamProvider.autoDispose<int>(
      (ref) => ownedStream(ref, source.controller.stream),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final subscription = container.listen(provider, (_, __) {});
    source.controller.add(1);
    await _settle();
    expect(container.read(provider).valueOrNull, 1);

    subscription.close();
    await _settle();

    expect(source.isSubscribed, isFalse);
  });

  test('values, errors and completion reach the provider unchanged', () async {
    final source = _Source<int>();
    final provider = StreamProvider.autoDispose<int>(
      (ref) => ownedStream(ref, source.controller.stream),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final seen = <AsyncValue<int>>[];
    container.listen(provider, (_, next) => seen.add(next));

    source.controller.add(1);
    await _settle();
    source.controller.addError(StateError('realtime down'));
    await _settle();
    source.controller.add(2);
    await _settle();

    expect(seen.whereType<AsyncData<int>>().map((value) => value.value), [
      1,
      2,
    ]);
    expect(seen.whereType<AsyncError<int>>(), hasLength(1));
    expect(container.read(provider.future), completion(2));

    await source.controller.close();
    await _settle();
    expect(container.read(provider).valueOrNull, 2);
  });

  test(
    'a rebuild cancels the previous source and listens once to the next',
    () async {
      final sources = <String, _Source<int>>{
        'a': _Source<int>(),
        'b': _Source<int>(),
      };
      final key = StateProvider<String>((ref) => 'a');
      final provider = StreamProvider.autoDispose<int>((ref) {
        return ownedStream(ref, sources[ref.watch(key)]!.controller.stream);
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.listen(provider, (_, __) {});
      await _settle();

      container.read(key.notifier).state = 'b';
      await _settle();
      container.read(provider);
      await _settle();

      expect(sources['a']!.isSubscribed, isFalse);
      expect(sources['b']!.isSubscribed, isTrue);
      expect(sources['b']!.listens, 1);
    },
  );

  test('a card-like provider watching a family through select releases the '
      'source when the card goes away before the first snapshot', () async {
    final created = <_Source<Map<String, int>>>[];
    final batch = StreamProvider.autoDispose.family<Map<String, int>, String>((
      ref,
      roundId,
    ) {
      final source = _Source<Map<String, int>>();
      created.add(source);
      return ownedStream(ref, source.controller.stream);
    });
    final card = Provider.autoDispose.family<int?, String>((ref, gameId) {
      return ref.watch(
        batch('round-1').select((async) => async.valueOrNull?[gameId]),
      );
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Thirty cards scroll past; none outlives the round's initial snapshot.
    for (var i = 0; i < 30; i++) {
      container.listen(card('game-$i'), (_, __) {}).close();
      await _settle();
    }

    expect(created, hasLength(30));
    expect(created.where((source) => source.isSubscribed), isEmpty);
  });
}
