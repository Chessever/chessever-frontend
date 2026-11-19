import 'dart:async';

import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_auto_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Marks a surface where starring something also keeps it in My Space: the
/// Search tab (product decision, 2026-11-19). A star tapped under this
/// scope pins its event or smart event too; unstarring never takes the pin
/// back (AGENTS.md: removal preserves the source, and the reverse holds:
/// a star's end leaves My Space alone).
///
/// Routes pushed from the scope (an event page, a smart event screen) sit
/// outside it, so their stars stay stars only.
class SpaceStarPins extends InheritedWidget {
  const SpaceStarPins({super.key, required super.child});

  /// Whether [context] is under the scope. Read once, at the tap, so no
  /// card rebuilds for it.
  static bool of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SpaceStarPins>() != null;

  @override
  bool updateShouldNotify(SpaceStarPins oldWidget) => false;
}

/// Pins [draft] to My Space after a star under [SpaceStarPins], through the
/// same list the long-press's "Add to My Space" writes: at once on screen,
/// synced after. Says "Added to My Space" only when this made the pin; one
/// already there is left as it is, silently. No haptic of its own: the star
/// already gave one.
///
/// Takes what it needs resolved: the card may be gone by the time the star
/// has been written. Waits for My Space's list to be read (cached after the
/// first time), so a pin made on another device is never doubled or
/// announced. Returns whether a pin was added.
Future<bool> pinStarredToSpace({
  required ProviderContainer container,
  required ScaffoldMessengerState? messenger,
  required SpaceShortcut draft,
}) async {
  if (!draft.canAddToMySpace) return false;
  try {
    await container.read(spaceShortcutsProvider.future);
  } catch (_) {
    // An unreadable list still takes the pin locally, as the menu's does.
  }
  final shortcuts = container.read(spaceShortcutsProvider.notifier);
  if (shortcuts.pinFor(draft.kind, draft.targetId) != null) return false;
  // The list changes at once; the server write runs on without holding up
  // the rest of the star (its notification prompt).
  unawaited(shortcuts.add(draft));
  container.read(spaceHiddenAutoKeysProvider.notifier).unhide(draft.key);
  if (messenger != null && messenger.mounted) {
    showAppSnackOn(messenger, 'Added to My Space', tone: AppSnackTone.success);
  }
  return true;
}
