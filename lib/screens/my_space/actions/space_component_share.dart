import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// These links navigate to the recipient's own workspace, without publishing it.
enum SpaceComponent {
  prep('Prep'),
  library('Library'),
  likes('Likes');

  const SpaceComponent(this.title);

  /// The card's own title, as its menu names it ("Open Prep").
  final String title;
}

Uri spaceComponentShareUri(SpaceComponent component) =>
    Uri.https('chessever.com', '/app/my-space/${component.name}');

/// Shares [link] from the card [cardContext] belongs to: the share sheet
/// rises from the card, and a failure is said in the danger snack. Run after
/// the card's menu has closed, so the card is measured where it rests.
Future<void> shareHubTileLink(BuildContext cardContext, Uri link) async {
  final box = cardContext.findRenderObject();
  final origin = box is RenderBox && box.attached && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
  try {
    await Share.share(link.toString(), sharePositionOrigin: origin);
  } catch (error) {
    if (cardContext.mounted) {
      showAppSnack(
        cardContext,
        userFacingError(error),
        tone: AppSnackTone.danger,
      );
    }
  }
}

/// The two rows a hub card's hold offers: Open (when [onOpen] is given),
/// then Share, which sends [link].
List<LibraryMenuAction> hubTileMenuActions(
  BuildContext cardContext, {
  required String title,
  required Uri link,
  VoidCallback? onOpen,
}) => [
  if (onOpen != null)
    LibraryMenuAction(
      icon: Icons.open_in_new_rounded,
      label: 'Open $title',
      onSelected: onOpen,
    ),
  LibraryMenuAction(
    icon: Icons.ios_share_rounded,
    label: 'Share',
    onSelected: () => shareHubTileLink(cardContext, link),
  ),
];

/// Outside Edit, holding a permanent card lifts it into the shared focus menu
/// every card uses ([CardContextMenu]): the card rises over the blurred page
/// with Open and Share beside it, and Share sends its destination as a link.
/// The edit grid owns gestures while editing, including hold-to-reorder.
class SpaceComponentShare extends StatelessWidget {
  const SpaceComponentShare({
    super.key,
    required this.component,
    required this.child,
    this.onOpen,
  });

  final SpaceComponent component;
  final Widget child;

  /// What the card's tap opens, without the tap's haptic (the menu raises
  /// its own): the Open row and a tap on the lifted card. Without it the
  /// menu offers Share alone.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => CardContextMenu(
    onPreviewTap: onOpen,
    actions: (cardContext) => hubTileMenuActions(
      cardContext,
      title: component.title,
      link: spaceComponentShareUri(component),
      onOpen: onOpen,
    ),
    child: child,
  );
}
