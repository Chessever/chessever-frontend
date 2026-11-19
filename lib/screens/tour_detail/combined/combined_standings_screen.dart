import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/screens/group_event/widget/empty_widget.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/standings/player_standing_section_select.dart';
import 'package:chessever2/screens/tour_detail/widgets/event_games_list_end.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_standings.dart';
import 'package:chessever2/screens/tour_detail/combined/standings_category_scope.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/round_header_widget.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen.dart';
import 'package:chessever2/screens/tour_detail/team_tour/team_tour_screen.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/share_standings.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The Standings tab (and, on a team event, the Players tab) while the event
/// is shown in Combined: every category's own table in one list, under a
/// header that names the category.
///
/// The header of the table being read stays at the top of the list, so the
/// reader always knows whose ranks these are, and one tap folds the table
/// away to bring the next category up. Rows are the single-category tab's
/// own rows, so a table reads the same either way.
///
/// What goes into a section is decided in `combined_standings.dart`.
class CombinedStandingsScreen extends ConsumerStatefulWidget {
  const CombinedStandingsScreen({
    super.key,
    this.view = CombinedStandingsView.standings,
  });

  final CombinedStandingsView view;

  @override
  ConsumerState<CombinedStandingsScreen> createState() =>
      _CombinedStandingsScreenState();
}

class _CombinedStandingsScreenState
    extends ConsumerState<CombinedStandingsScreen>
    with AutomaticKeepAliveClientMixin, ScrollToTopListenerMixin {
  final ScrollController _scrollController = ScrollController();

  /// One per section, to find where its table starts in the list.
  final Map<String, GlobalKey> _sectionKeys = <String, GlobalKey>{};

  @override
  bool get wantKeepAlive => true;

  @override
  void onScrollToTopRequested() {
    animateScrollControllerToTop(_scrollController);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(String sectionId) => _sectionKeys.putIfAbsent(
    sectionId,
    () => GlobalKey(debugLabel: 'combined_standings_$sectionId'),
  );

  void _toggle(String sectionId) {
    final collapsed = ref.read(combinedStandingsCollapsedProvider);
    final folding = !collapsed.contains(sectionId);
    if (folding) _bringHeaderToTop(sectionId);
    ref.read(combinedStandingsCollapsedProvider.notifier).state = folding
        ? <String>{...collapsed, sectionId}
        : (<String>{...collapsed}..remove(sectionId));
  }

  /// Folding a table whose header is held at the top removes the rows the
  /// reader is in the middle of. Left alone, the list would keep its offset
  /// and drop them somewhere in a later category. Moving to where the table
  /// starts leaves the folded header in place with the next category under
  /// it.
  void _bringHeaderToTop(String sectionId) {
    if (!_scrollController.hasClients) return;
    final sliver = _sectionKeys[sectionId]?.currentContext?.findRenderObject();
    if (sliver is! RenderSliver) return;
    final start = sliver.constraints.precedingScrollExtent;
    if (_scrollController.offset > start) _scrollController.jumpTo(start);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final state = ref.watch(combinedStandingsProvider(widget.view));
    // Watched on every path, not only where the folds are drawn: a search,
    // which opens every table, must not cost the reader the folds they had.
    final folded = ref.watch(combinedStandingsCollapsedProvider);
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.sp,
      tablet: 24.sp,
    );

    return Center(
      key: widget.view == CombinedStandingsView.standings
          ? e2eKey(E2eIds.standingsRoot)
          : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: ResponsiveHelper.contentMaxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: _body(context, state, folded),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    CombinedStandingsState state,
    Set<String> folded,
  ) {
    if (state.isLoading) return const StandingsLoadingList();

    final sections = state.sections;
    if (sections.isEmpty) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.only(top: 48.h),
          child: EmptyWidget(
            title: state.isSearching
                ? 'No players or teams found matching your search'
                : 'No data available',
          ),
        ),
      );
    }

    final favorites = ref
        .watch(favoritePlayersProviderNew)
        .maybeWhen(
          data: (players) => players,
          orElse: () => const <FavoritePlayer>[],
          skipLoadingOnRefresh: true,
          skipLoadingOnReload: true,
        );
    // A search opens every table it has a hit in, whatever was folded.
    final collapsed = state.isSearching ? const <String>{} : folded;
    // One table needs no header to tell it from another: the pages of a
    // single board-paginated tournament read as the plain Standings tab.
    final showHeaders = state.tableCount > 1;
    _sectionKeys.removeWhere(
      (id, _) => !sections.any((section) => section.group.id == id),
    );

    return CustomScrollView(
      key: PageStorageKey<String>('combined_standings_${widget.view.name}'),
      controller: _scrollController,
      primary: false,
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: showHeaders ? 4.sp : 8.sp)),
        for (final section in sections)
          _SectionSliver(
            key: _keyFor(section.group.id),
            section: section,
            favorites: favorites,
            showHeader: showHeaders,
            isCollapsed: showHeaders && collapsed.contains(section.group.id),
            isSearching: state.isSearching,
            onToggle: () => _toggle(section.group.id),
          ),
        // Clear of the floating buttons over the table.
        SliverToBoxAdapter(
          child: SizedBox(height: EventGamesListEnd.tableEnd(context)),
        ),
      ],
    );
  }
}

