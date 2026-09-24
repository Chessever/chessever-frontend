import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/standings/utils/player_event_share_utils.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// The chessever.com link of one team's page in [about]'s event
/// (`/broadcast/<slug>/<id>/team/<name>`), or null when the event has no
/// public URL (gamebase-only virtual events). Team pins from older builds
/// hold this link; My Space opens them as any `/broadcast/...` link.
String? teamPageShareUrl({
  required AboutTourModel? about,
  required String teamName,
}) {
  final name = teamName.trim();
  if (about == null || name.isEmpty) return null;
  final group = about.groupBroadcastId?.trim() ?? '';
  return buildTeamEventShareUrl(
    teamName: name,
    canonicalEventId: group.isNotEmpty ? group : about.id,
    eventName: about.name,
    tourId: about.id,
    tourSlug: about.slug,
  );
}

/// Team name as it reads inside a menu label ("Open Norway"). Long names are
/// shortened with an ellipsis so the label stays on one line beside the verb.
String teamMenuLabelName(String teamName) {
  final name = teamName.trim();
  if (name.length <= 16) return name;
  return '${name.substring(0, 15).trimRight()}…';
}

/// The team rows of a focus menu, for the team open in the tournament detail
/// screen: open its scorecard and share its page link. A team is not pinned
/// into My Space.
///
/// [nameInLabels] spells the team out in each label, for menus that carry
/// two teams at once (a matchup header).
List<LibraryMenuAction> teamMenuActions({
  required BuildContext context,
  required WidgetRef ref,
  required String teamName,
  VoidCallback? onOpen,
  bool includeShare = true,
  bool nameInLabels = false,
}) {
  final about = ref.read(tourDetailScreenProvider).valueOrNull?.aboutTourModel;
  final url = teamPageShareUrl(about: about, teamName: teamName);
  final label = teamMenuLabelName(teamName);
  return [
    if (onOpen != null)
      LibraryMenuAction(
        icon: Icons.open_in_new_rounded,
        label: nameInLabels ? 'Open $label' : 'Open team scorecard',
        onSelected: onOpen,
      ),
    if (includeShare && url != null)
      LibraryMenuAction(
        icon: Icons.ios_share_rounded,
        label: nameInLabels ? 'Share $label' : 'Share link',
        onSelected: () {
          final box =
              context.mounted ? context.findRenderObject() as RenderBox? : null;
          final origin =
              box != null && box.hasSize
                  ? box.localToGlobal(Offset.zero) & box.size
                  : const Rect.fromLTWH(0, 0, 1, 1);
          Share.share(url, sharePositionOrigin: origin);
        },
      ),
  ];
}
