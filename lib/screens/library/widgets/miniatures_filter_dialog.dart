import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/game_filter/rating_tier_filter.dart';
import 'package:chessever2/widgets/game_filter/wheel_range_filter.dart';
import 'package:flutter/material.dart';

class MiniatureOpeningFilterInput {
  const MiniatureOpeningFilterInput({
    this.eco,
    this.ecoCategories = const <String>{},
    this.opening,
  });

  final String? eco;
  final Set<String> ecoCategories;
  final String? opening;

  factory MiniatureOpeningFilterInput.parse(String value) {
    final input = value.trim();
    if (input.isEmpty) return const MiniatureOpeningFilterInput();

    final upper = input.toUpperCase();
    if (RegExp(r'^[A-E]\d{2}$').hasMatch(upper)) {
      return MiniatureOpeningFilterInput(eco: upper);
    }
    if (RegExp(r'^[A-E]$').hasMatch(upper)) {
      return MiniatureOpeningFilterInput(ecoCategories: <String>{upper});
    }
    return MiniatureOpeningFilterInput(opening: input);
  }
}

/// Shows the miniatures filter dialog behind the single tune icon
/// next to search — the same shape as the Favorites and Countrymen games tabs.
/// Returns the new filter or null if cancelled. Window / search are owned by
/// the screen's own controls and pass through unchanged.
Future<MiniatureGamesFilter?> showMiniaturesFilterDialog({
  required BuildContext context,
  required MiniatureGamesFilter currentFilter,
}) {
  return showAlertModal<MiniatureGamesFilter>(
    context: context,
    horizontalPadding: 0,
    child: MiniaturesFilterDialog(initialFilter: currentFilter),
  );
}

class MiniaturesFilterDialog extends StatefulWidget {
  const MiniaturesFilterDialog({super.key, required this.initialFilter});

  final MiniatureGamesFilter initialFilter;

  @override
  State<MiniaturesFilterDialog> createState() => _MiniaturesFilterDialogState();
}

class _MiniaturesFilterDialogState extends State<MiniaturesFilterDialog> {
  static const int _defaultMaxMoves = 25;
  static final int _maxYear = DateTime.now().year;
  static const int _minYear = GameFilter.absoluteMinYear;

  /// null = any result.
  MiniatureGameResult? _result;

  /// null = any time control.
  MiniatureGameTimeControl? _timeControl;

  /// null = default finish (by move 25, the index's outer bound).
  int? _maxMoves;

