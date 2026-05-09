import 'dart:async';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/event_mute_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/group_event/widget/appbar_icons_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_pin_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/match_expansion_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/round_expansion_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/utils/tablet_safe_menu.dart';
import 'package:chessever2/widgets/event_card/event_context_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

enum TournamentMenuAction {
  focusLiveGames,
  showAllGames,
  unpinAll,
  pinAll,
  collapseAllRounds,
  expandAllRounds,
  disableNotifications,
  enableNotifications,
  shareEvent,
}

class TournamentMenuButton extends ConsumerWidget {
  const TournamentMenuButton({super.key, required this.tourData});

  final TourDetailViewModel tourData;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GlobalKey menuKey = GlobalKey();

    // Watch mute state here to keep the provider alive while on this screen
    // and ensure ref.read in the onTap gets a synchronous value.
    final groupBroadcastId = tourData.aboutTourModel.groupBroadcastId;
    final isMuted =
        (groupBroadcastId != null && groupBroadcastId.isNotEmpty)
            ? ref.watch(eventMuteProvider(groupBroadcastId)).valueOrNull ??
                false
            : false;

    return AppBarIcons(
      key: menuKey,
      padding: EdgeInsets.symmetric(horizontal: 2.sp, vertical: 1.sp),
      image: SvgAsset.threeDots,
      onTap: () {
        final RenderBox? renderBox =
            menuKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox != null) {
          final visibleRoundIds =
              ref.read(gamesAppBarProvider.notifier).getVisibleRoundIds();
          final allRoundIds =
              ref.read(gamesAppBarProvider.notifier).getAllRoundIdsWithGames();
          final visibleMatchKeys = ref
              .read(gamesAppBarProvider.notifier)
              .getVisibleMatchKeys(visibleRoundIds);
          final allMatchKeys = ref
              .read(gamesAppBarProvider.notifier)
              .getVisibleMatchKeys(allRoundIds);
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
            color: context.colors.surface,
            constraints: BoxConstraints.tightFor(width: 208.w),
            items: _buildRedesignedMenuItems(
              ref,
              context,
              visibleRoundIds,
              visibleMatchKeys,
              allRoundIds,
              allMatchKeys,
              tourData,
              isMuted,
            ),
          );
        }
      },
    );
  }

  List<PopupMenuEntry<TournamentMenuAction>> _buildRedesignedMenuItems(
    WidgetRef ref,
    BuildContext context,
    List<String> visibleRoundIds,
    List<String> visibleMatchKeys,
    List<String> allRoundIds,
    List<String> allMatchKeys,
    TourDetailViewModel tourData,
    bool isMuted,
  ) {
    final List<PopupMenuEntry<TournamentMenuAction>> items = [];

    final gamesScreenState = ref.read(gamesTourScreenProvider).valueOrNull;
    final isFocusingLiveGames =
        gamesScreenState?.gameDisplayMode == GameDisplayMode.hideFinishedGames;

    // 1. Focus on live games / Show all games
    items.add(
      PopupMenuItem<TournamentMenuAction>(
        value:
            isFocusingLiveGames
                ? TournamentMenuAction.showAllGames
                : TournamentMenuAction.focusLiveGames,
        padding: EdgeInsets.zero,
        height: 36.h,
        onTap: () {
          if (isFocusingLiveGames) {
            unawaited(
              ref.read(gamesTourScreenProvider.notifier).showAllGames(),
            );
          } else {
            unawaited(
              ref.read(gamesTourScreenProvider.notifier).hideFinishedGames(),
            );
          }
        },
        child: _MenuDropDownItem(
          text: isFocusingLiveGames ? "Show all games" : "Focus on live games",
          fontFamily: 'InterDisplay',
          icon: Icon(
            isFocusingLiveGames
                ? Icons.format_list_bulleted_outlined
                : Icons.center_focus_strong_outlined,
            color: context.colors.textPrimary,
            size: 16,
          ),
          hasBorder: false,
        ),
      ),
    );

    // 2. Pin/Unpin All
    final isAnyPinned =
        ref
            .read(gamesPinprovider(tourData.aboutTourModel.id))
            .allPins
            .isNotEmpty;

    items.add(
      PopupMenuItem<TournamentMenuAction>(
        value:
            isAnyPinned
                ? TournamentMenuAction.unpinAll
                : TournamentMenuAction.pinAll,
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
            height: 16,
            width: 16,
            colorFilter: const ColorFilter.mode(kWhiteColor, BlendMode.srcIn),
          ),
        ),
      ),
    );

    // 3. Expand/Collapse All
    final roundExpansionState = ref.read(roundExpansionProvider);
    final matchExpansionState = ref.read(matchExpansionProvider);
    final isAllCollapsed = areAllVisibleSectionsCollapsed(
      visibleRoundIds: visibleRoundIds,
      visibleMatchKeys: visibleMatchKeys,
      roundExpansionState: roundExpansionState,
      matchExpansionState: matchExpansionState,
    );

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
            ref.read(roundExpansionProvider.notifier).expandAll(allRoundIds);
            if (allMatchKeys.isNotEmpty) {
              ref.read(matchExpansionProvider.notifier).expandAll();
            }
          } else {
            ref.read(roundExpansionProvider.notifier).collapseAll(allRoundIds);
            if (allMatchKeys.isNotEmpty) {
              ref
                  .read(matchExpansionProvider.notifier)
                  .collapseAll(allMatchKeys);
            }
          }
        },
        child: _MenuDropDownItem(
          text: isAllCollapsed ? "Expand all" : "Collapse all",
          icon: Icon(
            isAllCollapsed ? Icons.unfold_more : Icons.unfold_less,
            color: context.colors.textPrimary,
            size: 16,
          ),
        ),
      ),
    );

    // 4. Notifications
    final groupBroadcastId = tourData.aboutTourModel.groupBroadcastId;
    if (groupBroadcastId != null && groupBroadcastId.isNotEmpty) {
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
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please sign in to manage notifications'),
                ),
              );
              return;
            }
            ref.read(eventMuteProvider(groupBroadcastId).notifier).toggleMute();

            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isMuted
                      ? 'Notifications enabled for this event'
                      : 'Notifications disabled for this event',
                ),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          child: _MenuDropDownItem(
            text: isMuted ? "Enable notifications" : "Disable notifications",
            icon: Icon(
              isMuted
                  ? Icons.notifications_none
                  : Icons.notifications_off_outlined,
              color: context.colors.textPrimary,
              size: 16,
            ),
          ),
        ),
      );
    }

    // 5. Share event
    // We have the active tour (id + slug) in hand here, so we can build the
    // Lichess-mirror URL `<tour.slug>/<tour.id>` directly without an extra
    // database round-trip. `groupBroadcastId` is passed only as the fallback
    // path id used when slug/tourId are missing (legacy events).
    final aboutModel = tourData.aboutTourModel;
    final fallbackId =
        aboutModel.groupBroadcastId?.isNotEmpty == true
            ? aboutModel.groupBroadcastId!
            : aboutModel.id;
    if (fallbackId.isNotEmpty && aboutModel.name.isNotEmpty) {
      items.add(
        PopupMenuItem<TournamentMenuAction>(
          value: TournamentMenuAction.shareEvent,
          padding: EdgeInsets.zero,
          height: 36.h,
          onTap: () {
            final url = buildEventShareUrl(
              id: fallbackId,
              title: aboutModel.name,
              tourId: aboutModel.id,
              tourSlug: aboutModel.slug,
            );
            final box = context.findRenderObject() as RenderBox?;
            final origin =
                box != null
                    ? box.localToGlobal(Offset.zero) & box.size
                    : const Rect.fromLTWH(0, 0, 1, 1);
            Share.share(url, sharePositionOrigin: origin);
          },
          child: _MenuDropDownItem(
            text: "Share event",
            icon: Icon(Icons.ios_share, color: context.colors.textPrimary, size: 16),
          ),
        ),
      );
    }

    return items;
  }
}

@visibleForTesting
bool areAllVisibleSectionsCollapsed({
  required Iterable<String> visibleRoundIds,
  required Iterable<String> visibleMatchKeys,
  required Map<String, bool> roundExpansionState,
  required Map<String, bool> matchExpansionState,
}) {
  final rounds = visibleRoundIds.toList(growable: false);
  final matches = visibleMatchKeys.toList(growable: false);

  if (rounds.isEmpty && matches.isEmpty) {
    return false;
  }

  final areRoundsCollapsed = rounds.every(
    (id) => !(roundExpansionState[id] ?? true),
  );
  final areMatchesCollapsed = matches.every(
    (key) => !resolveMatchExpansionState(matchExpansionState, key),
  );

  return areRoundsCollapsed && areMatchesCollapsed;
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
      width: double.infinity,
      height: 40.h,
      padding: EdgeInsets.symmetric(horizontal: 14.w),
      decoration: BoxDecoration(
        color: context.colors.surface,
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
          SizedBox(width: 16.w, height: 16.h, child: icon),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: 12.sp,
                fontWeight: FontWeight.w400,
                color: context.colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
