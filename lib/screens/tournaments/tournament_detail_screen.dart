import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/standings/standings_screen.dart';
import 'package:chessever2/screens/tournaments/about_tour_screen.dart';
import 'package:chessever2/screens/gamesTourScreen/views/games_tour_screen.dart';
import 'package:chessever2/screens/tournaments/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tournaments/providers/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tournaments/widget/games_app_bar_widget.dart';
import 'package:chessever2/screens/tournaments/widget/text_dropdown_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final selectedBroadcastModelProvider = StateProvider<GroupBroadcast?>(
  (ref) => null,
);

final selectedTourModeProvider =
    AutoDisposeStateProvider<_TournamentDetailScreenMode>(
      (ref) => _TournamentDetailScreenMode.games,
    );

/// For Tabs
enum _TournamentDetailScreenMode { about, games, standings }

const _mappedName = {
  _TournamentDetailScreenMode.about: 'About',
  _TournamentDetailScreenMode.games: 'Games',
  _TournamentDetailScreenMode.standings: 'Standings',
};

class TournamentDetailScreen extends ConsumerStatefulWidget {
  const TournamentDetailScreen({super.key});

  @override
  ConsumerState<TournamentDetailScreen> createState() =>
      _TournamentDetailViewState();
}

class _TournamentDetailViewState extends ConsumerState<TournamentDetailScreen>
    with TickerProviderStateMixin {
  late PageController pageController;
  bool _isDisposed = false;

  // Define the pages for the PageView
  final List<Widget> _pages = const [
    AboutTourScreen(),
    GamesTourScreen(),
    StandingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _initializePageController();
  }

  void _initializePageController() {
    final selectedTourMode = ref.read(selectedTourModeProvider);
    final initialPage = _TournamentDetailScreenMode.values.indexOf(
      selectedTourMode,
    );

    pageController = PageController(
      initialPage: initialPage.clamp(1, _pages.length - 1),
    );
  }

  @override
  void deactivate() {
    _cleanupProviders();
    super.deactivate();
  }

  void _cleanupProviders() {
    try {
      ref.invalidate(selectedTourModeProvider);
      ref.invalidate(selectedTourIdProvider);
    } catch (e) {
      // Ignore errors during cleanup
      print('Error during provider cleanup: $e');
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
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
            _buildAppBar(tourDetailAsync, selectedTourMode),
            _buildContent(tourDetailAsync, selectedTourMode),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(
    AsyncValue<TourDetailViewModel> tourDetailAsync,
    _TournamentDetailScreenMode selectedTourMode,
  ) {
    return tourDetailAsync.when(
      data: (data) => _buildSuccessAppBar(data, selectedTourMode),
      error: (error, stackTrace) => _buildErrorAppBar(error),
      loading: () => const LoadingAppBarWithTitle(title: "Chessever"),
    );
  }

  Widget _buildSuccessAppBar(
    TourDetailViewModel data,
    _TournamentDetailScreenMode selectedTourMode,
  ) {
    return Column(
      children: [
        selectedTourMode == _TournamentDetailScreenMode.about
            ? _TourDetailDropDownAppBar(data: data)
            : selectedTourMode == _TournamentDetailScreenMode.games
            ? const GamesAppBarWidget()
            : _TourDetailDropDownAppBar(data: data),
        SizedBox(height: 8.h),
        _buildSegmentedSwitcher(selectedTourMode),
      ],
    );
  }

  Widget _buildErrorAppBar(Object error) {
    return Column(
      children: [
        LoadingAppBarWithTitle(
          title: "Error: ${error.toString().substring(0, 20)}...",
        ),
        SizedBox(height: 8.h),
        _buildSegmentedSwitcher(_TournamentDetailScreenMode.about),
      ],
    );
  }

  Widget _buildSegmentedSwitcher(_TournamentDetailScreenMode selectedTourMode) {
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
        onSelectionChanged: (index) => _handleTabSelection(index),
      ),
    );
  }

  void _handleTabSelection(int index) {
    if (_isDisposed || index < 0 || index >= _pages.length) return;

    try {
      // Animate to the selected page first
      pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );

      // Update state after animation starts
      ref.read(selectedTourModeProvider.notifier).state =
          _TournamentDetailScreenMode.values[index];
    } catch (e) {
      print('Error handling tab selection: $e');
    }
  }

  Widget _buildContent(
    AsyncValue<TourDetailViewModel> tourDetailAsync,
    _TournamentDetailScreenMode selectedTourMode,
  ) {
    return Expanded(
      child: PageView.builder(
        controller: pageController,
        itemCount: _pages.length,
        onPageChanged: (index) => _handlePageChanged(index),
        itemBuilder: (context, index) {
          // Return pages directly without error boundary
          if (index >= 0 && index < _pages.length) {
            return _pages[index];
          }
          // Fallback for invalid index
          return Center(
            child: Text(
              'Invalid page index: $index',
              style: TextStyle(color: kWhiteColor),
            ),
          );
        },
      ),
    );
  }

  void _handlePageChanged(int index) {
    if (_isDisposed ||
        index < 0 ||
        index >= _TournamentDetailScreenMode.values.length)
      return;

    try {
      // Update the selected mode when page changes (from swiping)
      final currentModeIndex = _TournamentDetailScreenMode.values.indexOf(
        ref.read(selectedTourModeProvider),
      );

      if (currentModeIndex != index) {
        ref.read(selectedTourModeProvider.notifier).state =
            _TournamentDetailScreenMode.values[index];
      }
    } catch (e) {
      print('Error handling page change: $e');
    }
  }
}

class _TourDetailDropDownAppBar extends ConsumerWidget {
  const _TourDetailDropDownAppBar({
    required this.data,
    super.key,
  });

  final TourDetailViewModel data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Null safety check for tours
    if (data.tours.isEmpty) {
      return _buildErrorAppBar(context, 'No tournaments available');
    }

    final selectedTourId = ref.watch(selectedTourIdProvider);
    final defaultTourId = data.tours.first.tour.id;

    return Row(
      children: [
        SizedBox(width: 16.w),
        IconButton(
          iconSize: 24.ic,
          padding: EdgeInsets.zero,
          onPressed: () => _handleBackPress(context),
          icon: const Icon(Icons.arrow_back_ios_new_outlined, size: 24),
        ),
        const Spacer(),
        SizedBox(
          height: 32.h,
          width: 230.w,
          child: TextDropDownWidget(
            items: _buildDropdownItems(data.tours),
            selectedId: selectedTourId ?? defaultTourId,
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
          icon: const Icon(Icons.arrow_back_ios_new_outlined, size: 24),
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

class LoadingAppBarWithTitle extends StatelessWidget {
  const LoadingAppBarWithTitle({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 20),
        IconButton(
          iconSize: 24,
          padding: EdgeInsets.zero,
          onPressed: () {
            try {
              Navigator.of(context).pop();
            } catch (e) {
              print('Error navigating back from loading state: $e');
            }
          },
          icon: const Icon(Icons.arrow_back_ios_new_outlined, size: 24),
        ),
        const SizedBox(width: 44),
        SkeletonWidget(
          child: Text(
            title,
            style: AppTypography.textMdRegular.copyWith(color: kWhiteColor),
          ),
        ),
        const SizedBox(width: 44),
      ],
    );
  }
}
