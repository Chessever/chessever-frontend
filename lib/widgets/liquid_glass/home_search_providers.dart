import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Whether the home bottom searchable pill is expanded (Apple Music morph).
final homeBottomSearchExpandedProvider = StateProvider<bool>((ref) => false);

/// Shared text controller for home bottom search morph.
/// Owned here so Events/Calendar/Library can subscribe without owning UI.
final homeBottomSearchTextProvider = StateProvider<String>((ref) => '');
