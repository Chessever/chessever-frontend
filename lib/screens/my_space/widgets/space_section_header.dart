import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show DiscoveryAction, DiscoveryType, discoveryType;
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// What a group of saved things is called under My Database, on its
/// sub-header, its See all page and its add sheet. The Library's files are
/// "Databases" here: the page's own title already says My Database.
String spaceGroupTitle(SpaceSection section) => switch (section) {
  SpaceSection.library => 'Databases',
  _ => section.title,
};

/// One group's sub-header inside My Database: what the group holds and how
/// many, on one quiet line one step under the page's section title, with
/// "See all" at the far end only while the group shows some of them.
///
/// Always one 44 line (the See all target's height), so every group opens
/// on the same rhythm whether or not it has more to show.
class SpaceSectionHeader extends StatelessWidget {
  const SpaceSectionHeader({
    super.key,
    required this.title,
    required this.count,
    this.onSeeAll,
  });

  final String title;
  final int count;

  /// Opens the whole group. Null when the group already shows everything.
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final seeAll = onSeeAll;
    final name = discoveryType(context, DiscoveryType.body);
    final quiet = discoveryType(
      context,
      DiscoveryType.body,
      weight: FontWeight.w500,
      tabular: true,
    ).copyWith(color: discoveryType(context, DiscoveryType.meta).color);
    return SizedBox(
      height: 44.w,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              label: '$title, $count',
              excludeSemantics: true,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: name,
                    ),
                  ),
                  SizedBox(width: 6.w),
                  Text('$count', maxLines: 1, style: quiet),
                ],
              ),
            ),
          ),
          if (seeAll != null) ...[
            SizedBox(width: 12.w),
            DiscoveryAction(
              label: 'See all',
              arrow: true,
              onTap: seeAll,
              semanticsLabel: 'See all $count $title',
            ),
          ],
        ],
      ),
    );
  }
}
