import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:flutter/material.dart';

/// Saved Smart Events need confirmation even when their live membership is
/// empty. Leaving My Space never unstars one (its star is its push
/// subscription, and removal keeps every source as it was), so the dialog
/// says where its notifications are stopped: the star on its card, or
/// Starred Smart Events once the card is gone.
Future<bool> confirmSpaceSmartEventRemoval(
  BuildContext context,
  Iterable<SpaceShortcut> shortcuts,
) async {
  final events = shortcuts
      .where((s) => s.kind == SpaceShortcutKind.smartEvent)
      .toList();
  if (events.isEmpty) return true;
  if (!context.mounted) return false;
  final one = events.length == 1;
  final removalMessage = one
      ? 'Remove ${events.single.title} from My Space? You can restore it with Undo.'
      : 'Remove these ${events.length} Smart Events from My Space? You can restore them with Undo.';
  final stopMessage = one
      ? 'To stop them, unstar it on its card or in Starred Smart Events.'
      : 'To stop them, unstar them on their cards or in Starred Smart Events.';
  return await showSmoothConfirmDialog(
        context: context,
        title: one ? 'Remove Smart Event?' : 'Remove Smart Events?',
        message:
            '$removalMessage Starred events will still send notifications. $stopMessage',
        confirmText: 'Remove',
        isDangerous: true,
      ) ==
      true;
}
