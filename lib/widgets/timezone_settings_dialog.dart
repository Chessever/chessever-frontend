import 'dart:ui';
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
  const TimezoneSettingsDialog({Key? key}) : super(key: key);

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
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(color: Colors.black.withOpacity(0.3)),
            ),
          ),
          // Dialog content
          Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 24.0,
            ),
            // Prevent dialog from closing when clicking on the dialog itself
            child: GestureDetector(
              onTap: () {}, // Absorb the tap
              child: Container(
                decoration: BoxDecoration(
                  color: kPopUpColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                    bottomLeft: Radius.circular(20),
                    bottomRight: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: timezoneOptions.length,
                  separatorBuilder:
                      (context, index) => const Divider(
                        height: 1,
                        thickness: 0.5,
                        color: Color(0xFF2C2C2E),
                      ),
                  itemBuilder: (context, index) {
                    final timezoneOption = timezoneOptions[index];

                    // Compare by unique ID instead of timezone offset
                    final isSelected = selectedId == timezoneOption.id;

                    return Container(
                      height: 36,
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
                          padding: const EdgeInsets.all(8),
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
