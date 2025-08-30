import 'package:chessever2/screens/group_event/providers/filter_provider.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/widgets/back_drop_filter_widget.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../screens/group_event/group_event_screen.dart';

class FilterPopup extends ConsumerStatefulWidget {
  const FilterPopup({super.key});

  @override
  ConsumerState<FilterPopup> createState() => _FilterPopupState();
}

class _FilterPopupState extends ConsumerState<FilterPopup> {
  final Set<String> _selectedFormats = {};

  // ELO slider state
  RangeValues _eloRange = const RangeValues(800, 3200);

  // Date range state
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  Widget build(BuildContext context) {
    final selectedTourEvent = ref.watch(selectedGroupCategoryProvider);
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
                            Text(
                              'Format',
                              style: AppTypography.textXsMedium.copyWith(
                                color: kWhiteColor,
                              ),
                            ),
                            SizedBox(height: 8.h),
                            formatsAsync.when(
                              data: (List<String> formats) {
                                return GridView.builder(
                                  shrinkWrap: true,
                                  padding: EdgeInsets.zero,
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 2,
                                        mainAxisSpacing: 8.h,
                                        crossAxisSpacing: 8.w,
                                        childAspectRatio: 3,
                                      ),
                                  itemCount: formats.length,
                                  itemBuilder: (context, index) {
                                    final format = formats[index];
                                    final isSelected = _selectedFormats
                                        .contains(format);
                                    return GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          if (isSelected) {
                                            _selectedFormats.remove(format);
                                          } else {
                                            _selectedFormats.add(format);
                                          }
                                        });
                                      },
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 150,
                                        ),
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color:
                                              isSelected
                                                  ? kPrimaryColor
                                                  : kBlack2Color,
                                          borderRadius: BorderRadius.circular(
                                            8.br,
                                          ),
                                        ),
                                        child: Text(
                                          format,
                                          style: AppTypography.textXsMedium
                                              .copyWith(
                                                color:
                                                    isSelected
                                                        ? kBlackColor
                                                        : kWhiteColor,
                                              ),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                              loading:
                                  () => const Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  ),
                              error:
                                  (e, st) => Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Text(
                                      'Failed to load formats',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
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
                                    // _selectedFormats.clear();
                                    _eloRange = const RangeValues(800, 3200);
                                    _startDate = null;
                                    _endDate = null;
                                  });
                                  await ref
                                      .read(groupEventScreenProvider.notifier)
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
                                        format:
                                            _selectedFormats.isEmpty
                                                ? null
                                                : _selectedFormats.toList(),
                                        eloRange: _eloRange,
                                        startDate: _startDate,
                                        endDate: _endDate,
                                      );

                                  await ref
                                      .read(groupEventScreenProvider.notifier)
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
