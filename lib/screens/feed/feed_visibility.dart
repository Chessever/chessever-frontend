import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Whether a Feed screen is open. Feed is a page pushed from For You ›
/// Discovery, not a home tab, so the news list asks this instead of the
/// bottom nav before it refreshes.
final feedScreenOpenProvider = StateProvider<bool>((ref) => false);

/// Whether Feed is seen this instant: its route is on top and not on its way
/// out (Back, a back swipe in progress), and the app is in the foreground.
///
/// [FeedScreen] flips [seen] the moment any of that changes, without waiting
/// for a frame, and every Feed page that can make a sound listens to it. A
/// clip's timer that fires between the change and the next rebuild (or with
/// no rebuild at all, in the background) finds Feed already silent.
class FeedSeen extends InheritedWidget {
  const FeedSeen({required this.seen, required super.child, super.key});

  final ValueListenable<bool> seen;

  /// The nearest Feed's [seen], or null outside a Feed (a page built on its
  /// own in a test), where a page counts as seen.
  static ValueListenable<bool>? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<FeedSeen>()?.seen;

  @override
  bool updateShouldNotify(FeedSeen oldWidget) => oldWidget.seen != seen;
}
