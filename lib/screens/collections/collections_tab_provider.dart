import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The Collections section's pages, in segment order.
enum CollectionsTab { about, collections, authors }

extension CollectionsTabLabel on CollectionsTab {
  String get label => switch (this) {
    CollectionsTab.about => 'About',
    CollectionsTab.collections => 'Collections',
    CollectionsTab.authors => 'Authors',
  };
}

/// Where the section opens unless a Premium viewer picked another page (hold
/// a tab title, or hold the Collections tab while on it).
const CollectionsTab kDefaultCollectionsTab = CollectionsTab.collections;

const String defaultCollectionsTabPrefsKey = 'default_collections_tab_v1';

CollectionsTab readDefaultCollectionsTab() {
  final name = SharedPreferencesService.instance.prefsOrNull?.getString(
    defaultCollectionsTabPrefsKey,
  );
  if (name == null) return kDefaultCollectionsTab;
  for (final tab in CollectionsTab.values) {
    if (tab.name == name) return tab;
  }
  return kDefaultCollectionsTab;
}

Future<void> writeDefaultCollectionsTab(CollectionsTab tab) async {
  final prefs =
      SharedPreferencesService.instance.prefsOrNull ??
      await SharedPreferencesService.instance.ensureInitialized();
  await prefs?.setString(defaultCollectionsTabPrefsKey, tab.name);
}

/// The page the embedded Collections section is showing. It opens on the
/// stored default and lives for the session, so leaving Collections and
/// coming back lands on the same page, like Home and Events.
final selectedCollectionsTabProvider = StateProvider<CollectionsTab>(
  (ref) => readDefaultCollectionsTab(),
);
