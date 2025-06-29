import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/blur_background.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/theme/app_theme.dart';
import '../providers/timezone_provider.dart';

// Enhanced model with unique identifier
class TimezoneOption {
  final String name;
  final String utcOffset;
  final TimeZone timezone;

  // Add a unique identifier for each timezone option
  final String id;

  const TimezoneOption({
    required this.name,
    required this.utcOffset,
    required this.timezone,
    required this.id,
  });

  String get display => '$name $utcOffset';
}

// State provider to track which timezone option is selected by ID
final selectedTimezoneIdProvider = StateProvider<String>((ref) => 'cet');

class TimezoneSettingsDialog extends ConsumerWidget {
  const TimezoneSettingsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTimezone = ref.watch(timezoneProvider);
    // Load the selected ID from state
    final selectedId = ref.watch(selectedTimezoneIdProvider);

    // Create descriptive timezone list with unique IDs
    final List<TimezoneOption> timezoneOptions = [
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
        name: 'Greenwich Mean Time',
        utcOffset: 'UTC+0',
        timezone: TimeZone.utc,
        id: 'gmt',
      ),
      TimezoneOption(
        name: 'West African Time',
        utcOffset: 'UTC+1',
        timezone: TimeZone.utcPlus1,
        id: 'wat',
      ),
      TimezoneOption(
        name: 'Australian Standard Time',
        utcOffset: 'UTC+8',
        timezone: TimeZone.utcPlus8,
        id: 'ast',
      ),
    ];

    return GestureDetector(
      // Close the dialog when tapping outside
      onTap: () => Navigator.of(context).pop(),
      child: Stack(
        children: [
          // Backdrop filter for blur effect
          Positioned.fill(child: BlurBackground()),
          // Dialog content
          Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: EdgeInsets.symmetric(
              horizontal: 24.sp,
              vertical: 24.sp,
            ),
            // Prevent dialog from closing when clicking on the dialog itself
            child: GestureDetector(
              onTap: () {}, // Absorb the tap
              child: Container(
                decoration: BoxDecoration(
                  color: kPopUpColor,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12.br),
                    topRight: Radius.circular(12.br),
                    bottomLeft: Radius.circular(20.br),
                    bottomRight: Radius.circular(20.br),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: kDarkGreyColor,
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: timezoneOptions.length,
                  separatorBuilder: (context, index) => Divider(),
                  itemBuilder: (context, index) {
                    final timezoneOption = timezoneOptions[index];

                    // Compare by unique ID instead of timezone offset
                    final isSelected = selectedId == timezoneOption.id;

                    return SizedBox(
                      height: 36.h,
                      child: InkWell(
                        onTap: () {
                          // Set both the timezone value and the selected ID
                          ref
                              .read(timezoneProvider.notifier)
                              .setTimezone(timezoneOption.timezone);
                          ref.read(selectedTimezoneIdProvider.notifier).state =
                              timezoneOption.id;
                          Navigator.of(context).pop();
                        },
                        child: Padding(
                          padding: EdgeInsets.all(8.sp),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              timezoneOption.display,
                              style: AppTypography.textSmMedium.copyWith(
                                color: isSelected ? kPrimaryColor : kWhiteColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
