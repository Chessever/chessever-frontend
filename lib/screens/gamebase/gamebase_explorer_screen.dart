import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/screens/gamebase/widgets/widgets.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';

/// Main screen for exploring the Gamebase opening database.
/// Displays a chess board, move statistics, and navigation controls.
class GamebaseExplorerScreen extends ConsumerStatefulWidget {
  const GamebaseExplorerScreen({super.key});

  @override
  ConsumerState<GamebaseExplorerScreen> createState() =>
      _GamebaseExplorerScreenState();
}

class _GamebaseExplorerScreenState
    extends ConsumerState<GamebaseExplorerScreen> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gamebaseExplorerProvider);
    final screenWidth = MediaQuery.of(context).size.width;
    final boardSize = screenWidth - 48.sp; // Account for padding

    return ScreenWrapper(
      child: Scaffold(
        backgroundColor: kBlack2Color,
        appBar: _buildAppBar(context),
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveHelper.contentMaxWidth,
            ),
            child: Column(
              children: [
                // Chess board section
                Padding(
                  padding: EdgeInsets.all(24.sp),
                  child: _GamebaseChessBoard(
                    fen: state.currentFen,
                    boardSize: boardSize,
                  ),
                ),

                // Navigation controls
                _NavigationControls(
                  canGoBack: state.canGoBack,
                  canGoForward: state.canGoForward,
                  onGoToStart:
                      () => ref.read(gamebaseExplorerProvider.notifier).goToStart(),
                  onGoBack:
                      () => ref.read(gamebaseExplorerProvider.notifier).goBack(),
                  onGoForward:
                      () => ref.read(gamebaseExplorerProvider.notifier).goForward(),
                  onGoToEnd:
                      () => ref.read(gamebaseExplorerProvider.notifier).goToEnd(),
                  onReset:
                      () => ref.read(gamebaseExplorerProvider.notifier).reset(),
                ),

                SizedBox(height: 8.sp),

                // Move statistics panel
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: kBlack3Color,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(16.br),
                      ),
                    ),
                    child: const MoveStatisticsPanel(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final state = ref.watch(gamebaseExplorerProvider);

    return AppBar(
      backgroundColor: kBlack2Color,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, size: 24.ic),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text(
        'Opening Explorer',
        style: TextStyle(
          color: kWhiteColor,
          fontSize: 18.f,
          fontWeight: FontWeight.w600,
        ),
      ),
      actions: [
        if (state.hasActiveFilters)
          IconButton(
            icon: Icon(Icons.filter_alt_off, size: 24.ic),
            onPressed:
                () =>
                    ref.read(gamebaseExplorerProvider.notifier).clearFilters(),
            tooltip: 'Clear filters',
          ),
        IconButton(
          icon: Icon(Icons.tune, size: 24.ic),
          onPressed: () => _showFilterSheet(context),
          tooltip: 'Filters',
        ),
      ],
    );
  }

  void _showFilterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: kBlack3Color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.br)),
      ),
      constraints: ResponsiveHelper.bottomSheetConstraints,
      builder: (context) => const _FilterSheet(),
    );
  }
}

/// Chess board widget for displaying the current position.
class _GamebaseChessBoard extends ConsumerWidget {
  const _GamebaseChessBoard({required this.fen, required this.boardSize});

  final String fen;
  final double boardSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardSettingsAsync = ref.watch(boardSettingsProviderNew);
    final boardSettings =
        boardSettingsAsync.valueOrNull ?? const BoardSettingsNew();

    return Container(
      height: boardSize,
      width: boardSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4.br),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4.br),
        child: AbsorbPointer(
          child: Chessboard.fixed(
            size: boardSize,
            settings: ChessboardSettings(
              enableCoordinates: true,
              // Use theme colors from settings with our custom app colors
              colorScheme: boardSettings.colorScheme,
              // Use piece set from settings
              pieceAssets: boardSettings.pieceAssets,
            ),
            orientation: Side.white,
            fen: fen,
          ),
        ),
      ),
    );
  }
}

/// Navigation controls for move history.
class _NavigationControls extends StatelessWidget {
  const _NavigationControls({
    required this.canGoBack,
    required this.canGoForward,
    required this.onGoToStart,
    required this.onGoBack,
    required this.onGoForward,
    required this.onGoToEnd,
    required this.onReset,
  });

  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onGoToStart;
  final VoidCallback onGoBack;
  final VoidCallback onGoForward;
  final VoidCallback onGoToEnd;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.sp),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _NavButton(
            icon: Icons.keyboard_double_arrow_left,
            onPressed: canGoBack ? onGoToStart : null,
            tooltip: 'Go to start',
          ),
          SizedBox(width: 8.sp),
          _NavButton(
            icon: Icons.chevron_left,
            onPressed: canGoBack ? onGoBack : null,
            tooltip: 'Previous move',
          ),
          SizedBox(width: 8.sp),
          _NavButton(icon: Icons.refresh, onPressed: onReset, tooltip: 'Reset'),
          SizedBox(width: 8.sp),
          _NavButton(
            icon: Icons.chevron_right,
            onPressed: canGoForward ? onGoForward : null,
            tooltip: 'Next move',
          ),
          SizedBox(width: 8.sp),
          _NavButton(
            icon: Icons.keyboard_double_arrow_right,
            onPressed: canGoForward ? onGoToEnd : null,
            tooltip: 'Go to end',
          ),
        ],
      ),
    );
  }
}

