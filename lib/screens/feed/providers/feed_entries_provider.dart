import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/feed/models/feed_entry.dart';
import 'package:chessever2/screens/feed/providers/feed_provider.dart';
import 'package:chessever2/services/feed_ads_config.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The Feed tab renders the backend's order.
final feedEntriesProvider =
    NotifierProvider<FeedEntriesNotifier, List<FeedEntry>>(
      FeedEntriesNotifier.new,
    );

class FeedEntriesNotifier extends Notifier<List<FeedEntry>> {
  @override
  List<FeedEntry> build() {
    final items = ref.watch(feedProvider).valueOrNull ?? const [];
    final entries = ref.read(feedProvider.notifier).serverEntries;
    return entries ?? [for (final item in items) FeedGameEntry(item)];
  }
}

/// Honor the backend's ad placements and the app's subscription and ad checks.
final feedPagesProvider = Provider<List<FeedEntry>>(
  (ref) => serverFeedPages(
    ref.watch(feedEntriesProvider),
    adsVisible: ref.watch(feedAdsVisibleProvider),
    withdrawn: ref.watch(feedAdWithdrawnProvider),
  ),
);

/// Platform/configuration availability, separate from subscriber eligibility.
final feedAdsAvailableProvider = Provider<bool>(
  (ref) => FeedAdsConfig.available,
);

/// Whether Feed shows ads between its posts: on Android and iOS, to a viewer
/// without a paid subscription (even with temporary rewarded Premium access),
/// once the subscription has first been checked. Later checks (a purchase,
/// a restore) do not take the ads away while they run.
final feedAdsVisibleProvider = NotifierProvider<FeedAdsVisibleNotifier, bool>(
  FeedAdsVisibleNotifier.new,
);

class FeedAdsVisibleNotifier extends Notifier<bool> {
  bool _checked = false;

  @override
  bool build() {
    if (!ref.watch(feedAdsAvailableProvider)) return false;
    final loading = ref.watch(
      subscriptionProvider.select((state) => state.isLoading),
    );
    _checked = _checked || !loading;
    return _checked &&
        !ref.watch(subscriptionProvider.select((state) => state.isSubscribed));
  }
}

/// Ad pages whose ad did not come (no fill, no consent, offline): left out
/// of [feedPagesProvider], so Feed never stands an empty page in the way.
final feedAdWithdrawnProvider = StateProvider<Set<String>>(
  (ref) => const <String>{},
);
