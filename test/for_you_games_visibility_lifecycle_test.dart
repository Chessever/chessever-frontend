import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test('stale widget cleanup cannot hide a replacement For You surface', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(forYouSurfaceVisibleProvider.notifier);
    final firstOwner = Object();
    final replacementOwner = Object();

    notifier.publish(owner: firstOwner, isVisible: true);
    notifier.publish(owner: replacementOwner, isVisible: true);
    notifier.publish(owner: firstOwner, isVisible: false);

    expect(container.read(forYouSurfaceVisibleProvider), isTrue);

    notifier.publish(owner: replacementOwner, isVisible: false);

    expect(container.read(forYouSurfaceVisibleProvider), isFalse);
  });
}
