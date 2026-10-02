import 'package:chessever2/screens/collections/collections_tab_provider.dart';
import 'package:chessever2/screens/for_you/providers/for_you_tab_provider.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// One page of a main section, as a start screen remembers it: the tab title
/// the viewer sees and the write that stores it. Each section keeps its own
/// page, so a launch opens the saved section on the page last saved for it.
class StartPage {
  const StartPage({required this.label, required this.save});

  final String label;
  final Future<void> Function() save;
}

StartPage forYouStartPage(ForYouTab tab) =>
    StartPage(label: tab.label, save: () => writeDefaultForYouTab(tab));

StartPage eventsStartPage(GroupEventCategory category) => StartPage(
  label: groupEventCategoryLabel(category),
  save: () => writeDefaultEventsCategory(category),
);

StartPage collectionsStartPage(CollectionsTab tab) =>
    StartPage(label: tab.label, save: () => writeDefaultCollectionsTab(tab));

/// The page [section] is on now: the tab its strip highlights, or the one it
/// comes back to when it is not the visible section.
StartPage currentStartPage(WidgetRef ref, BottomNavBarItem section) {
  switch (section) {
    case BottomNavBarItem.forYou:
      // A search overlays the strip but never replaces the tab under it.
      return forYouStartPage(ref.read(selectedForYouTabProvider));
    case BottomNavBarItem.tournaments:
      final selected = ref.read(selectedGroupCategoryProvider);
      // Search is a transient segment; hold the list it will hand back to.
      final searchTabs = ref.read(groupEventSearchTabControllerProvider);
      final category = eventsHomeCategories.contains(selected)
          ? selected
          : searchTabs.categoryBeforeSearch;
      return eventsStartPage(category);
    case BottomNavBarItem.collections:
      return collectionsStartPage(ref.read(selectedCollectionsTabProvider));
  }
}

/// "Home → Discovery": the section, then the tab inside it.
String startScreenName(BottomNavBarItem section, StartPage page) =>
    '${namesBottomNavBarIcons[section]} → ${page.label}';

/// What assistive technology announces for holding a nav slot or tab title.
String startScreenHint(BottomNavBarItem section, StartPage page) =>
    'Make ${startScreenName(section, page)} the start screen';

/// Premium-gated "hold to make this the launch screen", shared by the phone
/// bar, the tablet rail and the tab titles inside each section. Saves the
/// section and the page: [page] when a tab title was held, otherwise the page
/// the section is on.
Future<void> makeStartScreenDefault(
  BuildContext context,
  WidgetRef ref, {
  required BottomNavBarItem section,
  StartPage? page,
}) async {
  HapticFeedbackService.buttonPress();
  // Read now, not after the paywall: the viewer means the page they held.
  final target = page ?? currentStartPage(ref, section);
  await requirePremiumGuard(
    context,
    ref,
    featureId: 'default_start_tab',
    returnTo: 'home',
    onEntitled: () async {
      if (!context.mounted) return;
      final name = startScreenName(section, target);
      final confirmed = await showSmoothConfirmDialog(
        context: context,
        title: 'Make $name your start screen?',
        message: 'The app will open on $name next time you launch it.',
        confirmText: 'Apply',
      );
      if (confirmed != true || !context.mounted) return;
      await writeDefaultBottomTab(section);
      await target.save();
      HapticFeedbackService.success();
      if (context.mounted) {
        showAppSnack(context, '$name is now your start screen');
      }
    },
  );
}
