import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/theme/app_theme.dart';
import '../providers/timezone_provider.dart';

class TimezoneOption {
  final String name;
  final String utcOffset;
  final TimeZone timezone;
  
  const TimezoneOption({
    required this.name,
    required this.utcOffset,
    required this.timezone,
  });
  
  String get display => '$name $utcOffset';
}

class TimezoneSettingsDialog extends ConsumerWidget {
  const TimezoneSettingsDialog({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTimezone = ref.watch(timezoneProvider);

    // Create descriptive timezone list based on your image
    final List<TimezoneOption> timezoneOptions = [
      TimezoneOption(
        name: 'Central European Time',
        utcOffset: 'UTC+1',
        timezone: TimeZone.utcPlus1,
      ),
      TimezoneOption(
        name: 'Eastern Standard Time',
        utcOffset: 'UTC-5',
        timezone: TimeZone.utcMinus5,
      ),
      TimezoneOption(
        name: 'Greenwich Mean Time',
        utcOffset: 'UTC+0',
        timezone: TimeZone.utc,
      ),
      TimezoneOption(
        name: 'West African Time',
        utcOffset: 'UTC+1',
        timezone: TimeZone.utcPlus1,
      ),
      TimezoneOption(
        name: 'Australian Standard Time',
        utcOffset: 'UTC+8',
        timezone: TimeZone.utcPlus8,
      ),
    ];

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
        ),
        child: ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: timezoneOptions.length,
          separatorBuilder: (context, index) => const Divider(
            height: 1,
            thickness: 0.5,
            color: Color(0xFF2C2C2E),
          ),
          itemBuilder: (context, index) {
            final timezoneOption = timezoneOptions[index];
            final isSelected = timezoneOption.timezone.offset == selectedTimezone.offset;
            
            return ListTile(
              contentPadding: const EdgeInsets.only(left: 12),
              minLeadingWidth: 0,
              horizontalTitleGap: 4,
              title: Text(
                timezoneOption.display,
                style: AppTypography.textSmMedium.copyWith(
                  color: isSelected ? kPrimaryColor : kWhiteColor,
                ),
              ),
              onTap: () {
                ref.read(timezoneProvider.notifier).setTimezone(timezoneOption.timezone);
                Navigator.of(context).pop();
              },
            );
          },
        ),
      ),
    );
  }
}
