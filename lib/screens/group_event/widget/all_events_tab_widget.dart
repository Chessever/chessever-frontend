import 'dart:math' as math;

import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/scroll_cache.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/layout_swap_scroll_keeper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AllEventsTabWidget extends ConsumerStatefulWidget {
  const AllEventsTabWidget({
    required this.filteredEvents,
    required this.onSelect,
    super.key,
    this.isLoadingMore = false,
    this.paged = false,
    this.scrollController,
    this.clearsFloatingButtons = false,
  });
  final List<GroupEventCardModel> filteredEvents;
  final ValueChanged<GroupEventCardModel> onSelect;
  final bool isLoadingMore;

  /// The list pages more in as its end comes near (Past): its end keeps one
  /// slot of one height ([pageSlot]), the spinner in it only while a page
  /// loads, so the list never changes length at the page point (the scroll
  /// chrome would read that as the reader scrolling).
  final bool paged;

  /// The height of a paged list's end slot: the spinner's (36) and the gap
  /// under it.
  static double get pageSlot => 36 + 8.sp;
  final ScrollController? scrollController;

  /// The list floats under the page's buttons (the Events lists' Live
  /// first): its end stays clear of their reach ([InkFabStack.reach]), so
  /// no button ever covers the last card.
  final bool clearsFloatingButtons;

  /// How far the list's last card stays above the bottom edge.
  ///
  /// Clear of the buttons, it is their reach, plus whatever a bar the page
  /// runs under hands it as padding beyond the home indicator's inset (the
  /// reach holds that inset already). Otherwise it is the inset and a gap.
  static double endClearance(
    BuildContext context, {
    required bool clearsFloatingButtons,
  }) {
    final viewInset = MediaQuery.viewPaddingOf(context).bottom;
    if (!clearsFloatingButtons) return viewInset + 12.sp;
    final barShare = math.max(
      0.0,
      MediaQuery.paddingOf(context).bottom - viewInset,
    );
    return InkFabStack.reach(context) + barShare;
  }

  @override
  ConsumerState<AllEventsTabWidget> createState() => _AllEventsTabWidgetState();
}

class _AllEventsTabWidgetState extends ConsumerState<AllEventsTabWidget> {
  Widget _buildEventCard(
    GroupEventCardModel tourEventCardModel,
    int index, {
    bool forceCompactLayout = false,
  }) {
    // Entrance slide/fade removed: it ran a FadeTransition (saveLayer) per card
    // with a per-index stagger driven off an AnimationController on cold open —
    // the main jank when the Current tab first appears. Cards paint instantly.
    final heroSuffix = 'all-$index';

    return EventCard(
      tourEventCardModel: tourEventCardModel,
      heroTagSuffix: heroSuffix,
      forceCompactLayout: forceCompactLayout,
      onTap: () => widget.onSelect(tourEventCardModel),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.filteredEvents.isEmpty) {
      return Center(
        child: Text(
          'No tournaments found',
          style: TextStyle(color: context.colors.textPrimaryMuted),
        ),
      );
    }

    final endClearance = AllEventsTabWidget.endClearance(
      context,
      clearsFloatingButtons: widget.clearsFloatingButtons,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = ResponsiveHelper.adaptive(
          phone: 20.sp,
          tablet: 24.sp,
        );
        final crossAxisCount = ResponsiveHelper.isTablet
            ? ResponsiveHelper.columnsForWidth(
                constraints.maxWidth - horizontalPadding * 2,
                spacing: 16.sp,
              )
            : 1;
        final useGrid = crossAxisCount > 1;
        final cardWidth =
            (constraints.maxWidth -
                horizontalPadding * 2 -
                16.sp * (crossAxisCount - 1)) /
            crossAxisCount;
        return LayoutSwapScrollKeeper(
          controller: widget.scrollController,
          layout: crossAxisCount,
          child: useGrid
              ? _buildTabletGridLayout(
                  endClearance,
                  crossAxisCount,
                  EventCard.gridMainAxisExtent(context, cardWidth),
                )
              : _buildPhoneListLayout(endClearance),
        );
      },
    );
  }

  Widget _buildTabletGridLayout(
    double endClearance,
    int crossAxisCount,
    double cardHeight,
  ) {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 20.sp,
      tablet: 24.sp,
    );

    return CustomScrollView(
      controller: widget.scrollController,
      scrollCacheExtent: kListScrollCacheExtent,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(
            left: horizontalPadding,
            right: horizontalPadding,
            // With the page slot below, it carries the list's end.
            bottom: widget.paged ? 12.sp : endClearance,
          ),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 16.sp,
              mainAxisSpacing: 16.sp,
              mainAxisExtent: cardHeight,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final tourEventCardModel = widget.filteredEvents[index];
              return _buildEventCard(tourEventCardModel, index);
            }, childCount: widget.filteredEvents.length),
          ),
        ),
        if (widget.paged)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(bottom: endClearance),
              child: _pageSlot(context),
            ),
          ),
      ],
    );
  }

  /// A paged list's end slot ([AllEventsTabWidget.paged]).
  Widget _pageSlot(BuildContext context) => SizedBox(
    key: const ValueKey('events_page_slot'),
    height: AllEventsTabWidget.pageSlot,
    child: widget.isLoadingMore
        ? Align(
            alignment: Alignment.topCenter,
            child: CircularProgressIndicator(color: context.colors.accentText),
          )
        : null,
  );

  Widget _buildPhoneListLayout(double endClearance) {
    return ListView.builder(
      controller: widget.scrollController,
      scrollCacheExtent: kListScrollCacheExtent,
      padding: EdgeInsets.only(left: 20.sp, right: 20.sp, bottom: endClearance),
      itemCount: widget.filteredEvents.length + (widget.paged ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == widget.filteredEvents.length) return _pageSlot(context);
        final tourEventCardModel = widget.filteredEvents[index];
        return Padding(
          padding: EdgeInsets.only(bottom: 12.sp),
          child: _buildEventCard(
            tourEventCardModel,
            index,
            forceCompactLayout: true,
          ),
        );
      },
    );
  }
}
