import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/scroll_cache.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/event_card/smart_event_card.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class AllEventsTabWidget extends ConsumerStatefulWidget {
  const AllEventsTabWidget({
    required this.filteredEvents,
    required this.onSelect,
    super.key,
    this.isLoadingMore = false,
    this.scrollController,
    this.smartData,
  });
  final List<GroupEventCardModel> filteredEvents;
  final ValueChanged<GroupEventCardModel> onSelect;
  final bool isLoadingMore;
  final ScrollController? scrollController;
  final SmartEventCardData? smartData;

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

  Widget _buildSmartCard(SmartEventCardData smartData) {
    // Subtract tournaments the user hid from this smart event so the card
    // count matches the About tab (and survives restarts via the same store).
    final hidden = ref.watch(
      smartEventDismissedEventIdsProvider(smartData.request.dismissScopeId),
    );
    final visibleCount =
        smartData.request.events.where((e) => !hidden.contains(e.id)).length;
    return SmartEventCard(
      tierLabel: smartData.request.tierLabel,
      minElo: smartData.request.minElo,
      liveCount: visibleCount,
      avgElo: smartData.avgElo,
      titleSuffix: smartData.request.titleSuffix,
      caption: smartData.request.caption,
      countSingular: smartData.request.countSingular,
      countPlural: smartData.request.countPlural,
      accentColor: smartEventAccentColor(smartData.request.scopeId),
      onTap:
          () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SmartEventScreen(request: smartData.request),
            ),
          ),
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

    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    final isTablet = ResponsiveHelper.isTablet;
    final crossAxisCount = ResponsiveHelper.getGridCrossAxisCount(
      phoneCount: 1,
    );

    // Use grid layout for tablets, list layout for phones
    if (isTablet && crossAxisCount > 1) {
      return _buildTabletGridLayout(bottomPadding, crossAxisCount);
    }

    return _buildPhoneListLayout(bottomPadding);
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
        if (widget.smartData != null)
          SliverPadding(
            padding: EdgeInsets.only(
              left: horizontalPadding,
              right: horizontalPadding,
              bottom: 16.sp,
            ),
            sliver: SliverToBoxAdapter(
              child: _buildSmartCard(widget.smartData!),
            ),
          ),
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
                  color:
                      context.isLightTheme ? kPrimaryColor : kBoardLightDefault,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPhoneListLayout(double bottomPadding) {
    final smartOffset = widget.smartData != null ? 1 : 0;
    return ListView.builder(
      controller: widget.scrollController,
      scrollCacheExtent: kListScrollCacheExtent,
      padding: EdgeInsets.only(
        left: 20.sp,
        right: 20.sp,
        bottom: bottomPadding + 12.sp,
      ),
      itemCount:
          widget.filteredEvents.length +
          smartOffset +
          (widget.isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (widget.smartData != null && index == 0) {
          return Padding(
            padding: EdgeInsets.only(bottom: 12.sp),
            child: _buildSmartCard(widget.smartData!),
          );
        }

        if (index == widget.filteredEvents.length + smartOffset) {
          return Padding(
            padding: EdgeInsets.only(bottom: bottomPadding + 20),
            child: const Center(
              child: CircularProgressIndicator(color: kBoardLightDefault),
            ),
          );
        }
        final tourEventCardModel = widget.filteredEvents[index - smartOffset];
        return Padding(
          padding: EdgeInsets.only(bottom: 12.sp),
          child: _buildEventCard(tourEventCardModel, index),
        );
      },
    );
  }
}
