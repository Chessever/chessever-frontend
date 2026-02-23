import 'package:chessever2/screens/library/widgets/library_gamebase_filter_dialog.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Provider for the gamebase filter state used in Library search.
/// This provides a simple way to persist and access the current filter.
final gamebaseFilterProvider = StateProvider.autoDispose<GamebaseFilter>((ref) {
  return GamebaseFilter();
});

/// Provider that returns whether any filters are active.
final hasActiveGamebaseFiltersProvider = Provider<bool>((ref) {
  final filter = ref.watch(gamebaseFilterProvider);
  return filter.hasActiveFilters;
});

/// Provider that returns the count of active filters.
final activeGamebaseFilterCountProvider = Provider<int>((ref) {
  final filter = ref.watch(gamebaseFilterProvider);
  return filter.activeFilterCount;
});
