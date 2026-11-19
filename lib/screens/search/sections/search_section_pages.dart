import 'package:chessever2/screens/collections/collections_screen.dart';
import 'package:chessever2/screens/favorites/favorites_tab_screen.dart';
import 'package:chessever2/screens/favorites/provider/favorites_mode_provider.dart';
import 'package:chessever2/screens/for_you/discovery/news_screen.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart'
    show GroupEventCategory, selectedGroupCategoryProvider;
import 'package:chessever2/screens/group_event/providers/home_live_first_provider.dart'
    show homeEventsLiveFirstProvider;
import 'package:chessever2/screens/my_profile/profile_hub_screen.dart'
    show eventsScreenRoute;
import 'package:chessever2/screens/my_space/actions/space_star_pin.dart'
    show SpaceStarPins;
import 'package:chessever2/screens/search/sections/search_openings_page.dart';
import 'package:chessever2/screens/search/sections/search_smart_events_page.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/home_top_bar.dart' show PageTitle;
import 'package:chessever2/widgets/page_back_row.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart'
    show SearchHeaderMetrics;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The sections of the Search tab's landing that open a page of their own,
/// each named as its head reads and keyed by [slug] (`search-<slug>-…`).
enum SearchSectionId {
  liveNow('live', 'Live now'),
  topPlayers('top-players', 'Top players'),
  openings('openings', 'Openings'),
  smartEvents('smart', 'Smart events'),
  comingUp('upcoming', 'Coming up'),
  collections('collections', 'Collections'),
  news('news', 'News');

  const SearchSectionId(this.slug, this.title);

  final String slug;
  final String title;
}

/// Opens [section]'s own page: the page the app already has for it where
/// there is one, the section's cards down a page of their own where there
/// is not.
///
/// * Live now: Events on Current, its live events first while the page is
///   open ([_openLiveFirst]).
/// * Top players: Rankings, as Profile opens it.
/// * Openings: every opening as its smart event ([SearchOpeningsPage]);
///   [onOpening] opens one (the tab remembers the pick).
/// * Smart events: every built-in smart event ([SearchSmartEventsPage]).
/// * Coming up: Events on Upcoming.
/// * Collections: the Collections page.
/// * News: the News page.
Future<void> openSearchSectionPage(
  BuildContext context,
  SearchSectionId section, {
  ValueChanged<OpeningSearchSelection>? onOpening,
}) {
  FocusScope.of(context).unfocus();
  HapticFeedbackService.navigation();
  final navigator = Navigator.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  Future<void> push(Widget page) =>
      navigator.push(MaterialPageRoute<void>(builder: (_) => page));
  switch (section) {
    case SearchSectionId.liveNow:
      container.read(selectedGroupCategoryProvider.notifier).state =
          GroupEventCategory.current;
      return _openLiveFirst(container, navigator);
    case SearchSectionId.comingUp:
      container.read(selectedGroupCategoryProvider.notifier).state =
          GroupEventCategory.upcoming;
      return navigator.push(eventsScreenRoute());
    case SearchSectionId.topPlayers:
      return push(
        const FavoritesTabScreen(initialMode: FavoritesScreenMode.players),
      );
    case SearchSectionId.openings:
      return push(SearchOpeningsPage(onOpening: onOpening));
    case SearchSectionId.smartEvents:
      return push(const SearchSmartEventsPage());
    case SearchSectionId.collections:
      return push(const CollectionsScreen());
    case SearchSectionId.news:
      return NewsScreen.open(context);
  }
}

/// Events on Current with its live events first, for as long as the page is
/// open.
///
/// Live first is one flag for the session ([homeEventsLiveFirstProvider]),
/// shared with Home's Today feed, so Search only borrows it: when the page
/// closes it goes back to what it was, and Home is as the reader left it.
/// Already on, it is left alone; pressed on the Events page (its own Live
/// first capsule), it is the reader's and stays as they set it.
Future<void> _openLiveFirst(
  ProviderContainer container,
  NavigatorState navigator,
) async {
  final flag = container.read(homeEventsLiveFirstProvider.notifier);
  if (flag.state) return navigator.push<void>(eventsScreenRoute());
  flag.state = true;
  var pressed = false;
  final watch = container.listen<bool>(
    homeEventsLiveFirstProvider,
    (_, __) => pressed = true,
  );
  try {
    await navigator.push<void>(eventsScreenRoute());
  } finally {
    watch.close();
    if (!pressed) {
      container.read(homeEventsLiveFirstProvider.notifier).state = false;
    }
  }
}

/// A pushed page of one Search section's cards: the back row every pushed
/// page wears ([PageBackRow], named in [PageTitle]'s voice), stepping away
/// as the list scrolls and back, then [sliver] on the page's gutter, ending
/// clear of the bottom inset ([MediaQuery.paddingOf]).
class SearchSectionPageScaffold extends HookWidget {
  const SearchSectionPageScaffold({
    super.key,
    required this.title,
    required this.sliver,
  });

  final String title;
  final Widget sliver;

  @override
  Widget build(BuildContext context) {
    final chrome = useScrollChromeController();
    final gutter = SearchHeaderMetrics.gutter;
    return Scaffold(
      backgroundColor: context.colors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: Column(
            children: [
              // The status bar's inset stays put: the bar folds up to it.
              SizedBox(height: MediaQuery.viewPaddingOf(context).top + 4.h),
              CollapsingChrome(
                controller: chrome,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PageBackRow(title: PageTitle(title)),
                    SizedBox(height: SearchHeaderMetrics.bottomGap),
                  ],
                ),
              ),
              Expanded(
                child: ScrollChromeRegion(
                  controller: chrome,
                  // Still the Search tab's: a star here keeps its event or
                  // smart event in My Space, as the same card's star does
                  // on the landing.
                  child: SpaceStarPins(
                    child: CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(gutter, 4.h, gutter, 0),
                          sliver: sliver,
                        ),
                        // The last card ends clear of whatever floats over
                        // the page's foot (the dock, the home indicator),
                        // whose height arrives as the bottom inset.
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: 24.h + MediaQuery.paddingOf(context).bottom,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
