import 'dart:async';

import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_space/actions/space_menu_action.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
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
      final undo = await remove();
      HapticFeedbackService.light();
      if (messenger == null || !messenger.mounted) return;
      showAppSnackOn(
        messenger,
        'Removed from My Space',
        actionLabel: 'Undo',
        onAction: undo,
      );
    },
  );
}

/// Takes [entry] out of My Space's Players when called: removes its pins and
/// hides its follow on this device. Returns the Undo. Everything it needs is
/// read now, so it may run after the face has gone.
Future<Future<void> Function()> Function() spacePlayerRemover(
  WidgetRef ref,
  SpacePlayerEntry entry,
) {
  final store = ref.read(spaceShortcutsProvider.notifier);
  final hidden = ref.read(spaceHiddenAutoKeysProvider.notifier);
  final pins = [...entry.pins];
  final favorite = entry.favorite;
  return () async {
    final key = favorite == null ? null : spaceHiddenFavoriteKey(favorite);
    if (key != null) hidden.hide(key);
    final removed = <SpaceShortcut>[];
    for (final p in pins) {
      final gone = await store.removeTarget(p.kind, p.targetId);
      if (gone != null) removed.add(gone);
    }
    return () async {
      if (key != null) hidden.unhide(key);
      for (final p in removed.reversed) {
        await store.restore(p);
      }
    };
  };
}
