/// The Collections page's tabs, in order.
enum CollectionsTab { about, collections, authors }

extension CollectionsTabLabel on CollectionsTab {
  String get label => switch (this) {
    CollectionsTab.about => 'About',
    CollectionsTab.collections => 'Collections',
    CollectionsTab.authors => 'Authors',
  };
}
