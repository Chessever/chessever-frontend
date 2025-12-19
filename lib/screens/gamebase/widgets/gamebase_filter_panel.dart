import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../theme/app_theme.dart';
import '../../../utils/app_typography.dart';
import '../../../utils/responsive_helper.dart';
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
            onClear: () =>
                ref.read(gamebaseExplorerProvider.notifier).clearFilters(),
          ),

          // Expandable filter content
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: isExpanded.value
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
              style: AppTypography.textSmMedium.copyWith(
                color: kWhiteColor,
              ),
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

          // Selected Players
          if (filters.selectedPlayers.isNotEmpty) ...[
            SizedBox(height: 8.h),
            _SelectedPlayerChips(players: filters.selectedPlayers),
          ],
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
      children: TimeControl.values.map((tc) {
        final isSelected = selectedTimeControls.contains(tc);
        return _FilterChip(
          label: _getTimeControlLabel(tc),
          icon: _getTimeControlIcon(tc),
          isSelected: isSelected,
          onTap: () {
            ref.read(gamebaseExplorerProvider.notifier).toggleTimeControl(tc);
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

/// Reusable filter chip widget.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

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
            color: isSelected ? kWhiteColor.withOpacity(0.25) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16.sp,
              color: isSelected ? kWhiteColor : kSecondaryTextColor,
            ),
            SizedBox(width: 6.w),
            Text(
              label,
              style: AppTypography.textSmMedium.copyWith(
                color: kWhiteColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rating range input fields.
class _RatingRangeInputs extends HookConsumerWidget {
  const _RatingRangeInputs({
    required this.minRating,
    required this.maxRating,
  });

  final int? minRating;
  final int? maxRating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final minController = useTextEditingController(
      text: minRating?.toString() ?? '',
    );
    final maxController = useTextEditingController(
      text: maxRating?.toString() ?? '',
    );

    // Update controllers when external state changes
    useEffect(() {
      final minText = minRating?.toString() ?? '';
      final maxText = maxRating?.toString() ?? '';
      if (minController.text != minText) minController.text = minText;
      if (maxController.text != maxText) maxController.text = maxText;
      return null;
    }, [minRating, maxRating]);

    void updateRatings() {
      final min = int.tryParse(minController.text);
      final max = int.tryParse(maxController.text);
      ref.read(gamebaseExplorerProvider.notifier).setRatingRange(min, max);
    }

    return Row(
      children: [
        Expanded(
          child: _RatingTextField(
            controller: minController,
            hint: 'Min (e.g. 2000)',
            onSubmitted: (_) => updateRatings(),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          child: Text(
            '—',
            style: AppTypography.textSmRegular.copyWith(
              color: kSecondaryTextColor,
            ),
          ),
        ),
        Expanded(
          child: _RatingTextField(
            controller: maxController,
            hint: 'Max (e.g. 2800)',
            onSubmitted: (_) => updateRatings(),
          ),
        ),
      ],
    );
  }
}

/// Individual rating text field.
class _RatingTextField extends StatelessWidget {
  const _RatingTextField({
    required this.controller,
    required this.hint,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(4),
      ],
      style: AppTypography.textSmRegular.copyWith(color: kWhiteColor),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTypography.textSmRegular.copyWith(
          color: kSecondaryTextColor.withOpacity(0.5),
        ),
        filled: true,
        fillColor: kBlack3Color,
        contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
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
          borderSide: BorderSide(color: kWhiteColor.withOpacity(0.25), width: 1),
        ),
      ),
      onSubmitted: onSubmitted,
    );
  }
}

/// Player search field with autocomplete.
class _PlayerSearchField extends HookConsumerWidget {
  const _PlayerSearchField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchController = useTextEditingController();
    final searchQuery = useState('');
    final isFocused = useState(false);
    final focusNode = useFocusNode();

    // Debounced search
    useEffect(() {
      if (searchQuery.value.length < 2) return null;

      final timer = Future.delayed(const Duration(milliseconds: 300), () {
        // Trigger search by reading the provider
        ref.invalidate(playerSearchProvider(searchQuery.value));
      });

      return null;
    }, [searchQuery.value]);

    final searchResults = searchQuery.value.length >= 2
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
              hintText: 'Search',
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
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
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
                borderSide: BorderSide(color: kWhiteColor.withOpacity(0.25), width: 1),
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
                  separatorBuilder: (_, __) =>
                      Divider(color: kDividerColor, height: 1),
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
              loading: () => Padding(
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
              error: (_, __) => Padding(
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
  const _PlayerSearchResult({
    required this.player,
    required this.onTap,
  });

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
            Icon(
              Icons.add_rounded,
              size: 20.sp,
              color: kWhiteColor,
            ),
          ],
        ),
      ),
    );
  }
}

/// Selected player chips display.
class _SelectedPlayerChips extends ConsumerWidget {
  const _SelectedPlayerChips({required this.players});

  final List<GamebasePlayer> players;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children: players.map((player) {
        return Container(
          padding: EdgeInsets.only(left: 12.w, right: 4.w, top: 6.h, bottom: 6.h),
          decoration: BoxDecoration(
            color: kWhiteColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20.br),
            border: Border.all(color: kWhiteColor.withOpacity(0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                player.titleAndName,
                style: AppTypography.textSmMedium.copyWith(
                  color: kWhiteColor,
                ),
              ),
              SizedBox(width: 4.w),
              GestureDetector(
                onTap: () {
                  ref
                      .read(gamebaseExplorerProvider.notifier)
                      .removePlayerFilter(player.id);
                },
                child: Container(
                  padding: EdgeInsets.all(4.sp),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16.sp,
                    color: kWhiteColor.withOpacity(0.85),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
