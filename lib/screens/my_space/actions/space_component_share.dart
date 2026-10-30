import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// These links navigate to the recipient's own workspace, without publishing it.
enum SpaceComponent { prep, library, likes }

Uri spaceComponentShareUri(SpaceComponent component) =>
    Uri.https('chessever.com', '/app/my-space/${component.name}');

/// Outside Edit, holding a permanent card offers its destination for sharing.
/// The edit grid owns gestures while editing, including hold-to-reorder.
class SpaceComponentShare extends StatelessWidget {
  const SpaceComponentShare({
    super.key,
    required this.component,
    required this.child,
  });

  final SpaceComponent component;
  final Widget child;

  Future<void> _shareMenu(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    HapticFeedbackService.medium();
    final share = await showMenu<bool>(
      context: context,
      position: RelativeRect.fromRect(origin, Offset.zero & overlay.size),
      items: const [PopupMenuItem(value: true, child: Text('Share'))],
    );
    if (share != true || !context.mounted) return;
    try {
      await Share.share(
        spaceComponentShareUri(component).toString(),
        sharePositionOrigin: origin,
      );
    } catch (error) {
      if (context.mounted) {
        showAppSnack(
          context,
          userFacingError(error),
          tone: AppSnackTone.danger,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) =>
      GestureDetector(onLongPress: () => _shareMenu(context), child: child);
}
