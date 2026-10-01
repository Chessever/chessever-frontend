import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:flutter/material.dart';

/// Saved Smart Events need confirmation even when their live membership is empty.
Future<bool> confirmSpaceSmartEventRemoval(
  BuildContext context,
  Iterable<SpaceShortcut> shortcuts,
) async {
  final events = shortcuts
      .where((s) => s.kind == SpaceShortcutKind.smartEvent)
      .toList();
  if (events.isEmpty) return true;
  if (!context.mounted) return false;
  return await showSmoothConfirmDialog(
        context: context,
        title: events.length == 1
            ? 'Remove Smart Event?'
            : 'Remove Smart Events?',
        message: events.length == 1
            ? 'Remove ${events.single.title} from My Space? You can restore it with Undo.'
            : 'Remove these ${events.length} Smart Events from My Space? You can restore them with Undo.',
        confirmText: 'Remove',
        isDangerous: true,
      ) ==
      true;
}
