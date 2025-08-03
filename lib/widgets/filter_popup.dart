import 'package:chessever2/screens/tournaments/providers/filter_provider.dart';
import 'package:chessever2/screens/tournaments/providers/tournament_screen_provider.dart';
import 'package:chessever2/screens/tournaments/tournament_screen.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/divider_widget.dart';
import 'package:flutter/material.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/widgets/back_drop_filter_widget.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class FilterPopup extends ConsumerStatefulWidget {
  const FilterPopup({super.key});

  @override
  ConsumerState<FilterPopup> createState() => _FilterPopupState();
}

class _FilterPopupState extends ConsumerState<FilterPopup> {
  bool _isFormatExpanded = false;
  String _selectedFormat = 'All Formats';

  // ELO slider state
  RangeValues _eloRange = const RangeValues(800, 3200);

  // Date range state
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  Widget build(BuildContext context) {
    final selectedTourEvent = ref.watch(selectedTourEventProvider);
    final dialogWidth = 280.w;
    final horizontalPadding = 20.w;
    final verticalPadding = 16.h;
    final formatsAsync = ref.watch(tourFormatsProvider(selectedTourEvent));

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Stack(
        children: [
          const Positioned.fill(child: BackDropFilterWidget()),
          Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.zero,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                width: dialogWidth,
                constraints: BoxConstraints(maxHeight: 500.h),
                // Increased height
                decoration: BoxDecoration(
                  color: kBlackColor,
                  borderRadius: BorderRadius.circular(4.br),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(
                          left: horizontalPadding,
                          right: horizontalPadding,
                          top: verticalPadding,
                          bottom: 0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Format Section
                            Text(
                              'Format',
                              style: AppTypography.textXsMedium.copyWith(
                                color: kWhiteColor,
                              ),
                            ),
                            SizedBox(height: 8.h),
                            GestureDetector(
                              onTap:
                                  () => setState(
                                    () =>
                                        _isFormatExpanded = !_isFormatExpanded,
                                  ),
                              child: Container(
                                height: 40.h,
                                decoration: BoxDecoration(
                                  color:
                                      _isFormatExpanded
                                          ? kPrimaryColor
                                          : kBlack2Color,
                                  borderRadius: BorderRadius.circular(8.br),
                                ),
                                padding: EdgeInsets.symmetric(
                                  horizontal: 16.sp,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _selectedFormat,
                                      style: AppTypography.textXsMedium
                                          .copyWith(
                                            color:
                                                _isFormatExpanded
                                                    ? kBlackColor
                                                    : kWhiteColor,
                                          ),
                                    ),
                                    Icon(
                                      _isFormatExpanded
                                          ? Icons.keyboard_arrow_up
                                          : Icons.keyboard_arrow_down,
                                      color:
                                          _isFormatExpanded
                                              ? kBlackColor
                                              : kWhiteColor,
                                      size: 24.ic,
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // Format expansion
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              height: _isFormatExpanded ? null : 0,
                              child:
                                  _isFormatExpanded
                                      ? Container(
                                        margin: EdgeInsets.only(top: 4.sp),
                                        decoration: BoxDecoration(
                                          color: kBlack2Color,
                                          borderRadius: BorderRadius.circular(
                                            8.br,
                                          ),
                                        ),
                                        child: formatsAsync.when(
                                          data:
                                              (formats) => Column(
                                                children:
                                                    formats.map((format) {
                                                      final isSelected =
                                                          _selectedFormat ==
                                                          format;
                                                      return Column(
                                                        children: [
                                                          GestureDetector(
                                                            onTap:
                                                                () => setState(() {
                                                                  _selectedFormat =
                                                                      format;
                                                                  _isFormatExpanded =
                                                                      false;
                                                                }),
                                                            child: Container(
                                                              height: 40.h,
                                                              alignment:
                                                                  Alignment
                                                                      .centerLeft,
                                                              padding:
                                                                  EdgeInsets.symmetric(
                                                                    horizontal:
                                                                        16.sp,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color:
                                                                    isSelected
                                                                        ? kDividerColor
                                                                        : Colors
                                                                            .transparent,
                                                              ),
                                                              child: Text(
                                                                format,
                                                                style: AppTypography
                                                                    .textXsMedium
                                                                    .copyWith(
                                                                      color:
                                                                          kWhiteColor,
                                                                    ),
                                                              ),
                                                            ),
                                                          ),
                                                          if (format !=
                                                              formats.last)
                                                            DividerWidget(),
                                                        ],
                                                      );
                                                    }).toList(),
                                              ),
                                          loading:
                                              () => const Padding(
                                                padding: EdgeInsets.all(8.0),
                                                child: Center(
                                                  child:
                                                      CircularProgressIndicator(),
                                                ),
                                              ),
                                          error:
                                              (e, st) => Padding(
                                                padding: const EdgeInsets.all(
                                                  8.0,
                                                ),
                                                child: Text(
                                                  'Failed to load formats',
                                                  style: TextStyle(
                                                    color: Colors.red,
                                                  ),
                                                ),
                                              ),
                                        ),
                                      )
                                      : const SizedBox.shrink(),
                            ),

                            // ELO Range Slider
                            SizedBox(height: 24.h),
                            Text(
                              'ELO Range',
                              style: AppTypography.textXsMedium.copyWith(
                                color: kWhiteColor,
                              ),
                            ),
                            SizedBox(height: 8.h),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 16.sp,
                                vertical: 12.sp,
                              ),
                              decoration: BoxDecoration(
                                color: kBlack2Color,
                                borderRadius: BorderRadius.circular(8.br),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${_eloRange.start.round()}',
                                        style: AppTypography.textXsMedium
                                            .copyWith(color: kWhiteColor),
                                      ),
                                      Text(
                                        '${_eloRange.end.round()}',
                                        style: AppTypography.textXsMedium
                                            .copyWith(color: kWhiteColor),
                                      ),
                                    ],
                                  ),
                                  RangeSlider(
                                    values: _eloRange,
                                    min: 800,
                                    max: 3200,
                                    divisions: 48,
                                    labels: RangeLabels(
                                      '${_eloRange.start.round()}',
                                      '${_eloRange.end.round()}',
                                    ),
                                    activeColor: kPrimaryColor,
                                    inactiveColor: kDividerColor,
                                    onChanged: (values) {
                                      setState(() => _eloRange = values);
                                      print(
                                        'ELO Range changed: ${values.start.round()}-${values.end.round()}',
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: 16.h),
                          ],
                        ),
                      ),

                      // Buttons
                      Padding(
                        padding: EdgeInsets.all(20.sp),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            SizedBox(
                              width: 116.w,
                              height: 40.h,
                              child: OutlinedButton(
                                onPressed: () async {
                                  setState(() {
                                    _selectedFormat = 'All Formats';
                                    _isFormatExpanded = false;
                                    _eloRange = const RangeValues(1000, 3000);
                                    _startDate = null;
                                    _endDate = null;
                                  });
                                  await ref
                                      .read(tournamentNotifierProvider.notifier)
                                      .resetFilters();
                                  Navigator.of(context).pop();
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: kWhiteColor,
                                  backgroundColor: kBlack2Color,
                                  side: BorderSide.none,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4.br),
                                  ),
                                  padding: EdgeInsets.zero,
                                ),
                                child: Text(
                                  'Reset',
                                  style: AppTypography.textSmMedium.copyWith(
                                    color: kWhiteColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.visible,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 116.w,
                              height: 40.h,
                              child: ElevatedButton(
                                onPressed: () async {
                                  final filteredTours = await ref
                                      .read(
                                        tourFormatRepositoryProvider(
                                          selectedTourEvent,
                                        ),
                                      )
                                      .applyAllFilters(
                                        format: _selectedFormat,
                                        eloRange: _eloRange,
                                        startDate: _startDate,
                                        endDate: _endDate,
                                      );

                                  await ref
                                      .read(tournamentNotifierProvider.notifier)
                                      .setFilteredModels(filteredTours);

                                  Navigator.of(context).pop(filteredTours);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kPrimaryColor,
                                  foregroundColor: kBlackColor,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4.br),
                                  ),
                                  padding: EdgeInsets.zero,
                                ),
                                child: Text(
                                  'Apply Filters',
                                  style: AppTypography.textSmMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.visible,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
