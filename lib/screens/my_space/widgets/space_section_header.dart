import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show DiscoverySeeAllHeader;
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:flutter/material.dart';

/// What a group of saved things is called on My Space, on its header, its
/// See all page and its add sheet. The Library's files are "Databases" here.
String spaceGroupTitle(SpaceSection section) => switch (section) {
  SpaceSection.library => 'Databases',
  _ => section.title,
};

/// One My Space group's head: Discovery's own section head
/// ([DiscoverySeeAllHeader]), so every hub section opens the same way. The
/// name (a 44 target of its own) and "See all" both open the group, the
/// count follows the name, and See all is always there.
class SpaceSectionHeader extends StatelessWidget {
  const SpaceSectionHeader({
    super.key,
    required this.title,
    required this.count,
    required this.onSeeAll,
    this.gutter = 0,
  });

  final String title;
  final int count;

  /// Opens the whole group: the title's tap and See all's.
  final VoidCallback onSeeAll;

  /// The page gutter the head starts on (0 inside a tablet column, which
  /// already holds it).
  final double gutter;

  @override
  Widget build(BuildContext context) {
    return DiscoverySeeAllHeader(
      title: title,
      count: count,
      gutter: gutter,
      onOpen: onSeeAll,
      seeAllSemanticsLabel: 'See all $count $title',
    );
  }
}
