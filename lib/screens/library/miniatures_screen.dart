import 'package:chessever2/screens/library/miniatures/miniatures_about_tab.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_games_tab.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_mode_provider.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_players_tab.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Miniatures community database: short decisive master games ending by
/// move 25, served by the gamebase `/api/miniatures` index.
///
/// Laid out like Favorites and Countrymen — a Games / Players / About tab
/// triple over a shared page view. Browse, search, filters, players, and
/// add-to-folder are free. Opening a game dated before local Today shows the
/// premium paywall; Today-dated games open freely.
class MiniaturesScreen extends ConsumerStatefulWidget {
  const MiniaturesScreen({super.key});

  @override
  ConsumerState<MiniaturesScreen> createState() => _MiniaturesScreenState();
}

class _MiniaturesScreenState extends ConsumerState<MiniaturesScreen> {
  late final PageController _pageController;
  final ScrollToTopBus _scrollToTopBus = ScrollToTopBus();

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: MiniaturesScreenMode.values.indexOf(
        ref.read(selectedMiniaturesModeProvider),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollToTopBus.dispose();
    super.dispose();
  }

  void _handleTabSelection(int index) {
    final current = ref.read(selectedMiniaturesModeProvider);
    final target = MiniaturesScreenMode.values[index];
    if (target == current) {
      // Re-tapping the active tab scrolls it back to the top.
      _scrollToTopBus.request();
      return;
    }
    HapticFeedbackService.selection();
    ref.read(selectedMiniaturesModeProvider.notifier).state = target;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _handlePageChanged(int index) {
    final target = MiniaturesScreenMode.values[index];
    if (ref.read(selectedMiniaturesModeProvider) == target) return;
    ref.read(selectedMiniaturesModeProvider.notifier).state = target;
  }

  @override
  Widget build(BuildContext context) {
    final selectedMode = ref.watch(selectedMiniaturesModeProvider);
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 20.sp,
      tablet: 32.sp,
    );

    return Scaffold(
      backgroundColor: context.colors.background,
      body: ScreenWrapper(
        child: Column(
          children: [
            SizedBox(height: MediaQuery.of(context).viewPadding.top + 8.h),
            _buildHeader(),
            SizedBox(height: 12.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: SegmentedSwitcher(
                backgroundColor: context.colors.popup,
                selectedBackgroundColor: context.colors.popup,
                options: miniaturesModeNames.values.toList(),
                currentSelection: MiniaturesScreenMode.values.indexOf(
                  selectedMode,
                ),
                onSelectionChanged: _handleTabSelection,
                notifyOnReselect: true,
              ),
            ),
            Expanded(
              child: ScrollToTopScope(
                bus: _scrollToTopBus,
                child: PageView(
                  controller: _pageController,
                  onPageChanged: _handlePageChanged,
                  // Order must track MiniaturesScreenMode.
                  children: const [
                    MiniaturesAboutTab(),
                    MiniaturesGamesTab(),
                    MiniaturesPlayersTab(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return SizedBox(
      height: 44.h,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 18.sp,
                color: context.colors.textPrimary,
              ),
            ),
          ),
          // Icon and title travel as one centred lockup. The horizontal
          // padding keeps that lockup clear of the back button on the
          // narrowest phones instead of letting the two overlap.
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 56.w),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Same bare mark the Library card uses for this collection.
                Icon(
                  Icons.bolt_rounded,
                  size: 18.sp,
                  color: context.colors.iconPrimary,
                ),
                SizedBox(width: 6.w),
                Flexible(
                  child: Text(
                    'Miniatures',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.textMdMedium.copyWith(
                      color: context.colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
