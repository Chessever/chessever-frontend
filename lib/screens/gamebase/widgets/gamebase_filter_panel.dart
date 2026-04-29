import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../revenue_cat_service/subscribe_state.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_typography.dart';
import '../../../utils/responsive_helper.dart';
import '../../../widgets/game_filter/wheel_range_filter.dart';
import '../../../widgets/paywall/premium_paywall_sheet.dart';
import '../models/models.dart';
import '../providers/gamebase_explorer_state.dart';
import '../providers/gamebase_providers.dart';

/// Filter panel for Gamebase explorer with time controls, rating range, and player search.
class GamebaseFilterPanel extends HookConsumerWidget {
  const GamebaseFilterPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gamebaseExplorerProvider);
    final isExpanded = useState(false);

    return Container(
      decoration: BoxDecoration(
        color: kBlack2Color,
        border: Border(
          bottom: BorderSide(color: kWhiteColor.withOpacity(0.05)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with toggle
          _FilterHeader(
            isExpanded: isExpanded.value,
            hasActiveFilters: state.hasActiveFilters,
            onToggle: () => isExpanded.value = !isExpanded.value,
            onClear:
                () =>
                    ref.read(gamebaseExplorerProvider.notifier).clearFilters(),
          ),

          // Expandable filter content
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState:
                isExpanded.value
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: _FilterContent(filters: state.filters),
          ),
        ],
      ),
    );
  }
}

/// Header row with filter icon, label, and clear button.
class _FilterHeader extends StatelessWidget {
  const _FilterHeader({
    required this.isExpanded,
    required this.hasActiveFilters,
    required this.onToggle,
    required this.onClear,
  });

  final bool isExpanded;
  final bool hasActiveFilters;
  final VoidCallback onToggle;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        child: Row(
          children: [
            Icon(
              Icons.filter_list_rounded,
              size: 20.sp,
              color: hasActiveFilters ? kWhiteColor : kSecondaryTextColor,
            ),
            SizedBox(width: 8.w),
            Text(
              'Filters',
              style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
            ),
            if (hasActiveFilters) ...[
              SizedBox(width: 8.w),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                decoration: BoxDecoration(
                  color: kWhiteColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10.br),
                ),
                child: Text(
                  'Active',
                  style: AppTypography.textXsMedium.copyWith(
                    color: kWhiteColor,
                  ),
                ),
              ),
            ],
            const Spacer(),
            if (hasActiveFilters)
              GestureDetector(
                onTap: onClear,
                child: Padding(
                  padding: EdgeInsets.all(4.sp),
                  child: Text(
                    'Clear all',
                    style: AppTypography.textXsMedium.copyWith(
                      color: kRedColor,
                    ),
                  ),
                ),
              ),
            SizedBox(width: 8.w),
            AnimatedRotation(
              turns: isExpanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20.sp,
                color: kSecondaryTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Expandable filter content with all filter options.
class _FilterContent extends HookConsumerWidget {
  const _FilterContent({required this.filters});

  final GamebaseFilters filters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time Control Section
          _SectionLabel(label: 'Time Control'),
          SizedBox(height: 8.h),
          _TimeControlChips(selectedTimeControls: filters.timeControls),

          SizedBox(height: 16.h),

          // Result Section
          _SectionLabel(label: 'Result'),
          SizedBox(height: 8.h),
          _GameResultChips(selectedResult: filters.gameResult),

          SizedBox(height: 16.h),

          // Format Section (OTB / Online) — temporarily hidden
          // _SectionLabel(label: 'Format'),
          // SizedBox(height: 8.h),
          // _FormatChips(selectedIsOnline: filters.isOnline),
          // SizedBox(height: 16.h),

          // Color Section (only when a player is selected)
          if (filters.playerIds.isNotEmpty) ...[
            _SectionLabel(label: 'Color'),
            SizedBox(height: 8.h),
            _PlayerColorChips(selectedColor: filters.playerColor),
            SizedBox(height: 16.h),
          ],

          // Rating Range Section
          _SectionLabel(label: 'Rating Range'),
          SizedBox(height: 8.h),
          _RatingRangeInputs(
            minRating: filters.minRating,
            maxRating: filters.maxRating,
          ),

          SizedBox(height: 16.h),

          // Player Search Section
          _SectionLabel(label: 'Player'),
          SizedBox(height: 8.h),
          const _PlayerSearchField(),
        ],
      ),
    );
  }
}

