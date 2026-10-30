import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// The landing destinations available from Discovery.
enum DiscoveryShareDestination { feed, likes, news, reports, miniatures }

Uri discoveryShareUri(DiscoveryShareDestination component) =>
    Uri.https('chessever.com', '/app/${component.name}');

/// Holding a Discovery tile shares its landing page without opening it.
class DiscoveryTileShare extends StatelessWidget {
  const DiscoveryTileShare({
    super.key,
    required this.component,
    required this.child,
  });

  final DiscoveryShareDestination component;
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
        discoveryShareUri(component).toString(),
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
