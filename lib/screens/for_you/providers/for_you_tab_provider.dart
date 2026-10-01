import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The For You section's pages, in segment order.
enum ForYouTab { mySpace, today, discovery }

extension ForYouTabLabel on ForYouTab {
  String get label => switch (this) {
    ForYouTab.mySpace => 'My Space',
    ForYouTab.today => 'Today',
    ForYouTab.discovery => 'Discovery',
  };
}

/// Legacy: where older builds remembered the last For You page. Nothing reads
/// or writes it any more; the key stays only so Home can drop a value an
/// older build left on the device (see `forgetForYouPageForLaunch`).
const String forYouLastTabPrefsKey = 'for_you_last_tab_v1';

/// Every launch lands on the stored default (Today unless a Premium viewer
/// picked another in Settings › Customization).
const ForYouTab kDefaultForYouTab = ForYouTab.today;

/// The launch Home page a Premium viewer picked. Unset or unreadable means
/// Today.
const String defaultForYouTabPrefsKey = 'default_foryou_tab_v1';

ForYouTab readDefaultForYouTab() {
  final name = SharedPreferencesService.instance.prefsOrNull?.getString(
    defaultForYouTabPrefsKey,
  );
  if (name == null) return kDefaultForYouTab;
  for (final tab in ForYouTab.values) {
    if (tab.name == name) return tab;
  }
  return kDefaultForYouTab;
}

Future<void> writeDefaultForYouTab(ForYouTab tab) async {
  final prefs =
      SharedPreferencesService.instance.prefsOrNull ??
      await SharedPreferencesService.instance.ensureInitialized();
  await prefs?.setString(defaultForYouTabPrefsKey, tab.name);
}

/// Selected For You page. It starts on [initial] (the stored default unless
/// a caller says otherwise) and lives in memory afterwards: within a
/// session the provider below keeps the user's page.
class ForYouTabController extends StateNotifier<ForYouTab> {
  ForYouTabController([ForYouTab? initial])
    : super(initial ?? readDefaultForYouTab());

  void select(ForYouTab tab) {
    if (tab == state) return;
    state = tab;
  }
}

/// Kept alive for the session so leaving For You and coming back lands on the
/// same page.
final selectedForYouTabProvider =
    StateNotifierProvider<ForYouTabController, ForYouTab>(
      (ref) => ForYouTabController(),
    );

/// The query behind the For You header's transient Search page. Non-empty
/// exactly while that page is showing: picking a regular tab clears it, and
/// clearing it returns to [selectedForYouTabProvider]'s tab, which a search
/// never overwrites. Resets whenever the For You screen leaves the tree.
final forYouSearchQueryProvider = StateProvider.autoDispose<String>(
  (ref) => '',
);

/// True while the For You pager shows any part of Today, set by the shell as
/// the pages move. A swipe hands the selection over at the halfway mark, so
/// this keeps Today drawn while it is still half in view on either side of
/// that handover. Resets whenever the For You screen leaves the tree.
final forYouTodayInViewProvider = StateProvider.autoDispose<bool>(
  (ref) => false,
);

/// True while For You is the selected main section and Today is its visible
/// page (not covered by the Search page). The Today feed
/// (`ForYouGamesWidget`) gates its live subscriptions and the
/// `forYouSurfaceVisibleProvider` signal on this, together with its own route
/// and app-lifecycle checks.
final forYouTodayTabActiveProvider = Provider.autoDispose<bool>((ref) {
  final onForYou = ref.watch(
    selectedBottomNavBarItemProvider.select(
      (item) => item == BottomNavBarItem.forYou,
    ),
  );
  if (!onForYou) return false;
  final todayShown =
      ref.watch(selectedForYouTabProvider) == ForYouTab.today ||
      ref.watch(forYouTodayInViewProvider);
  if (!todayShown) return false;
  return ref.watch(forYouSearchQueryProvider.select((q) => q.isEmpty));
});
