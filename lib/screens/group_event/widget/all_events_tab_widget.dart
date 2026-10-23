import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/scroll_cache.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/layout_swap_scroll_keeper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AllEventsTabWidget extends ConsumerStatefulWidget {
  const AllEventsTabWidget({
    required this.filteredEvents,
    required this.onSelect,
    super.key,
    this.isLoadingMore = false,
    this.scrollController,
  });
  final List<GroupEventCardModel> filteredEvents;
  final ValueChanged<GroupEventCardModel> onSelect;
  final bool isLoadingMore;
  final ScrollController? scrollController;

  @override
  ConsumerState<AllEventsTabWidget> createState() => _AllEventsTabWidgetState();
}

class _AllEventsTabWidgetState extends ConsumerState<AllEventsTabWidget> {
  Widget _buildEventCard(GroupEventCardModel tourEventCardModel, int index) {
    // Entrance slide/fade removed: it ran a FadeTransition (saveLayer) per card
    // with a per-index stagger driven off an AnimationController on cold open —
    // the main jank when the Current tab first appears. Cards paint instantly.
    final heroSuffix = 'all-$index';

    return EventCard(
      tourEventCardModel: tourEventCardModel,
      heroTagSuffix: heroSuffix,
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

    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    final isTablet = ResponsiveHelper.isTablet;
    final crossAxisCount = ResponsiveHelper.getGridCrossAxisCount(
      phoneCount: 1,
    );

    // Use grid layout for tablets, list layout for phones. iPhone Duo swaps
    // between them as it closes and opens; the keeper holds the reader's place.
    final useGrid = isTablet && crossAxisCount > 1;
    return LayoutSwapScrollKeeper(
      controller: widget.scrollController,
      layout: useGrid ? crossAxisCount : 1,
      child: useGrid
          ? _buildTabletGridLayout(bottomPadding, crossAxisCount)
          : _buildPhoneListLayout(bottomPadding),
    );
  }

  Widget _buildTabletGridLayout(double bottomPadding, int crossAxisCount) {
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
            bottom: bottomPadding + 12.sp,
          ),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 16.sp,
              mainAxisSpacing: 16.sp,
              // Tablet cards use image-as-background, needs taller aspect ratio
              childAspectRatio: ResponsiveHelper.isLandscape ? 1.4 : 1.2,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final tourEventCardModel = widget.filteredEvents[index];
              return _buildEventCard(tourEventCardModel, index);
            }, childCount: widget.filteredEvents.length),
          ),
        ),
        if (widget.isLoadingMore)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomPadding + 20),
              child: Center(
                child: CircularProgressIndicator(
                  color: context.colors.accentText,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPhoneListLayout(double bottomPadding) {
    return ListView.builder(
      controller: widget.scrollController,
      scrollCacheExtent: kListScrollCacheExtent,
      padding: EdgeInsets.only(
        left: 20.sp,
        right: 20.sp,
        bottom: bottomPadding + 12.sp,
      ),
      itemCount: widget.filteredEvents.length + (widget.isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == widget.filteredEvents.length) {
          return Padding(
            padding: EdgeInsets.only(bottom: bottomPadding + 20),
            child: Center(
              child: CircularProgressIndicator(
                color: context.colors.accentText,
              ),
            ),
          );
        }
        final tourEventCardModel = widget.filteredEvents[index];
        return Padding(
          padding: EdgeInsets.only(bottom: 12.sp),
          child: _buildEventCard(tourEventCardModel, index),
        );
      },
    );
  }
}