/// Section label for filter groups.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTypography.textXsMedium.copyWith(
        color: kSecondaryTextColor,
        letterSpacing: 0.5,
      ),
    );
  }
}

/// Time control filter chips (Classical, Rapid, Blitz).
class _TimeControlChips extends ConsumerWidget {
  const _TimeControlChips({required this.selectedTimeControls});

  final List<TimeControl> selectedTimeControls;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children:
          TimeControl.values.map((tc) {
            final isSelected = selectedTimeControls.contains(tc);
            return _FilterChip(
              label: _getTimeControlLabel(tc),
              icon: _getTimeControlIcon(tc),
              isSelected: isSelected,
              onTap: () {
                ref
                    .read(gamebaseExplorerProvider.notifier)
                    .toggleTimeControl(tc);
              },
            );
          }).toList(),
    );
  }

  String _getTimeControlLabel(TimeControl tc) {
    switch (tc) {
      case TimeControl.classical:
        return 'Classical';
      case TimeControl.rapid:
        return 'Rapid';
      case TimeControl.blitz:
        return 'Blitz';
    }
  }

  IconData _getTimeControlIcon(TimeControl tc) {
    switch (tc) {
      case TimeControl.classical:
        return Icons.hourglass_top_rounded;
      case TimeControl.rapid:
        return Icons.timer_outlined;
      case TimeControl.blitz:
        return Icons.bolt_rounded;
    }
  }
}

/// Game result filter chips (1-0, 0-1, ½-½).
class _GameResultChips extends ConsumerWidget {
  const _GameResultChips({required this.selectedResult});

  final GamebaseGameResult? selectedResult;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children:
          GamebaseGameResult.values.map((r) {
            final isSelected = selectedResult == r;
            return _FilterChip(
              label: r.displayText,
              icon: _getResultIcon(r),
              isSelected: isSelected,
              onTap: () {
                ref.read(gamebaseExplorerProvider.notifier).toggleGameResult(r);
              },
            );
          }).toList(),
    );
  }

  IconData _getResultIcon(GamebaseGameResult r) {
    switch (r) {
      case GamebaseGameResult.whiteWins:
        return Icons.looks_one_rounded;
      case GamebaseGameResult.blackWins:
        return Icons.looks_one_rounded;
      case GamebaseGameResult.draw:
        return Icons.handshake_rounded;
    }
  }
}

// Format filter chips (OTB, Online) — temporarily hidden.
// class _FormatChips extends ConsumerWidget {
//   const _FormatChips({required this.selectedIsOnline});
//
//   final bool? selectedIsOnline;
//
//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     return Wrap(
//       spacing: 8.w,
//       runSpacing: 8.h,
//       children: [
//         _FilterChip(
//           label: 'OTB',
//           icon: Icons.location_on_outlined,
//           isSelected: selectedIsOnline == false,
//           onTap: () {
//             ref.read(gamebaseExplorerProvider.notifier).toggleFormat(false);
//           },
//         ),
//         _FilterChip(
//           label: 'Online',
//           icon: Icons.language_rounded,
//           isSelected: selectedIsOnline == true,
//           onTap: () {
//             ref.read(gamebaseExplorerProvider.notifier).toggleFormat(true);
//           },
//         ),
//       ],
//     );
//   }
// }

/// Player color filter chips (White, Black).
class _PlayerColorChips extends ConsumerWidget {
  const _PlayerColorChips({required this.selectedColor});

  final GamebasePlayerColor? selectedColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children: [
        _FilterChip(
          label: 'White',
          icon: Icons.circle,
          isSelected: selectedColor == GamebasePlayerColor.white,
          iconColor: kWhiteColor,
          onTap: () {
            ref
                .read(gamebaseExplorerProvider.notifier)
                .togglePlayerColor(GamebasePlayerColor.white);
          },
        ),
        _FilterChip(
          label: 'Black',
          icon: Icons.circle_outlined,
          isSelected: selectedColor == GamebasePlayerColor.black,
          iconColor: kSecondaryTextColor,
          onTap: () {
            ref
                .read(gamebaseExplorerProvider.notifier)
                .togglePlayerColor(GamebasePlayerColor.black);
          },
        ),
      ],
    );
  }
}