  late final TextEditingController _openingController;
  late RangeValues _yearRange;
  late int? _selectedMinRating;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final filter = widget.initialFilter;
    _result = filter.results.length == 1 ? filter.results.first : null;
    _timeControl =
        filter.timeControls.length == 1 ? filter.timeControls.first : null;
    _maxMoves =
        (filter.maxMoves == null || filter.maxMoves == _defaultMaxMoves)
            ? null
            : filter.maxMoves;
    _openingController = TextEditingController(
      text: _openingInputFromFilter(filter),
    );
    _yearRange = RangeValues(
      (_yearFromDate(filter.dateFrom) ?? _minYear).toDouble(),
      (_yearFromDate(filter.dateTo) ?? _maxYear).toDouble(),
    );
    _selectedMinRating = RatingTierFilter.normalizeMinRating(filter.minRating);
  }

  @override
  void dispose() {
    _openingController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  static String _openingInputFromFilter(MiniatureGamesFilter filter) {
    final eco = filter.eco?.trim();
    if (eco != null && eco.isNotEmpty) return eco.toUpperCase();
    if (filter.ecoCategories.length == 1) {
      return filter.ecoCategories.first.toUpperCase();
    }
    final opening = filter.opening?.trim();
    if (opening != null && opening.isNotEmpty) return opening;
    return filter.variation?.trim() ?? '';
  }

  static int? _yearFromDate(String? value) {
    final text = value?.trim();
    if (text == null || text.length < 4) return null;
    return int.tryParse(text.substring(0, 4));
  }

  @override
  Widget build(BuildContext context) {
    final dialogWidth = 320.w;
    return Container(
      width: dialogWidth,
      constraints: BoxConstraints(maxHeight: 560.h),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16.br),
        border: Border.all(
          color: context.colors.textPrimary.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: true,
              radius: Radius.circular(4.br),
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionLabel('Ended by move'),
                    SizedBox(height: 8.h),
                    _chipGrid<int?>(
                      values: const <int?>[null, 20, 15],
                      selected: _maxMoves,
                      label: (v) => '≤ ${v ?? _defaultMaxMoves}',
                      onTap: (v) {
                        HapticFeedbackService.selection();
                        setState(() => _maxMoves = v);
                      },
                    ),
                    SizedBox(height: 20.h),

                    _sectionLabel('Time Control'),
                    SizedBox(height: 8.h),
                    _chipGrid<MiniatureGameTimeControl?>(
                      values: <MiniatureGameTimeControl?>[
                        null,
                        ...MiniatureGameTimeControl.values,
                      ],
                      selected: _timeControl,
                      label: (v) => v == null ? 'All' : v.label,
                      onTap: (v) {
                        HapticFeedbackService.selection();
                        setState(() => _timeControl = v);
                      },
                    ),
                    SizedBox(height: 20.h),

                    _sectionLabel('Level'),
                    SizedBox(height: 8.h),
                    RatingTierFilter(
                      selectedMinRating: _selectedMinRating,
                      onChanged: (value) {
                        HapticFeedbackService.selection();
                        setState(() => _selectedMinRating = value);
                      },
                    ),
                    SizedBox(height: 20.h),

                    _sectionLabel('Opening'),
                    SizedBox(height: 8.h),
                    _textField(
                      controller: _openingController,
                      hint: 'Example: B90 or Sicilian Defense',
                    ),
                    SizedBox(height: 20.h),

                    _sectionLabel('Result'),
                    SizedBox(height: 8.h),
                    _chipGrid<MiniatureGameResult?>(
                      values: <MiniatureGameResult?>[
                        null,
                        ...MiniatureGameResult.values,
                      ],
                      selected: _result,
                      label: (v) => v == null ? 'All' : v.label,
                      onTap: (v) {
                        HapticFeedbackService.selection();
                        setState(() => _result = v);
                      },
                    ),
                    SizedBox(height: 20.h),

                    _sectionLabel('Year'),
                    SizedBox(height: 8.h),
                    WheelRangeFilter(
                      minValue: _minYear.toDouble(),
                      maxValue: _maxYear.toDouble(),
                      currentStart: _yearRange.start,
                      currentEnd: _yearRange.end,
                      divisions: _maxYear - _minYear,
                      onChanged: (v) => setState(() => _yearRange = v),
                    ),
                    SizedBox(height: 12.h),
                  ],
                ),
              ),
            ),
          ),
          _buildButtons(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final activeChipWidgets = <Widget>[];

    Widget buildChip(String label, VoidCallback onRemove) {
      return GestureDetector(
        onTap: () {
          HapticFeedbackService.buttonPress();
          onRemove();
        },
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
          decoration: BoxDecoration(
            color: kPrimaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4.br),
            border: Border.all(color: kPrimaryColor.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTypography.textXsMedium.copyWith(
                  color: kPrimaryColor,
                ),
              ),
              SizedBox(width: 4.w),
              Icon(Icons.close_rounded, color: kPrimaryColor, size: 14.ic),
            ],
          ),
        ),
      );
    }

    if (_result != null) {
      activeChipWidgets.add(
        buildChip('Result: ${_result!.label}', () {
          setState(() => _result = null);
        }),
      );
    }
    if (_timeControl != null) {
      activeChipWidgets.add(
        buildChip('TC: ${_timeControl!.label}', () {
          setState(() => _timeControl = null);
        }),
      );
    }
    if (_maxMoves != null) {
      activeChipWidgets.add(
        buildChip('Ended by move: ≤ $_maxMoves', () {
          setState(() => _maxMoves = null);
        }),
      );
    }
    if (_openingController.text.trim().isNotEmpty) {
      activeChipWidgets.add(
        buildChip('Opening: ${_openingController.text.trim()}', () {
          setState(() => _openingController.clear());
        }),
      );
    }

    if (_yearRange.start.round() > _minYear ||
        _yearRange.end.round() < _maxYear) {
      activeChipWidgets.add(
        buildChip(
          'Year: ${_yearRange.start.round()}-${_yearRange.end.round()}',
          () {
            setState(
              () =>
                  _yearRange = RangeValues(
                    _minYear.toDouble(),
                    _maxYear.toDouble(),
                  ),
            );
          },
        ),
      );
    }
    final ratingLabel = RatingTierFilter.labelForMinRating(_selectedMinRating);
    if (ratingLabel != null) {
      activeChipWidgets.add(
        buildChip('Level: $ratingLabel', () {
          setState(() => _selectedMinRating = null);
        }),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 18.h, 12.w, 6.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Filters',
                style: AppTypography.textMdBold.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(
                  Icons.close_rounded,
                  color: context.colors.textPrimary.withValues(alpha: 0.6),
                  size: 20.ic,
                ),
              ),
            ],
          ),
          if (activeChipWidgets.isNotEmpty) ...[
            SizedBox(height: 8.h),
            Wrap(spacing: 6.w, runSpacing: 6.h, children: activeChipWidgets),
            SizedBox(height: 4.h),
          ],
        ],
      ),
    );
  }

  Widget _buildButtons() {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 16.h),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _resetFilters,
              child: Container(
                height: 40.h,
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(4.br),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Reset',
                  style: AppTypography.textSmBold.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: GestureDetector(
              onTap: _applyFilters,
              child: Container(
                height: 40.h,
                decoration: BoxDecoration(
                  color: context.colors.textPrimary,
                  borderRadius: BorderRadius.circular(4.br),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Apply Filters',
                  style: AppTypography.textSmBold.copyWith(
                    color: context.colors.textInverse,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _resetFilters() {
    HapticFeedbackService.buttonPress();
    // Preserve everything owned by the screen's own controls. Hidden legacy
    // sort/opening variants reset to the phone defaults.
    final initial = widget.initialFilter;
    Navigator.of(context).pop(
      MiniatureGamesFilter(
        window: initial.window,
        search: initial.search,
        playerId: initial.playerId,
      ),
    );
  }

  void _applyFilters() {
    FocusScope.of(context).unfocus();
    HapticFeedbackService.buttonPress();
    final initial = widget.initialFilter;
    final openingInput = MiniatureOpeningFilterInput.parse(
      _openingController.text,
    );

    final yearFrom = _yearRange.start.round();
    final yearTo = _yearRange.end.round();

    Navigator.of(context).pop(
      MiniatureGamesFilter(
        window: initial.window,
        sort: MiniatureGamesSort.recent,
        order: MiniatureGamesSortOrder.desc,
        search: initial.search,
        playerId: initial.playerId,
        results: _result == null ? const {} : {_result!},
        timeControls: _timeControl == null ? const {} : {_timeControl!},
        maxMoves: _maxMoves,
        eco: openingInput.eco,
        ecoCategories: openingInput.ecoCategories,
        opening: openingInput.opening,
        variation: null,
        minRating: _selectedMinRating,
        dateFrom: yearFrom > _minYear ? '$yearFrom-01-01' : null,
        dateTo: yearTo < _maxYear ? '$yearTo-12-31' : null,
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: AppTypography.textSmMedium.copyWith(
        color: context.colors.textPrimary,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _chipGrid<T>({
    required List<T> values,
    required T selected,
    required String Function(T) label,
    required ValueChanged<T> onTap,
  }) {
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children:
          values.map((v) {
            final isSelected = v == selected;
            return GestureDetector(
              onTap: () => onTap(v),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                decoration: BoxDecoration(
                  color:
                      isSelected
                          ? kPrimaryColor
                          : context.colors.surfaceRecessed,
                  borderRadius: BorderRadius.circular(8.br),
                ),
                child: Text(
                  label(v),
                  style: AppTypography.textXsMedium.copyWith(
                    color:
                        isSelected ? kBlackColor : context.colors.textPrimary,
                  ),
                ),
              ),
            );
          }).toList(),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      onChanged: (_) => setState(() {}),
      style: AppTypography.textSmMedium.copyWith(
        color: context.colors.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: AppTypography.textSmRegular.copyWith(
          color: context.colors.textPrimary.withValues(alpha: 0.4),
        ),
        filled: true,
        fillColor: context.colors.surfaceRecessed,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.br),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
