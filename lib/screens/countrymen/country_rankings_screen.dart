import 'dart:async';

import 'package:chessever2/screens/countrymen/tabs/countrymen_players_tab.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:chessever2/widgets/home_top_bar.dart' show PageTitle;
import 'package:chessever2/widgets/ink_fab.dart' show SearchInkFab;
import 'package:chessever2/widgets/page_back_row.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Reuses the country ranking list with route-local filters and an exact
/// federation code. No pinned or temporary country selection is changed.
///
/// Searched like Countrymen's own Rankings tab: the floating button's glass
/// becomes the field in the header's place, over the same list.
class CountryRankingsScreen extends StatelessWidget {
  const CountryRankingsScreen({super.key, required this.federation});

  final String federation;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        countrymenPlayersProvider.overrideWith(
          (ref) => CountrymenPlayersNotifier(ref, federation: federation),
        ),
      ],
      child: _CountryRankingsPage(federation: federation),
    );
  }
}

/// Inside the route's own [ProviderScope], so the search reaches the
/// federation's list and not the Countrymen screen's.
class _CountryRankingsPage extends ConsumerStatefulWidget {
  const _CountryRankingsPage({required this.federation});

  final String federation;

  @override
  ConsumerState<_CountryRankingsPage> createState() =>
      _CountryRankingsPageState();
}

class _CountryRankingsPageState extends ConsumerState<_CountryRankingsPage>
    with SingleTickerProviderStateMixin {
  /// The header and the search button scroll away with the list and come
  /// back as it scrolls up, as on every other list.
  late final ScrollChromeController _chrome = ScrollChromeController(
    vsync: this,
  );

  final SearchModeController _search = SearchModeController();

  @override
  void dispose() {
    _search.dispose();
    _chrome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final federation = widget.federation;
    final name = CountryUtils.getCountryName(federation);
    CountrymenPlayersNotifier players() =>
        ref.read(countrymenPlayersProvider.notifier);

    return SearchModeHost(
      controller: _search,
      chrome: _chrome,
      debounce: const Duration(milliseconds: 400),
      onQuery: (query) => unawaited(players().search(query)),
      onClose: () => unawaited(players().clearSearch()),
      child: Scaffold(
        backgroundColor: context.colors.background,
        floatingActionButton: SlidingFabs(
          controller: _chrome,
          child: const SearchInkFab(
            key: ValueKey('country_rankings_search_fab'),
            label: 'Search players',
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveHelper.contentMaxWidth,
            ),
            child: Column(
              children: [
                SizedBox(height: MediaQuery.viewPaddingOf(context).top + 4.h),
                CollapsingChrome(
                  controller: _chrome,
                  child: SearchModeHeaderSlot(
                    header: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PageBackRow(
                          title: PageTitle(
                            '${name.isEmpty ? federation : name} rankings',
                            // The flag at its own proportions, inside the
                            // title mark's square.
                            mark: Center(
                              child: FederationFlag(
                                federation: federation,
                                width: PageTitle.markSize,
                                height: PageTitle.markSize * 0.72,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: SearchHeaderMetrics.bottomGap),
                      ],
                    ),
                    search: const SearchModeHeader(
                      hintText: 'Search players',
                      textFieldKey: ValueKey('country_rankings_search_field'),
                      closeKey: ValueKey('country_rankings_search_close'),
                    ),
                  ),
                ),
                Expanded(
                  child: ScrollChromeRegion(
                    controller: _chrome,
                    child: const CountrymenPlayersTab(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
