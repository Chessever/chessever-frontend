import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/analyzed_games_section.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/most_liked_section.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/premium_tour_section.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/smart_events_section.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/todays_miniatures_section.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/whos_hot_section.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/scroll_cache.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The Discovery sections, top to bottom: the community's games and runs
/// first, the day's games next, then what the viewer builds, and what
/// Premium adds after everything it adds to.
enum DiscoverySection {
  mostLiked,

  /// Shown as "Streaks".
  whosHot,
  miniatures,
  analyzed,
  smartEvents,
  premiumTour,
}

/// The sections [DiscoveryView] shows. The Premium tour is for free accounts
/// only: a subscriber already has everything it lists.
List<DiscoverySection> discoverySections({required bool subscribed}) => [
  for (final section in DiscoverySection.values)
    if (section != DiscoverySection.premiumTour || !subscribed) section,
];

/// For You > Discovery: community and editorial surfaces with their Premium
/// boundaries in place. Most liked, Streaks, today's miniatures, analyzed
/// games, Smart Events, and what Premium unlocks.
///
/// One grammar throughout: every section opens with its title and at most
/// one control on the far side; tabs are segment tracks; accent ink is only
/// ever an action; games are the app's own cards under one meta line.
///
/// Every section reads its own data and handles its own loading, empty and
/// failure states, so one failing never blanks the page. The list is lazy:
/// a section below the fold starts its reads only when it comes near.
class DiscoveryView extends ConsumerStatefulWidget {
  const DiscoveryView({super.key, this.scrollController});

  final ScrollController? scrollController;

  @override
  ConsumerState<DiscoveryView> createState() => _DiscoveryViewState();
}

class _DiscoveryViewState extends ConsumerState<DiscoveryView> {
  /// From one section's last ink to the next section's header.
  static double get _gap => 28.w;

  final _mostLikedKey = GlobalKey();
  final _analyzedKey = GlobalKey();

  // Built once and handed back as the same instances, so a parent rebuild
  // (the For You swipe flips its in-view state) skips these sections and
  // their card lists instead of rebuilding them 2-3 times per swipe.
  late final Widget _mostLiked = MostLikedSection(key: _mostLikedKey);
  late final Widget _analyzed = AnalyzedGamesSection(key: _analyzedKey);
  late final Widget _premiumTour = PremiumTourSection(
    onShowMostLiked: _showMostLiked,
    onShowAnalyzed: _showAnalyzed,
  );

  void _showMostLiked() => _reveal(_mostLikedKey);
  void _showAnalyzed() => _reveal(_analyzedKey);

  void _reveal(GlobalKey key) {
    final target = key.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(target);
  }

  Widget _section(DiscoverySection section) {
    return switch (section) {
      DiscoverySection.mostLiked => _mostLiked,
      DiscoverySection.whosHot => const WhosHotSection(),
      DiscoverySection.premiumTour => _premiumTour,
      DiscoverySection.miniatures => const TodaysMiniaturesSection(),
      DiscoverySection.smartEvents => const SmartEventsSection(),
      DiscoverySection.analyzed => _analyzed,
    };
  }

  @override
  Widget build(BuildContext context) {
    final subscribed = ref.watch(
      subscriptionProvider.select((s) => s.isSubscribed),
    );
    final sections = discoverySections(subscribed: subscribed);

    return RefreshIndicator(
      color: context.colors.accentText,
      backgroundColor: context.colors.surface,
      onRefresh: () async => refreshDiscovery(ref),
      child: ListView.builder(
        controller: widget.scrollController,
        scrollCacheExtent: kListScrollCacheExtent,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: EdgeInsets.only(top: 4.w, bottom: 32.w),
        itemCount: sections.length,
        // Each item is its own slot, which adds these itself: the slot must
        // be the list's child so a trimmed last line keeps its full target.
        addRepaintBoundaries: false,
        addSemanticIndexes: false,
        itemBuilder: (context, index) {
          final section = sections[index];
          // One rhythm between sections, measured from ink: the slot gives
          // back the room under a last line of text (an upgrade line, a
          // notice), so it sits as far from the next title as a card does.
          return DiscoverySectionSlot(
            key: ValueKey(section),
            child: IndexedSemantics(
              index: index,
              child: RepaintBoundary(
                child: Padding(
                  padding: EdgeInsets.only(top: index == 0 ? 0 : _gap),
                  child: _section(section),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