/// Reusable filter chip widget.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.iconColor,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: isSelected ? kWhiteColor.withOpacity(0.12) : kBlack3Color,
          borderRadius: BorderRadius.circular(8.br),
          border: Border.all(
            color:
                isSelected ? kWhiteColor.withOpacity(0.25) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16.sp,
              color:
                  iconColor ?? (isSelected ? kWhiteColor : kSecondaryTextColor),
            ),
            SizedBox(width: 6.w),
            Text(
              label,
              style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rating range slider.
class _RatingRangeInputs extends HookConsumerWidget {
  const _RatingRangeInputs({required this.minRating, required this.maxRating});

  static const double _absMin = 0;
  static const double _absMax = 3500;
  static const int _step = 50;

  final int? minRating;
  final int? maxRating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = useState(
      RangeValues(
        (minRating?.toDouble() ?? _absMin).clamp(_absMin, _absMax),
        (maxRating?.toDouble() ?? _absMax).clamp(_absMin, _absMax),
      ),
    );

    // Sync when external state changes (e.g. "Clear all")
    useEffect(() {
      final newStart = (minRating?.toDouble() ?? _absMin).clamp(
        _absMin,
        _absMax,
      );
      final newEnd = (maxRating?.toDouble() ?? _absMax).clamp(_absMin, _absMax);
      if (range.value.start != newStart || range.value.end != newEnd) {
        range.value = RangeValues(newStart, newEnd);
      }
      return null;
    }, [minRating, maxRating]);

    final isDefault =
        range.value.start == _absMin && range.value.end == _absMax;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!isDefault)
          GestureDetector(
            onTap: () {
              range.value = const RangeValues(_absMin, _absMax);
              ref
                  .read(gamebaseExplorerProvider.notifier)
                  .setRatingRange(null, null);
            },
            child: Padding(
              padding: EdgeInsets.only(bottom: 8.h),
              child: Text(
                'Reset',
                style: AppTypography.textXsMedium.copyWith(
                  color: kSecondaryTextColor,
                ),
              ),
            ),
          ),
        WheelRangeFilter(
          minValue: _absMin,
          maxValue: _absMax,
          currentStart: range.value.start,
          currentEnd: range.value.end,
          divisions: ((_absMax - _absMin) / _step).round(),
          onChanged: (values) {
            range.value = values;
            final min = values.start == _absMin ? null : values.start.round();
            final max = values.end == _absMax ? null : values.end.round();
            ref
                .read(gamebaseExplorerProvider.notifier)
                .setRatingRange(min, max);
          },
        ),
      ],
    );
  }
}

/// Player search field with inline selected player display.
class _PlayerSearchField extends HookConsumerWidget {
  const _PlayerSearchField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gamebaseExplorerProvider);
    final selectedPlayer =
        state.filters.selectedPlayers.isNotEmpty
            ? state.filters.selectedPlayers.first
            : null;

    // If a player is selected, show inline display instead of search field
    if (selectedPlayer != null) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: kBlack3Color,
          borderRadius: BorderRadius.circular(8.br),
          border: Border.all(color: kWhiteColor.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Icon(Icons.person_rounded, size: 20.sp, color: kWhiteColor),
            SizedBox(width: 8.w),
            Expanded(
              child: Text(
                selectedPlayer.titleAndName,
                style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              onTap: () {
                ref
                    .read(gamebaseExplorerProvider.notifier)
                    .removePlayerFilter(selectedPlayer.id);
              },
              child: Padding(
                padding: EdgeInsets.all(4.sp),
                child: Icon(
                  Icons.close_rounded,
                  size: 18.sp,
                  color: kSecondaryTextColor,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final isSubscribed = ref.watch(
      subscriptionProvider.select((s) => s.isSubscribed),
    );

    if (!isSubscribed) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          await requirePremiumGuard(context, ref);
        },
        child: const AbsorbPointer(
          ignoringSemantics: true,
          child: _PlayerSearchInput(),
        ),
      );
    }

    return const _PlayerSearchInput();
  }
}

/// Search input with autocomplete dropdown (shown when no player is selected).
class _PlayerSearchInput extends HookConsumerWidget {
  const _PlayerSearchInput();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchController = useTextEditingController();
    final searchQuery = useState('');
    final isFocused = useState(false);
    final focusNode = useFocusNode();

