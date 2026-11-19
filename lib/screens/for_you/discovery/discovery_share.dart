import 'package:chessever2/screens/my_space/actions/space_component_share.dart'
    show hubTileMenuActions;
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:chessever2/widgets/hub_tile.dart';
import 'package:flutter/material.dart';

/// The landing destinations available from Discovery.
enum DiscoveryShareDestination {
  feed('Feed'),
  likes('Likes'),
  news('News'),
  reports('Reports'),
  miniatures('Miniatures'),
  collections('Collections');

  const DiscoveryShareDestination(this.title);

  /// The tile's own title, as its menu names it ("Open Feed").
  final String title;
}

Uri discoveryShareUri(DiscoveryShareDestination component) =>
    Uri.https('chessever.com', '/app/${component.name}');

/// Holding a Discovery tile lifts it into the shared focus menu, as My
/// Space's own cards do: Open, then Share, which sends its landing page as a
/// link without opening it.
class DiscoveryTileShare extends StatelessWidget {
  const DiscoveryTileShare({
    super.key,
    required this.component,
    required this.child,
    this.onOpen,
  });

  final DiscoveryShareDestination component;
  final Widget child;

  /// What the Open row and a tap on the lifted tile run. Defaults to the
  /// tile's own tap when [child] is a [HubTile].
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final tile = child;
    final open = onOpen ?? (tile is HubTile ? tile.onTap : null);
    return CardContextMenu(
      onPreviewTap: open,
      actions: (cardContext) => hubTileMenuActions(
        cardContext,
        title: component.title,
        link: discoveryShareUri(component),
        onOpen: open,
      ),
      child: child,
    );
  }
}
