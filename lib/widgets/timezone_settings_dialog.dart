import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/blur_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/theme/app_theme.dart';
import '../providers/timezone_provider.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class TimezoneOption {
  final String name;
  final String utcOffset;
  final TimeZone timezone;
  final String id;

  const TimezoneOption({
    required this.name,
    required this.utcOffset,
    required this.timezone,
    required this.id,
  });

  String get display => '$name $utcOffset';
}

final selectedTimezoneIdProvider = StateProvider<String>((ref) => 'cet');

class TimezoneSettingsDialog extends ConsumerWidget {
  const TimezoneSettingsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedTimezoneIdProvider);

    final timezoneOptions = [
      TimezoneOption(
        name: 'Central European Time',
        utcOffset: 'UTC+1',
        timezone: TimeZone.utcPlus1,
        id: 'cet',
      ),
      TimezoneOption(
        name: 'Eastern Standard Time',
        utcOffset: 'UTC-5',
        timezone: TimeZone.utcMinus5,
        id: 'est',
      ),
      TimezoneOption(
        name: 'Pacific Standard Time',
        utcOffset: 'UTC-8',
        timezone: TimeZone.utcMinus8,
        id: 'pst',
      ),
      TimezoneOption(
        name: 'Greenwich Mean Time',
        utcOffset: 'UTC+0',
        timezone: TimeZone.utc,
        id: 'gmt',
      ),
      TimezoneOption(
        name: 'India Standard Time',
        utcOffset: 'UTC+5:30',
        timezone: TimeZone.utcPlus3,
        id: 'ist',
      ),
    ];

    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Stack(
        children: [
          Positioned.fill(child: BlurBackground()),
          Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.symmetric(
              horizontal: 24.sp,
              vertical: 24.sp,
            ),
            child: GestureDetector(
              onTap: () {},
              child: Container(
                decoration: BoxDecoration(
                  color: kPopUpColor,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(12.br),
                    bottom: Radius.circular(20.br),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: kDarkGreyColor,
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Padding(
                      padding: EdgeInsets.all(16.sp),
                      child: Row(
                        children: [
                          InkWell(
                            onTap: () => Navigator.pop(context),
                            child: Row(
                              children: [
                                SvgPicture.asset(
                                  SvgAsset.left_arrow,
                                  height: 10.h,
                                  width: 5.w,
                                ),
                                SizedBox(width: 8.w),
                                Text(
                                  'Back',
                                  style: AppTypography.textSmRegular.copyWith(
                                    color: kBoardColorGrey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Timezone list
                    ListView.separated(
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.symmetric(horizontal: 16.sp),
                      itemCount: timezoneOptions.length,
                      separatorBuilder:
                          (_, __) =>
                              Divider(color: Colors.grey[800], height: 1),
                      itemBuilder: (context, index) {
                        final option = timezoneOptions[index];
                        final isSelected = selectedId == option.id;

                        return InkWell(
                          onTap: () {
                            ref
                                .read(timezoneProvider.notifier)
                                .setTimezone(option.timezone);
                            ref
                                .read(selectedTimezoneIdProvider.notifier)
                                .state = option.id;
                            Navigator.pop(context);
                          },
                          child: Container(
                            height: 50.h,
                            padding: EdgeInsets.symmetric(vertical: 8.sp),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                option.display,
                                style: AppTypography.textSmMedium.copyWith(
                                  color:
                                      isSelected ? kPrimaryColor : kWhiteColor,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    SizedBox(height: 16.h),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