/// One category: its pinned header, then its table.
class _SectionSliver extends StatelessWidget {
  const _SectionSliver({
    super.key,
    required this.section,
    required this.favorites,
    required this.showHeader,
    required this.isCollapsed,
    required this.isSearching,
    required this.onToggle,
  });

  final CombinedStandingsSection section;
  final List<FavoritePlayer> favorites;
  final bool showHeader;
  final bool isCollapsed;
  final bool isSearching;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return StandingsCategoryScope(
      // The selected category's rows behave exactly as on its own tab.
      tourId: section.isSelectedCategory ? null : section.tourId,
      // The group ends the header's hold: it leaves with the last row of
      // its own table instead of sitting over the next category's.
      child: SliverMainAxisGroup(
        slivers: [
          if (showHeader)
            PinnedHeaderSliver(
              child: _SectionHeader(
                section: section,
                isCollapsed: isCollapsed,
                isSearching: isSearching,
                onToggle: onToggle,
              ),
            ),
          if (!isCollapsed) ..._table(context),
          // Air before the next category's header.
          if (showHeader) SliverToBoxAdapter(child: SizedBox(height: 10.sp)),
        ],
      ),
    );
  }

  List<Widget> _table(BuildContext context) {
    if (section.hasError) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(12.sp, 14.sp, 12.sp, 6.sp),
            child: Text(
              "Couldn't load these standings. Pull away and try again.",
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
        ),
      ];
    }

    final officialRound = section.officialRound;
    return [
      if (section.officialSections.isNotEmpty)
        SliverToBoxAdapter(
          child: PlayerStandingSectionSelect(
            tourId: section.tourId,
            sections: section.officialSections,
          ),
        ),
      if (section.showsTeams && officialRound != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(12.sp, 10.sp, 12.sp, 4.sp),
            child: Text(
              'Official standings · after round $officialRound',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      if (section.showsTeams)
        SliverList.builder(
          itemCount: section.teams.length,
          itemBuilder: (context, index) {
            final team = section.teams[index];
            return TeamStandingRow(
              key: ValueKey('team_standing_${team.teamName}'),
              team: team,
            );
          },
        )
      else
        SliverList.builder(
          itemCount: section.players.length,
          itemBuilder: (context, index) => StandingsPlayerRow(
            player: section.players[index],
            favorites: favorites,
          ),
        ),
    ];
  }
}

/// A category's header: its name, how many it ranks, and the fold.
///
/// The same round header the Combined Games list uses, so the two tabs read
/// as one view. It sits on the page's own colour, edge to edge, so rows pass
/// under it without showing around its rounded corners.
class _SectionHeader extends ConsumerWidget {
  const _SectionHeader({
    required this.section,
    required this.isCollapsed,
    required this.isSearching,
    required this.onToggle,
  });

  final CombinedStandingsSection section;
  final bool isCollapsed;
  final bool isSearching;
  final VoidCallback onToggle;

  /// A search shows every hit, so there is nothing to fold until it is
  /// cleared: the header then carries no chevron and takes no tap, rather
  /// than offering a fold that would do nothing.
  VoidCallback? get _fold => isSearching ? null : onToggle;

  String get _count {
    final noun = section.showsTeams ? 'team' : 'player';
    final total = section.total;
    if (isSearching) return '${section.rowCount} of $total';
    return total == 1 ? '1 $noun' : '$total ${noun}s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = section.group.label;
    return ColoredBox(
      color: context.colors.background,
      child: Padding(
        // The header's own shadow falls 2 below it; the padding keeps it
        // whole instead of slicing it at the row that passes under.
        padding: EdgeInsets.only(top: 4.sp, bottom: 6.sp),
        child: CardContextMenu(
          enabled: !section.hasError,
          actions: (menuContext) => [
            if (!isSearching)
              LibraryMenuAction(
                icon: isCollapsed ? Icons.unfold_more : Icons.unfold_less,
                label: isCollapsed ? 'Expand $label' : 'Collapse $label',
                onSelected: onToggle,
              ),
            LibraryMenuAction(
              icon: section.showsTeams
                  ? Icons.groups_outlined
                  : Icons.leaderboard_outlined,
              label: 'Share $label standings',
              onSelected: () => shareCombinedStandingsSection(
                context,
                ref,
                tourId: section.tourId,
                teams: section.showsTeams,
              ),
            ),
          ],
          child: Semantics(
            header: true,
            child: TournamentRoundHeader(
              title: label,
              detail: section.hasError ? null : _count,
              isExpanded: !isCollapsed,
              onToggle: _fold,
              dense: true,
            ),
          ),
        ),
      ),
    );
  }
}
