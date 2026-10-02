import 'dart:async';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar_widget.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/paywall/home_customization_access.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Main sections: Home, Events, Collections. The calendar opens
/// from the sidebar, and Feed from For You › Discovery.
///
/// Tabs are only ever addressed by value or by [Enum.name] (analytics sends
/// the name), never by index, so reordering the bar moves nothing else.
enum BottomNavBarItem {
  tournaments,
  forYou,
  collections;

  // Source compatibility for integrations compiled against the previous tab.
  @Deprecated(
    'Library is reached through My Space; use collections for the main tab',
  )
  static const library = collections;
}

/// Keep enum identities stable for callers; presentation has its own order.
const bottomNavBarOrder = [
  BottomNavBarItem.forYou,
  BottomNavBarItem.tournaments,
  BottomNavBarItem.collections,
];

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

final bottomNavBarReTapRequestProvider =
    StateNotifierProvider<
      BottomNavBarReTapRequestNotifier,
      BottomNavBarReTapRequest
    >((ref) => BottomNavBarReTapRequestNotifier());

final Map<BottomNavBarItem, String> bottomNavBarIcons = {
  BottomNavBarItem.tournaments: SvgAsset.tournamentIcon,
  BottomNavBarItem.forYou: SvgAsset.forYouNavIcon,
  BottomNavBarItem.collections: 'assets/svgs/collections_nav.svg',
};

final namesBottomNavBarIcons = {
  BottomNavBarItem.tournaments: 'Events',
  BottomNavBarItem.forYou: 'Home',
  BottomNavBarItem.collections: 'Collections',
};

/// The section Home shows. The app opens on the stored default
/// ([readDefaultBottomTab], For You unless the viewer picked another); deep
/// links and notification taps push their screens over Home, so backing out
/// of them lands there too.
final selectedBottomNavBarItemProvider =
    StateProvider.autoDispose<BottomNavBarItem>(
      (ref) => readDefaultBottomTab(),
    );

/// The launch section a Premium viewer picked (long-press a tab, or Settings
/// › Customization). Unset or unreadable means For You.
const String defaultBottomTabPrefsKey = 'default_bottom_tab_v1';

BottomNavBarItem readDefaultBottomTab() {
  final name = SharedPreferencesService.instance.prefsOrNull?.getString(
    defaultBottomTabPrefsKey,
  );
  if (name == null) return BottomNavBarItem.forYou;
  for (final item in BottomNavBarItem.values) {
    if (item.name == name) return item;
  }
  return BottomNavBarItem.forYou;
}

Future<void> writeDefaultBottomTab(BottomNavBarItem item) async {
  final prefs =
      SharedPreferencesService.instance.prefsOrNull ??
      await SharedPreferencesService.instance.ensureInitialized();
  await prefs?.setString(defaultBottomTabPrefsKey, item.name);
}

/// Premium-gated "hold a tab to make it the launch section", shared by the
/// phone bar and the tablet rail.
Future<void> makeBottomTabDefault(
  BuildContext context,
  WidgetRef ref,
  BottomNavBarItem item,
) async {
  HapticFeedbackService.buttonPress();
  await ensureHomeCustomizationAccess(
    context,
    ref,
    featureId: 'default_start_tab',
    returnTo: 'home',
    onEntitled: () async {
      if (!context.mounted) return;
      final name = namesBottomNavBarIcons[item]!;
      final confirmed = await showSmoothConfirmDialog(
        context: context,
        title: 'Make $name your start screen?',
        message: 'The app will open on $name next time you launch it.',
        confirmText: 'Apply',
      );
      if (confirmed != true || !context.mounted) return;
      await writeDefaultBottomTab(item);
      HapticFeedbackService.success();
      if (context.mounted) {
        showAppSnack(
          context,
          '${namesBottomNavBarIcons[item]} is now your start screen',
        );
      }
    },
  );
}

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
      // Keep comfortable touch targets plus the device's bottom safe area.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            for (final item in bottomNavBarOrder)
              BottomNavBarWidget(
                key: switch (item) {
                  BottomNavBarItem.tournaments => e2eKey(E2eIds.navEvents),
                  BottomNavBarItem.forYou => e2eKey(E2eIds.navForYou),
                  BottomNavBarItem.collections => e2eKey(E2eIds.navCollections),
                },
                width:
                    MediaQuery.sizeOf(context).width / bottomNavBarOrder.length,
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
                icon: item == BottomNavBarItem.forYou
                    ? Icons.home_rounded
                    : null,
                title: namesBottomNavBarIcons[item]!,
                onLongPress: () =>
                    unawaited(makeBottomTabDefault(context, ref, item)),
              ),
          ],
        ),
      ),
    );
  }
}
