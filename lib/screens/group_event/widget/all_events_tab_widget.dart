import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
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

class _AllEventsTabWidgetState extends ConsumerState<AllEventsTabWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    // Start animation when widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _animationController.forward();
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Widget _buildEventCard(GroupEventCardModel tourEventCardModel, int index) {
    // Create staggered animation for each item
    final itemAnimation = Tween<Offset>(
      begin: const Offset(0, -0.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Interval(
          (index * 0.1).clamp(0.0, 1.0),
          ((index * 0.1) + 0.6).clamp(0.0, 1.0),
          curve: Curves.easeOutCubic,
        ),
      ),
    );

    final fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Interval(
          (index * 0.1).clamp(0.0, 1.0),
          ((index * 0.1) + 0.6).clamp(0.0, 1.0),
          curve: Curves.easeOut,
        ),
      ),
    );

    final heroSuffix = 'all-$index';

    Widget eventCard = EventCard(
      tourEventCardModel: tourEventCardModel,
      heroTagSuffix: heroSuffix,
      onTap: () => widget.onSelect(tourEventCardModel),
    );

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return SlideTransition(
          position: itemAnimation,
          child: FadeTransition(
            opacity: fadeAnimation,
            child: eventCard,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.filteredEvents.isEmpty) {
      return const Center(
        child: Text(
          'No tournaments found',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    final isTablet = ResponsiveHelper.isTablet;
    final crossAxisCount = ResponsiveHelper.getGridCrossAxisCount(phoneCount: 1);

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
              // Event cards have variable height, so we use a reasonable aspect ratio
              childAspectRatio: ResponsiveHelper.isLandscape ? 2.2 : 1.8,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final tourEventCardModel = widget.filteredEvents[index];
                return _buildEventCard(tourEventCardModel, index);
              },
              childCount: widget.filteredEvents.length,
            ),
          ),
        ),
        if (widget.isLoadingMore)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomPadding + 20),
              child: const Center(
                child: CircularProgressIndicator(color: kBoardLightDefault),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPhoneListLayout(double bottomPadding) {
    return ListView.builder(
      controller: widget.scrollController,
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
            child: const Center(
              child: CircularProgressIndicator(color: kBoardLightDefault),
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
