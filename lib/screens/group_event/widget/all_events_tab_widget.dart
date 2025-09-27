import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../widgets/event_card/completed_event_card.dart';

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

    return ListView.builder(
      controller: widget.scrollController,
      padding: EdgeInsets.only(
        left: 20.sp,
        right: 20.sp,
        bottom: MediaQuery.of(context).viewPadding.bottom + 12.sp,
      ),
      itemCount: widget.filteredEvents.length + (widget.isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == widget.filteredEvents.length) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewPadding.bottom + 20,
            ),
            child: const Center(
              child: CircularProgressIndicator(color: kBoardLightDefault),
            ),
          );
        }
        final tourEventCardModel = widget.filteredEvents[index];

        // Create staggered animation for each item
        final itemAnimation = Tween<Offset>(
          begin: const Offset(0, -0.5),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Interval(
              (index * 0.1).clamp(0.0, 1.0), // Stagger start times
              ((index * 0.1) + 0.6).clamp(0.0, 1.0), // Stagger end times
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

        Widget eventCard;
        switch (tourEventCardModel.tourEventCategory) {
          case TourEventCategory.live:
            eventCard = EventCard(
              tourEventCardModel: tourEventCardModel,
              onTap: () => widget.onSelect(tourEventCardModel),
            );
            break;
          case TourEventCategory.upcoming:
            eventCard = EventCard(
              tourEventCardModel: tourEventCardModel,
              onTap: () => widget.onSelect(tourEventCardModel),
            );
            break;
          case TourEventCategory.ongoing:
            eventCard = EventCard(
              tourEventCardModel: tourEventCardModel,
              onTap: () => widget.onSelect(tourEventCardModel),
            );
            break;
          case TourEventCategory.completed:
            eventCard = CompletedEventCard(
              tourEventCardModel: tourEventCardModel,
              onTap: () => widget.onSelect(tourEventCardModel),
            );
            break;
        } 

        return AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return SlideTransition(
              position: itemAnimation,
              child: FadeTransition(
                opacity: fadeAnimation,
                child: Padding(
                  padding: EdgeInsets.only(bottom: 12.sp),
                  child: eventCard,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
