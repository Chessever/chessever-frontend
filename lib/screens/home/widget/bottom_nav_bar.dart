import 'dart:async';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar_widget.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Main sections, in bar order: Events, Feed, For You, Library. The calendar
/// lives as a compact month in the sidebar.
///
/// Tabs are only ever addressed by value or by [Enum.name] (analytics sends
/// the name), never by index, so reordering the bar moves nothing else.
enum BottomNavBarItem { tournaments, feed, forYou, library }

/// Emitted whenever the user taps the already-selected bottom nav item.
/// Screens that own a scrollable surface for [item] should listen and
/// scroll their active list back to the top. [sequence] increments on
/// every fresh request so repeated re-taps re-fire the listener even
/// when [item] hasn't changed.
class BottomNavBarReTapRequest {
  const BottomNavBarReTapRequest({required this.item, required this.sequence});

  final BottomNavBarItem item;
  final int sequence;
}

class BottomNavBarReTapRequestNotifier
    extends StateNotifier<BottomNavBarReTapRequest> {
  BottomNavBarReTapRequestNotifier()
    : super(
        const BottomNavBarReTapRequest(
          item: BottomNavBarItem.forYou,
          sequence: 0,
        ),
      );

  void request(BottomNavBarItem item) {
    state = BottomNavBarReTapRequest(item: item, sequence: state.sequence + 1);
  }
}

final bottomNavBarReTapRequestProvider = StateNotifierProvider<
  BottomNavBarReTapRequestNotifier,
  BottomNavBarReTapRequest
>((ref) => BottomNavBarReTapRequestNotifier());

final Map<BottomNavBarItem, String> bottomNavBarIcons = {
  BottomNavBarItem.tournaments: SvgAsset.tournamentIcon,
  BottomNavBarItem.feed: SvgAsset.feedNavIcon,
  BottomNavBarItem.forYou: SvgAsset.forYouNavIcon,
  BottomNavBarItem.library: SvgAsset.libraryNavIcon,
};

final namesBottomNavBarIcons = {
  BottomNavBarItem.tournaments: 'Events',
  BottomNavBarItem.feed: 'Feed',
  BottomNavBarItem.forYou: 'For You',
  BottomNavBarItem.library: 'Library',
};

/// The section Home shows. The app opens on For You (its Today page); deep
/// links and notification taps push their screens over Home, so backing out
/// of them lands there too.
final selectedBottomNavBarItemProvider =
    StateProvider.autoDispose<BottomNavBarItem>(
      (ref) => BottomNavBarItem.forYou,
    );

/// Whether the home sidebar (the home Scaffold's drawer) is open, however it
/// was opened: avatar, nav rail or edge swipe. Home reports it through
/// `Scaffold.onDrawerChanged`. A drawer is not a route, so a tab that must
/// pause under it (Feed playback) cannot learn this from RouteAware.
/// Auto-disposed with its last listener, so it can never outlive the shell
/// reading "open".
final homeDrawerOpenProvider = StateProvider.autoDispose<bool>((ref) => false);

class BottomNavBar extends ConsumerWidget {
  const BottomNavBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedItem = ref.watch(selectedBottomNavBarItemProvider);
    // Aspect-specific: `MediaQuery.of` subscribes this bar to viewInsets too,
    // so it rebuilt on every frame of the software keyboard sliding in.
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;

    return Container(
      padding: EdgeInsets.only(top: 0, bottom: bottomPadding),
      decoration: BoxDecoration(
        color: context.colors.background,
        border: Border(
          top: BorderSide(color: context.colors.divider, width: 1.w),
        ),
      ),
      // Design height (70.h) is a floor, not a fixed slot: each nav item is a
      // Column (icon + label + vertical padding) whose label height rides
      // MediaQuery.textScaler. A fixed height that also had the safe-area inset
      // carved out of a capped total starved that Column on short screens /
      // large text scales / large insets and overflowed the bottom. Flooring
      // the row content (so it can grow when it must) and adding the inset on
      // top via padding keeps the normal-device look while never overflowing.
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 70.h),
        child: Row(
          children: [
            for (final item in BottomNavBarItem.values)
              BottomNavBarWidget(
                key: switch (item) {
                  BottomNavBarItem.tournaments => e2eKey(E2eIds.navEvents),
                  BottomNavBarItem.feed => e2eKey(E2eIds.navFeed),
                  BottomNavBarItem.forYou => e2eKey(E2eIds.navForYou),
                  BottomNavBarItem.library => e2eKey(E2eIds.navLibrary),
                },
                width:
                    MediaQuery.sizeOf(context).width /
                    BottomNavBarItem.values.length,
                isSelected: selectedItem == item,
                onTap: () {
                  final previous = ref.read(selectedBottomNavBarItemProvider);
                  if (previous == item) {
                    // Same tab re-tapped: signal screens to scroll their
                    // active list to top. Selected subtab + data are
                    // preserved; no pull-to-refresh, no reload.
                    ref
                        .read(bottomNavBarReTapRequestProvider.notifier)
                        .request(item);
                    return;
                  }

                  ref.read(selectedBottomNavBarItemProvider.notifier).state =
                      item;

                  unawaited(
                    AnalyticsService.instance.trackEvent(
                      'Bottom Nav Changed',
                      properties: {
                        'previous_tab': previous.name,
                        'tab': item.name,
                      },
                    ),
                  );
                },
                svgIcon: bottomNavBarIcons[item]!,
                title: namesBottomNavBarIcons[item]!,
              ),
          ],
        ),
      ),
    );
  }
}