    // Debounced search
    useEffect(() {
      if (searchQuery.value.length < 2) return null;

      Future.delayed(const Duration(milliseconds: 300), () {
        ref.invalidate(playerSearchProvider(searchQuery.value));
      });

      return null;
    }, [searchQuery.value]);

    final searchResults =
        searchQuery.value.length >= 2
            ? ref.watch(playerSearchProvider(searchQuery.value))
            : const AsyncValue<List<GamebasePlayer>>.data([]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Focus(
          onFocusChange: (hasFocus) => isFocused.value = hasFocus,
          child: TextField(
            controller: searchController,
            focusNode: focusNode,
            style: AppTypography.textSmRegular.copyWith(color: kWhiteColor),
            decoration: InputDecoration(
              hintText: 'Search player...',
              hintStyle: AppTypography.textSmRegular.copyWith(
                color: kSecondaryTextColor.withOpacity(0.5),
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 20.sp,
                color: kSecondaryTextColor,
              ),
              filled: true,
              fillColor: kBlack3Color,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12.w,
                vertical: 10.h,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.br),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.br),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.br),
                borderSide: BorderSide(
                  color: kWhiteColor.withOpacity(0.25),
                  width: 1,
                ),
              ),
            ),
            onChanged: (value) => searchQuery.value = value,
          ),
        ),

        // Search Results Dropdown
        if (isFocused.value && searchQuery.value.length >= 2)
          Container(
            margin: EdgeInsets.only(top: 4.h),
            constraints: BoxConstraints(maxHeight: 200.h),
            decoration: BoxDecoration(
              color: kBlack3Color,
              borderRadius: BorderRadius.circular(8.br),
              border: Border.all(color: kDividerColor),
            ),
            child: searchResults.when(
              data: (players) {
                if (players.isEmpty) {
                  return Padding(
                    padding: EdgeInsets.all(16.sp),
                    child: Text(
                      'No players found',
                      style: AppTypography.textSmRegular.copyWith(
                        color: kSecondaryTextColor,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.symmetric(vertical: 4.h),
                  itemCount: players.length,
                  separatorBuilder:
                      (_, __) => Divider(color: kDividerColor, height: 1),
                  itemBuilder: (context, index) {
                    final player = players[index];
                    return _PlayerSearchResult(
                      player: player,
                      onTap: () {
                        ref
                            .read(gamebaseExplorerProvider.notifier)
                            .addPlayerFilter(player);
                        searchController.clear();
                        searchQuery.value = '';
                        focusNode.unfocus();
                      },
                    );
                  },
                );
              },
              loading:
                  () => Padding(
                    padding: EdgeInsets.all(16.sp),
                    child: Center(
                      child: SizedBox(
                        width: 20.sp,
                        height: 20.sp,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: kWhiteColor,
                        ),
                      ),
                    ),
                  ),
              error:
                  (_, __) => Padding(
                    padding: EdgeInsets.all(16.sp),
                    child: Text(
                      'Search failed',
                      style: AppTypography.textSmRegular.copyWith(
                        color: kRedColor,
                      ),
                    ),
                  ),
            ),
          ),
      ],
    );
  }
}

/// Individual player search result item.
class _PlayerSearchResult extends StatelessWidget {
  const _PlayerSearchResult({required this.player, required this.onTap});

  final GamebasePlayer player;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        child: Row(
          children: [
            // Federation flag placeholder
            Container(
              width: 24.w,
              height: 16.h,
              decoration: BoxDecoration(
                color: kBlack2Color,
                borderRadius: BorderRadius.circular(2.br),
              ),
              alignment: Alignment.center,
              child: Text(
                player.fed,
                style: AppTypography.textXsBold.copyWith(
                  color: kSecondaryTextColor,
                  fontSize: 8.f,
                ),
              ),
            ),
            SizedBox(width: 10.w),
            // Player info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    player.titleAndName,
                    style: AppTypography.textSmMedium.copyWith(
                      color: kWhiteColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (player.highestRating != null)
                    Text(
                      '${player.highestRating}',
                      style: AppTypography.textXsRegular.copyWith(
                        color: kSecondaryTextColor,
                      ),
                    ),
                ],
              ),
            ),
            // Add icon
            Icon(Icons.add_rounded, size: 20.sp, color: kWhiteColor),
          ],
        ),
      ),
    );
  }
}
