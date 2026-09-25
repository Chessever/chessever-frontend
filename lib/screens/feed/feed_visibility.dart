import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Whether a Feed screen is open. Feed is a page pushed from For You ›
/// Discovery, not a home tab, so the news list asks this instead of the
/// bottom nav before it refreshes.
final feedScreenOpenProvider = StateProvider<bool>((ref) => false);
