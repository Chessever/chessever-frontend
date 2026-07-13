import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Whether the home bottom searchable pill is expanded (Apple Music morph).
final homeBottomSearchExpandedProvider = StateProvider<bool>((ref) => false);

/// Shared text controller for home bottom search morph.
/// Owned here so Events/Calendar/Library can subscribe without owning UI.
final homeBottomSearchTextProvider = StateProvider<String>((ref) => '');

/// Becomes visible only after the expanded search control receives its second
/// tap. The filter action is routed back to the active Home destination.
final homeBottomSearchFilterVisibleProvider = StateProvider<bool>(
  (ref) => false,
);

/// Monotonic request channel for the active destination's filter sheet.
final homeBottomSearchFilterRequestProvider = StateProvider<int>((ref) => 0);