/// Individual navigation button.
class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8.br),
          child: Container(
            width: 44.w,
            height: 44.h,
            decoration: BoxDecoration(
              color:
                  isEnabled
                      ? kPrimaryColor.withValues(alpha: 0.1)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(8.br),
              border: Border.all(
                color:
                    isEnabled
                        ? kPrimaryColor.withValues(alpha: 0.3)
                        : kDividerColor,
              ),
            ),
            child: Icon(
              icon,
              size: 24.ic,
              color: isEnabled ? kPrimaryColor : kSecondaryTextColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// Filter sheet for time controls, ratings, and players.
class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gamebaseExplorerProvider);
    final filters = state.filters;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(16.sp),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Filters',
                  style: TextStyle(
                    color: kWhiteColor,
                    fontSize: 18.f,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (state.hasActiveFilters)
                  TextButton(
                    onPressed: () {
                      ref
                          .read(gamebaseExplorerProvider.notifier)
                          .clearFilters();
                      Navigator.pop(context);
                    },
                    child: Text(
                      'Clear all',
                      style: TextStyle(color: kPrimaryColor, fontSize: 14.f),
                    ),
                  ),
              ],
            ),
            SizedBox(height: 16.sp),

            // Time control filters
            Text(
              'Time Control',
              style: TextStyle(
                color: kSecondaryTextColor,
                fontSize: 12.f,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8.sp),
            Wrap(
              spacing: 8.sp,
              children:
                  TimeControl.values.map((tc) {
                    final isSelected = filters.timeControls.contains(tc);
                    return FilterChip(
                      label: Text(tc.displayName),
                      selected: isSelected,
                      onSelected: (_) {
                        ref
                            .read(gamebaseExplorerProvider.notifier)
                            .toggleTimeControl(tc);
                      },
                      selectedColor: kPrimaryColor.withValues(alpha: 0.2),
                      checkmarkColor: kPrimaryColor,
                      labelStyle: TextStyle(
                        color: isSelected ? kPrimaryColor : kWhiteColor,
                        fontSize: 12.f,
                      ),
                      backgroundColor: kBlack2Color,
                      side: BorderSide(
                        color: isSelected ? kPrimaryColor : kDividerColor,
                      ),
                    );
                  }).toList(),
            ),
            SizedBox(height: 16.sp),

            // Rating range
            Text(
              'Rating Range',
              style: TextStyle(
                color: kSecondaryTextColor,
                fontSize: 12.f,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8.sp),
            Row(
              children: [
                Expanded(
                  child: _RatingDropdown(
                    value: filters.minRating,
                    hint: 'Min',
                    onChanged: (value) {
                      ref
                          .read(gamebaseExplorerProvider.notifier)
                          .setRatingRange(value, filters.maxRating);
                    },
                  ),
                ),
                SizedBox(width: 16.sp),
                Text(
                  'to',
                  style: TextStyle(color: kSecondaryTextColor, fontSize: 14.f),
                ),
                SizedBox(width: 16.sp),
                Expanded(
                  child: _RatingDropdown(
                    value: filters.maxRating,
                    hint: 'Max',
                    onChanged: (value) {
                      ref
                          .read(gamebaseExplorerProvider.notifier)
                          .setRatingRange(filters.minRating, value);
                    },
                  ),
                ),
              ],
            ),
            SizedBox(height: 24.sp),

            // Apply button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryColor,
                  padding: EdgeInsets.symmetric(vertical: 12.sp),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.br),
                  ),
                ),
                child: Text(
                  'Apply',
                  style: TextStyle(
                    color: kWhiteColor,
                    fontSize: 14.f,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dropdown for rating selection.
class _RatingDropdown extends StatelessWidget {
  const _RatingDropdown({
    required this.value,
    required this.hint,
    required this.onChanged,
  });

  final int? value;
  final String hint;
  final ValueChanged<int?> onChanged;

  static const List<int?> _ratings = [
    null,
    1000,
    1200,
    1400,
    1600,
    1800,
    2000,
    2200,
    2400,
    2600,
    2800,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.sp),
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius: BorderRadius.circular(8.br),
        border: Border.all(color: kDividerColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: value,
          hint: Text(
            hint,
            style: TextStyle(color: kSecondaryTextColor, fontSize: 14.f),
          ),
          dropdownColor: kBlack2Color,
          isExpanded: true,
          icon: Icon(Icons.arrow_drop_down, color: kSecondaryTextColor),
          items:
              _ratings.map((rating) {
                return DropdownMenuItem<int?>(
                  value: rating,
                  child: Text(
                    rating?.toString() ?? 'Any',
                    style: TextStyle(color: kWhiteColor, fontSize: 14.f),
                  ),
                );
              }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
