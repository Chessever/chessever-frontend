import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/tablet_safe_menu.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Actions available from the event card long-press context menu.
enum EventContextAction { about, games, standings, share }

/// Builds the canonical shareable URL for an event, matching the
/// `lichess.org/broadcast/<slug>/<id>` shape but on chessever.com.
String buildEventShareUrl({required String id, required String title}) {
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
  await _handleEventContextAction(
    context: context,
    ref: ref,
    model: model,
    action: action,
  );
}

/// Community events are calendar-only and not backed by a GroupBroadcast,
/// so tapping About/Games/Standings has no destination.
bool canShowFor(GroupEventCardModel model) {
  return model.eventSource != EventSource.communityEvent;
}

List<PopupMenuEntry<EventContextAction>> _buildMenuItems() {
  return [
    _menuItem(
      value: EventContextAction.about,
      label: 'About event',
      icon: Icons.info_outline,
      hasBorder: false,
    ),
    _menuItem(
      value: EventContextAction.games,
      label: 'Games',
      icon: Icons.sports_esports_outlined,
    ),
    _menuItem(
      value: EventContextAction.standings,
      label: 'Standings',
      icon: Icons.emoji_events_outlined,
    ),
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
  bool hasBorder = true,
}) {
  return PopupMenuItem<EventContextAction>(
    value: value,
    padding: EdgeInsets.zero,
    height: 36.h,
    child: _EventMenuRow(label: label, icon: icon, hasBorder: hasBorder),
  );
}

Future<void> _handleEventContextAction({
  required BuildContext context,
  required WidgetRef ref,
  required GroupEventCardModel model,
  required EventContextAction action,
}) async {
  switch (action) {
    case EventContextAction.about:
      await _openTournamentDetail(
        context: context,
        ref: ref,
        model: model,
        mode: TournamentDetailScreenMode.about,
      );
      break;
    case EventContextAction.games:
      await _openTournamentDetail(
        context: context,
        ref: ref,
        model: model,
        mode: TournamentDetailScreenMode.games,
      );
      break;
    case EventContextAction.standings:
      await _openTournamentDetail(
        context: context,
        ref: ref,
        model: model,
        mode: TournamentDetailScreenMode.standings,
      );
      break;
    case EventContextAction.share:
      await _shareEvent(context: context, model: model);
      break;
  }
}

Future<void> _openTournamentDetail({
  required BuildContext context,
  required WidgetRef ref,
  required GroupEventCardModel model,
  required TournamentDetailScreenMode mode,
}) async {
  try {
    final broadcast = await ref
        .read(groupBroadcastRepositoryProvider)
        .getGroupBroadcastById(model.id);

    ref.read(selectedBroadcastModelProvider.notifier).state = broadcast;
    ref.read(selectedTourModeProvider.notifier).state = mode;

    AnalyticsService.instance.trackEventDetached(
      'Event Context Menu Opened Tournament',
      properties: {
        'event_id': model.id,
        'event_name': model.title,
        'target_tab': mode.name,
      },
    );

    if (!context.mounted) return;
    await Navigator.pushNamed(context, '/tournament_detail_screen');
  } catch (e) {
    debugPrint('[EventContextMenu] Failed to open tournament ${model.id}: $e');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Unable to open event'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

Future<void> _shareEvent({
  required BuildContext context,
  required GroupEventCardModel model,
}) async {
  final url = buildEventShareUrl(id: model.id, title: model.title);
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
  const _EventMenuRow({
    required this.label,
    required this.icon,
    required this.hasBorder,
  });

  final String label;
  final IconData icon;
  final bool hasBorder;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 40.h,
      padding: EdgeInsets.symmetric(horizontal: 14.w),
      decoration: BoxDecoration(
        color: kBlack2Color,
        border:
            hasBorder
                ? Border(
                  top: BorderSide(
                    color: const Color(0xFFE2E2E2).withValues(alpha: 0.04),
                    width: 1.w,
                  ),
                )
                : null,
      ),
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
