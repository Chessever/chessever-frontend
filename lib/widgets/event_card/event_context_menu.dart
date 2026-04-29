import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/tablet_safe_menu.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Actions available from the event card long-press context menu.
enum EventContextAction { share }

/// Builds the canonical shareable URL for an event, mirroring
/// `lichess.org/broadcast/<tour.slug>/<tour.id>` on chessever.com.
///
/// Pass [tourSlug] and [tourId] when known (Lichess short id like `QXavbhIZ`
/// + kebab slug) to produce a link that swaps `lichess.org` ↔ `chessever.com`
/// without any other change. The fallback path uses the group_broadcast id
/// and a slugified title — always works, but the path tail isn't a Lichess
/// short id.
String buildEventShareUrl({
  required String id,
  required String title,
  String? tourId,
  String? tourSlug,
}) {
  if (tourId != null &&
      tourId.isNotEmpty &&
      tourSlug != null &&
      tourSlug.isNotEmpty) {
    return 'https://chessever.com/broadcast/$tourSlug/$tourId';
  }
  final slug = _slugify(title);
  return 'https://chessever.com/broadcast/$slug/$id';
}

String _slugify(String input) {
  final lower = input.toLowerCase();
  final dashed = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  final trimmed = dashed.replaceAll(RegExp(r'^-+|-+$'), '');
  return trimmed.isEmpty ? 'event' : trimmed;
}

/// Show the event long-press context menu and run the selected action.
///
/// Community (calendar) events don't have a tournament detail screen, so the
/// menu is not shown for them — the caller should check [canShowFor] first.
Future<void> showEventContextMenu({
  required BuildContext context,
  required WidgetRef ref,
  required GroupEventCardModel model,
  required Offset globalPosition,
}) async {
  if (!canShowFor(model)) return;

  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final position = RelativeRect.fromRect(
    globalPosition & const Size(40, 40),
    Offset.zero & overlay.size,
  );

  final action = await showTabletSafeMenu<EventContextAction>(
    context: context,
    position: position,
    color: kBlack2Color,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.br)),
    constraints: BoxConstraints.tightFor(width: 176.w),
    items: _buildMenuItems(),
  );

  if (action == null || !context.mounted) return;
  switch (action) {
    case EventContextAction.share:
      await _shareEvent(context: context, ref: ref, model: model);
      break;
  }
}

/// Community events are calendar-only and not backed by a GroupBroadcast,
/// so tapping About/Games/Standings has no destination.
bool canShowFor(GroupEventCardModel model) {
  return model.eventSource != EventSource.communityEvent;
}

List<PopupMenuEntry<EventContextAction>> _buildMenuItems() {
  return [
    _menuItem(
      value: EventContextAction.share,
      label: 'Share',
      icon: Icons.ios_share,
    ),
  ];
}

PopupMenuItem<EventContextAction> _menuItem({
  required EventContextAction value,
  required String label,
  required IconData icon,
}) {
  return PopupMenuItem<EventContextAction>(
    value: value,
    padding: EdgeInsets.zero,
    height: 36.h,
    child: _EventMenuRow(label: label, icon: icon),
  );
}

Future<void> _shareEvent({
  required BuildContext context,
  required WidgetRef ref,
  required GroupEventCardModel model,
}) async {
  // Resolve the primary tour so the share link mirrors the Lichess shape
  // `<tour.slug>/<tour.id>`. This keeps the path tail an 8-char Lichess
  // short id (e.g. `QXavbhIZ`) instead of repeating the slug. Fall back to
  // the group_broadcast id if the lookup fails, so sharing never blocks.
  ({String id, String slug})? tour;
  try {
    tour = await ref
        .read(groupBroadcastRepositoryProvider)
        .getPrimaryTourSlugAndId(model.id);
  } catch (_) {
    tour = null;
  }

  final url = buildEventShareUrl(
    id: model.id,
    title: model.title,
    tourId: tour?.id,
    tourSlug: tour?.slug,
  );
  if (!context.mounted) return;
  final box = context.findRenderObject() as RenderBox?;
  final origin =
      box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : const Rect.fromLTWH(0, 0, 1, 1);

  AnalyticsService.instance.trackEventDetached(
    'Event Shared',
    properties: {'event_id': model.id, 'event_name': model.title},
  );

  await Share.share(url, sharePositionOrigin: origin);
}

class _EventMenuRow extends StatelessWidget {
  const _EventMenuRow({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 40.h,
      padding: EdgeInsets.symmetric(horizontal: 14.w),
      decoration: const BoxDecoration(color: kBlack2Color),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 16.w,
            height: 16.h,
            child: Icon(icon, color: kWhiteColor, size: 16),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'InterDisplay',
                fontSize: 12.sp,
                fontWeight: FontWeight.w400,
                color: kWhiteColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper used by long-press handlers that want the standard haptic + menu flow.
Future<void> onEventCardLongPress({
  required BuildContext context,
  required WidgetRef ref,
  required GroupEventCardModel model,
  required Offset globalPosition,
}) async {
  if (!canShowFor(model)) return;
  HapticFeedbackService.contextMenu();
  await showEventContextMenu(
    context: context,
    ref: ref,
    model: model,
    globalPosition: globalPosition,
  );
}
