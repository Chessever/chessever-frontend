import 'dart:async';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/event_mute_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/group_event/widget/appbar_icons_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_pin_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/match_expansion_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/round_expansion_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/utils/tablet_safe_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum TournamentMenuAction {
  focusLiveGames,
  unpinAll,
  pinAll,
  collapseAllRounds,
  expandAllRounds,
  disableNotifications,
  enableNotifications,
}

class TournamentMenuButton extends ConsumerWidget {
  const TournamentMenuButton({
    super.key,
    required this.tourData,
  });

  final TourDetailViewModel tourData;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GlobalKey menuKey = GlobalKey();

    return AppBarIcons(
      key: menuKey,
      padding: EdgeInsets.symmetric(
        horizontal: 2.sp,
        vertical: 1.sp,
      ),
      image: SvgAsset.threeDots,
      onTap: () {
        final RenderBox? renderBox =
            menuKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          final roundIds =
              ref.read(gamesAppBarProvider.notifier).getVisibleRoundIds();
          final matchKeys =
              ref.read(gamesAppBarProvider.notifier).getAllMatchKeys();
          final Offset offset = renderBox.localToGlobal(Offset.zero);

          showTabletSafeMenu(
            context: context,
            position: RelativeRect.fromLTRB(
              offset.dx,
              offset.dy + renderBox.size.height,
              offset.dx + renderBox.size.width,
              offset.dy,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.br),
            ),
            color: kBlack2Color,
            items: _buildRedesignedMenuItems(
              ref,
              context,
              roundIds,
              matchKeys,
              tourData,
            ),
          );
        }
      },
    );
  }

  List<PopupMenuEntry<TournamentMenuAction>> _buildRedesignedMenuItems(
    WidgetRef ref,
    BuildContext context,
    List<String> roundIds,
    List<String> matchKeys,
    TourDetailViewModel tourData,
  ) {
    final List<PopupMenuEntry<TournamentMenuAction>> items = [];

    // 1. Focus on live games
    items.add(
      PopupMenuItem<TournamentMenuAction>(
        value: TournamentMenuAction.focusLiveGames,
        padding: EdgeInsets.zero,
        height: 36.h,
        onTap: () {
          unawaited(
            ref.read(gamesTourScreenProvider.notifier).hideFinishedGames(),
          );
        },
        child: const _MenuDropDownItem(
          text: "Focus on live games",
          fontFamily: 'InterDisplay',
          icon: Icon(
            Icons.center_focus_strong_outlined,
            color: kWhiteColor,
            size: 16,
          ),
          hasBorder: false,
        ),
      ),
    );

    // 2. Pin/Unpin All
    final isAnyPinned =
        ref.read(gamesPinprovider(tourData.aboutTourModel.id)).allPins.isNotEmpty;

    items.add(
      PopupMenuItem<TournamentMenuAction>(
        value: isAnyPinned ? TournamentMenuAction.unpinAll : TournamentMenuAction.pinAll,
        padding: EdgeInsets.zero,
        height: 36.h,
        onTap: () {
          if (isAnyPinned) {
            ref.read(gamesTourScreenProvider.notifier).unpinAllGames();
          } else {
            ref.read(gamesTourScreenProvider.notifier).enableAutoPin();
          }
        },
        child: _MenuDropDownItem(
          text: isAnyPinned ? "Unpin all" : "Pin all",
          icon: SvgPicture.asset(
            isAnyPinned ? SvgAsset.unpine : SvgAsset.pin,
            height: 16.h,
            width: 16.w,
            colorFilter: const ColorFilter.mode(kWhiteColor, BlendMode.srcIn),
          ),
        ),
      ),
    );

    // 3. Expand/Collapse All
    final expandedRounds = ref.read(roundExpansionProvider);
    final isAllCollapsed = roundIds.every((id) => !expandedRounds.containsKey(id));

    items.add(
      PopupMenuItem<TournamentMenuAction>(
        value:
            isAllCollapsed
                ? TournamentMenuAction.expandAllRounds
                : TournamentMenuAction.collapseAllRounds,
        padding: EdgeInsets.zero,
        height: 36.h,
        onTap: () {
          if (isAllCollapsed) {
            ref.read(roundExpansionProvider.notifier).expandAll(roundIds);
            ref.read(matchExpansionProvider.notifier).expandAll();
          } else {
            ref.read(roundExpansionProvider.notifier).collapseAll(roundIds);
            ref.read(matchExpansionProvider.notifier).collapseAll(matchKeys);
          }
        },
        child: _MenuDropDownItem(
          text: isAllCollapsed ? "Expand all" : "Collapse all",
          icon: Icon(
            isAllCollapsed ? Icons.unfold_more : Icons.unfold_less,
            color: kWhiteColor,
            size: 16,
          ),
        ),
      ),
    );

    // 4. Notifications
    final groupBroadcastId = tourData.aboutTourModel.groupBroadcastId;
    if (groupBroadcastId != null && groupBroadcastId.isNotEmpty) {
      final isMuted =
          ref.read(eventMuteProvider(groupBroadcastId)).valueOrNull ?? false;

      items.add(
        PopupMenuItem<TournamentMenuAction>(
          value:
              isMuted
                  ? TournamentMenuAction.enableNotifications
                  : TournamentMenuAction.disableNotifications,
          padding: EdgeInsets.zero,
          height: 36.h,
          onTap: () {
            final isAuthenticated = ref.read(isAuthenticatedProvider);
            if (!isAuthenticated) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(
                const SnackBar(
                  content: Text('Please sign in to manage notifications'),
                ),
              );
              return;
            }
            ref.read(eventMuteProvider(groupBroadcastId).notifier).toggleMute();
          },
          child: _MenuDropDownItem(
            text: isMuted ? "Enable notifications" : "Disable notifications",
            icon: Icon(
              isMuted ? Icons.notifications_none : Icons.notifications_off_outlined,
              color: kWhiteColor,
              size: 16,
            ),
          ),
        ),
      );
    }

    return items;
  }
}

class _MenuDropDownItem extends StatelessWidget {
  final String text;
  final Widget icon;
  final bool hasBorder;
  final String fontFamily;

  const _MenuDropDownItem({
    required this.text,
    required this.icon,
    this.hasBorder = true,
    this.fontFamily = 'SF Pro',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 172.w,
      height: 36.h,
      padding: EdgeInsets.symmetric(horizontal: 8.w),
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            text,
            style: TextStyle(
              fontFamily: fontFamily,
              fontSize: 12.sp,
              fontWeight: FontWeight.w400,
              color: kWhiteColor,
            ),
          ),
          SizedBox(width: 16.w, height: 16.h, child: icon),
        ],
      ),
    );
  }
}
