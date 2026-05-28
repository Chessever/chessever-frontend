import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test(
    'bottom nav re-tap requests advance sequence for repeated same tab taps',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(
        bottomNavBarReTapRequestProvider.notifier,
      );

      notifier.request(BottomNavBarItem.tournaments);
      final first = container.read(bottomNavBarReTapRequestProvider);

      notifier.request(BottomNavBarItem.tournaments);
      final second = container.read(bottomNavBarReTapRequestProvider);

      expect(first.item, BottomNavBarItem.tournaments);
      expect(second.item, BottomNavBarItem.tournaments);
      expect(second.sequence, first.sequence + 1);
    },
  );
}
