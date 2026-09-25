import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The one "Add to My Space" / "Remove from My Space" row every long-press
/// menu in the app appends. Callers only describe the target; this helper
/// owns dedupe, persistence, haptics and the confirmation snack.
///
/// Everything the row needs (the notifier, the messenger) is resolved here,
/// while the host is still mounted: the row runs after the menu route pops,
/// by which time the host card may be disposed or recycled, and touching
/// [ref] or [context] then throws. The notifier itself is app-scoped, so the
/// captured instance stays valid across the awaits below.
LibraryMenuAction spaceMenuAction({
  required BuildContext context,
  required WidgetRef ref,
  required SpaceShortcut draft,
}) {
  final inSpace = ref.read(spaceShortcutExistsProvider(draft.key));
  final notifier = ref.read(spaceShortcutsProvider.notifier);
  final messenger = ScaffoldMessenger.maybeOf(context);
  return LibraryMenuAction(
    icon: inSpace
        ? Icons.dashboard_customize
        : Icons.dashboard_customize_outlined,
    label: inSpace ? 'Remove from My Space' : 'Add to My Space',
    onSelected: () async {
      if (inSpace) {
        final removed = await notifier.removeTarget(draft.kind, draft.targetId);
        HapticFeedbackService.light();
        if (messenger != null && removed != null) {
          showAppSnackOn(
            messenger,
            'Removed from ${draft.section.title}',
            actionLabel: 'Undo',
            onAction: () => notifier.restore(removed),
          );
        }
        return;
      }
      final added = await notifier.add(draft);
      HapticFeedbackService.success();
      if (messenger != null) {
        showAppSnackOn(
          messenger,
          added
              ? 'Added to ${draft.section.title} in My Space'
              : 'Already in My Space',
          tone: added ? AppSnackTone.success : AppSnackTone.neutral,
        );
      }
    },
  );
}

/// Same as [spaceMenuAction] for surfaces that are not a context menu (an
/// app-bar button, a sheet row). Returns whether the target is now in My Space.
///
/// [ref] is only read before the first await, so the host may be disposed
/// while the write is in flight (user backs out, swipes to the next game).
Future<bool> toggleSpaceShortcut({
  required BuildContext context,
  required WidgetRef ref,
  required SpaceShortcut draft,
}) async {
  final notifier = ref.read(spaceShortcutsProvider.notifier);
  final action = spaceMenuAction(context: context, ref: ref, draft: draft);
  await action.onSelected();
  return notifier.contains(draft.kind, draft.targetId);
}
