import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test('Events opens on Current', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(selectedGroupCategoryProvider),
      GroupEventCategory.current,
    );
  });

  test('clearing a search started from the default tab returns to Current', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(groupEventSearchTabControllerProvider);

    controller.showSearch();
    controller.restorePreviousTab();

    expect(
      container.read(selectedGroupCategoryProvider),
      GroupEventCategory.current,
    );
  });

  for (final originalCategory in eventsHomeCategories) {
    test('clearing search restores the $originalCategory home tab', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(selectedGroupCategoryProvider.notifier).state =
          originalCategory;

      final controller = container.read(groupEventSearchTabControllerProvider);
      controller.showSearch();
      expect(
        container.read(selectedGroupCategoryProvider),
        GroupEventCategory.search,
      );

      controller.restorePreviousTab();
      expect(container.read(selectedGroupCategoryProvider), originalCategory);
    });
  }

  test('restoring search does not override a tab selected by the user', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(groupEventSearchTabControllerProvider);

    controller.showSearch();
    container.read(selectedGroupCategoryProvider.notifier).state =
        GroupEventCategory.past;
    controller.restorePreviousTab();

    expect(
      container.read(selectedGroupCategoryProvider),
      GroupEventCategory.past,
    );
  });
}
