import 'dart:async';

import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_space/actions/space_menu_action.dart';
import 'package:chessever2/screens/my_space/navigation/space_shortcut_navigator.dart';
import 'package:chessever2/screens/my_space/providers/space_auto_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_players_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Opens a face of My Space's Players the way its pin opens, and records the
/// visit once the page has slid in, so the player leads the row when the
/// user comes back.
void spaceOpenPlayer(BuildContext context, WidgetRef ref, SpacePlayerEntry e) {
  HapticFeedbackService.cardTap();
  // Resolved now: the face may be recycled before the visit is written.
  final visits = ref.read(spacePlayerVisitsProvider.notifier);
  unawaited(openSpaceShortcut(context, ref, e.shortcut));
  if (!e.isPerson) return;
  unawaited(spaceAfterOpenTransition().then((_) => visits.visit(e.identity)));
}

/// "Remove from My Space" on a face: its pins leave, its follow is hidden
/// here (never unfollowed), and one snack offers Undo for both.
///
/// Resolved while the host is mounted: the row runs after the menu pops.
LibraryMenuAction spaceRemovePlayerAction({
  required BuildContext context,
  required WidgetRef ref,
  required SpacePlayerEntry entry,
}) {
  // A Countrymen flag or a streak card is a pin like any other.
  if (!entry.isPerson) {
    return spaceMenuAction(context: context, ref: ref, draft: entry.shortcut);
  }
  final remove = spacePlayerRemover(ref, entry);
  final messenger = ScaffoldMessenger.maybeOf(context);
  return LibraryMenuAction(
    icon: Icons.dashboard_customize,
    label: 'Remove from My Space',
    onSelected: () async {
      // The face leaves at once, the snack follows at once, and Undo brings
      // the face back at once (the store writes it once the deletes have
      // answered).
      final removal = remove();
      HapticFeedbackService.light();
      if (messenger != null && messenger.mounted) {
        showAppSnackOn(
          messenger,
          'Removed from My Space',
          actionLabel: 'Undo',
          onAction: () => unawaited(
            removal.undo().catchError((Object e) {
              debugPrint('[MySpace] undo failed: $e');
            }),
          ),
        );
      }
      await removal.written;
    },
  );
}

/// A player's removal from My Space: [written] completes once the server
/// has answered its deletes; [undo] puts the face back at once.
typedef SpacePlayerRemoval = ({
  Future<void> written,
  Future<void> Function() undo,
});

/// Takes [entry] out of My Space's Players when called: removes its pins and
/// hides its follow on this device, all of it off the page at once (the
/// pins' deletes run together). Its [SpacePlayerRemoval.undo] puts back what
/// left, as it stood when it left. Everything it needs is read now, so it
/// may run after the face has gone.
SpacePlayerRemoval Function() spacePlayerRemover(
  WidgetRef ref,
  SpacePlayerEntry entry,
) {
  final store = ref.read(spaceShortcutsProvider.notifier);
  final hidden = ref.read(spaceHiddenAutoKeysProvider.notifier);
  final pins = [...entry.pins];
  final favorite = entry.favorite;
  return () {
    final key = favorite == null ? null : spaceHiddenFavoriteKey(favorite);
    if (key != null) hidden.hide(key);
    // Only what is in My Space now leaves, and only that comes back.
    final present = [for (final p in pins) ?store.pinFor(p.kind, p.targetId)];
    final written = Future.wait([
      for (final p in present) store.removeTarget(p.kind, p.targetId),
    ]);
    return (
      written: written,
      undo: () async {
        if (key != null) hidden.unhide(key);
        await Future.wait([for (final p in present) store.restore(p)]);
      },
    );
  };
}
