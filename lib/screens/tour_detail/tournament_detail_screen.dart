import 'package:chessever2/main.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_scroll_provider.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen.dart';
import 'package:chessever2/screens/tour_detail/about_tour_screen.dart';
import 'package:chessever2/screens/tour_detail/games_tour/views/games_tour_screen.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_app_bar_widget.dart';
import 'package:chessever2/screens/tour_detail/widget/text_dropdown_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class TournamentDetailScreen extends ConsumerStatefulWidget {
  const TournamentDetailScreen({super.key});

  @override
  ConsumerState<TournamentDetailScreen> createState() =>
      _TournamentDetailViewState();
}

class _TournamentDetailViewState extends ConsumerState<TournamentDetailScreen>
    with RouteAware {
  late PageController pageController;

  @override
  void didPush() {
    Future.microtask(() {
      ref.read(shouldStreamProvider.notifier).state = true;
    });
    super.didPush();
  }

  @override
  void didPop() {
    Future.microtask(() {
      ref.read(shouldStreamProvider.notifier).state = false;
    });
    super.didPop();
  }

  @override
  void didPopNext() {
    Future.microtask(() {
      ref.read(shouldStreamProvider.notifier).state = true;
    });
    super.didPopNext();
  }

  @override
  void didPushNext() {
    Future.microtask(() {
      ref.read(shouldStreamProvider.notifier).state = false;
    });
    super.didPushNext();
  }

  @override
  void didChangeDependencies() {
    routeObserver.subscribe(this, ModalRoute.of(context)!);
    super.didChangeDependencies();
  }

  @override
  void initState() {
    pageController = PageController(initialPage: 1);
    super.initState();
  }

  @override
  void deactivate() {
    _cleanupProviders();
    super.deactivate();
  }

  void _cleanupProviders() {
    try {
      ref.invalidate(selectedTourModeProvider);
      ref.invalidate(gamesTourProvider);
      ref.invalidate(selectedBroadcastModelProvider);
      ref.invalidate(userSelectedRoundProvider);
      ref.invalidate(tourDetailScreenProvider);
      ref.invalidate(gamesAppBarProvider);
      ref.invalidate(gamesTourScreenProvider);
      ref.invalidate(playerTourScreenProvider);
      ref.invalidate(searchQueryProvider);
      ref.invalidate(gamesTourScrollProvider);
    } catch (e) {
      // Ignore errors during cleanup
      print('Error during provider cleanup: $e');
    }
  }

  @override
  void dispose() {
    pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedTourMode = ref.watch(selectedTourModeProvider);
    final tourDetailAsync = ref.watch(tourDetailScreenProvider);
    return ScreenWrapper(
      child: Scaffold(
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: MediaQuery.of(context).viewPadding.top + 4.h),
            tourDetailAsync.when(
              data: (data) => _buildSuccessAppBar(data, selectedTourMode),
              error: (error, stackTrace) => _buildErrorAppBar(error),
              loading: () => const _LoadingAppBarWithTitle(title: "Chessever"),
            ),
            Expanded(
              child: PageView.builder(
                controller: pageController,
                itemCount: 3,
                onPageChanged: _handlePageChanged,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return AboutTourScreen();
                  } else if (index == 1) {
                    return GamesTourScreen();
                  } else if (index == 2) {
                    return PlayerTourScreen();
                  } else {
                    return Center(
                      child: Text(
                        'Invalid page index: $index',
                        style: TextStyle(color: kWhiteColor),
                      ),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessAppBar(
    TourDetailViewModel data,
    TournamentDetailScreenMode selectedTourMode,
  ) {
    return Column(
      children: [
        selectedTourMode == TournamentDetailScreenMode.about
            ? _TourDetailDropDownAppBar(data: data)
            : selectedTourMode == TournamentDetailScreenMode.games
            ? const GamesAppBarWidget()
            : _TourDetailDropDownAppBar(data: data),
        SizedBox(height: 8.h),
        _buildSegmentedSwitcher(
          selectedTourMode,
          (index) => _handleTabSelection(index),
        ),
      ],
    );
  }

  Widget _buildErrorAppBar(Object error) {
    return Column(
      children: [
        _LoadingAppBarWithTitle(
          title: "Error: ${error.toString().substring(0, 20)}...",
        ),
        SizedBox(height: 8.h),
        _buildSegmentedSwitcher(TournamentDetailScreenMode.games, (index) {}),
      ],
    );
  }

  Widget _buildSegmentedSwitcher(
    TournamentDetailScreenMode selectedTourMode,
    ValueChanged<int> onChanged,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.sp),
      child: SegmentedSwitcher(
        key: UniqueKey(),
        backgroundColor: kPopUpColor,
        selectedBackgroundColor: kPopUpColor,
        options: _mappedName.values.toList(),
        initialSelection: _mappedName.values.toList().indexOf(
          _mappedName[selectedTourMode]!,
        ),
        onSelectionChanged: onChanged,
      ),
    );
  }

  void _handleTabSelection(int index) {
    try {
      // Update state after animation starts
      ref
          .read(selectedTourModeProvider.notifier)
          .update((_) => TournamentDetailScreenMode.values[index]);
      // Animate to the selected page first
      pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } catch (e) {
      print('Error handling tab selection: $e');
    }
  }

  void _handlePageChanged(int index) {
    try {
      // Update the selected mode when page changes (from swiping)
      final currentModeIndex = TournamentDetailScreenMode.values.indexOf(
        ref.read(selectedTourModeProvider),
      );

      if (currentModeIndex != index) {
        ref
            .read(selectedTourModeProvider.notifier)
            .update((_) => TournamentDetailScreenMode.values[index]);
      }
    } catch (e) {
      print('Error handling page change: $e');
    }
  }
}

class _TourDetailDropDownAppBar extends ConsumerWidget {
  const _TourDetailDropDownAppBar({required this.data, super.key});

  final TourDetailViewModel data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Null safety check for tours
    if (data.tours.isEmpty) {
      return _buildErrorAppBar(context, 'No tournaments available');
    }

    final defaultTourId = data.tours.first.tour.id;
    final selectedTourId =
        ref.watch(tourDetailScreenProvider).value?.aboutTourModel.id ??
        defaultTourId;

    return Row(
      children: [
        SizedBox(width: 16.w),
        IconButton(
          iconSize: 24.ic,
          padding: EdgeInsets.zero,
          onPressed: () => _handleBackPress(context),
          icon: Icon(Icons.arrow_back_ios_new_outlined, size: 24.ic),
        ),
        const Spacer(),
        SizedBox(
          height: 32.h,
          width: 230.w,
          child: TextDropDownWidget(
            items: _buildDropdownItems(data.tours),
            selectedId: selectedTourId,
            onChanged: (value) => _handleDropdownChange(ref, value),
          ),
        ),
        const Spacer(),
        SizedBox(width: 44.w),
      ],
    );
  }

  List<Map<String, String>> _buildDropdownItems(List<TourModel> tours) {
    return tours
        .map(
          (tourModel) => {
            'key': tourModel.tour.id,
            'value': _extractTourName(tourModel.tour.name),
            'status': tourModel.roundStatus.name,
          },
        )
        .toList();
  }

  String _extractTourName(String fullName) {
    final parts = fullName.split('|');
    return parts.isNotEmpty ? parts.last.trim() : fullName;
  }

  void _handleBackPress(BuildContext context) {
    try {
      Navigator.of(context).pop();
    } catch (e) {
      print('Error navigating back: $e');
    }
  }

  void _handleDropdownChange(WidgetRef ref, String value) {
    try {
      ref.read(tourDetailScreenProvider.notifier).updateSelection(value);
    } catch (e) {
      print('Error updating tour selection: $e');
    }
  }

  Widget _buildErrorAppBar(BuildContext context, String errorMessage) {
    return Row(
      children: [
        SizedBox(width: 16.w),
        IconButton(
          iconSize: 24.ic,
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(Icons.arrow_back_ios_new_outlined, size: 24.ic),
        ),
        const Spacer(),
        Text(
          errorMessage,
          style: AppTypography.textMdRegular.copyWith(color: kWhiteColor),
        ),
        const Spacer(),
        SizedBox(width: 44.w),
      ],
    );
  }
}

class _LoadingAppBarWithTitle extends StatelessWidget {
  const _LoadingAppBarWithTitle({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 20.ic),
        IconButton(
          iconSize: 24.ic,
          padding: EdgeInsets.zero,
          onPressed: () {
            try {
              Navigator.of(context).pop();
            } catch (e) {
              print('Error navigating back from loading state: $e');
            }
          },
          icon: Icon(Icons.arrow_back_ios_new_outlined, size: 24.ic),
        ),
        SizedBox(width: 44.w),
        SkeletonWidget(
          child: Text(
            title,
            style: AppTypography.textMdRegular.copyWith(color: kWhiteColor),
          ),
        ),
        SizedBox(width: 44.w),
      ],
    );
  }
}

const _mappedName = {
  TournamentDetailScreenMode.about: 'About',
  TournamentDetailScreenMode.games: 'Games',
  TournamentDetailScreenMode.standings: 'Players',
};
