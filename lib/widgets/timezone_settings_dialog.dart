import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../providers/timezone_provider.dart';
import 'settings_card.dart';
import 'settings_dialog.dart';
import 'settings_item.dart';

class TimezoneSettingsDialog extends ConsumerWidget {
  const TimezoneSettingsDialog({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTimezone = ref.watch(timezoneProvider);

    // Determine screen size for responsive layout
    final Size screenSize = MediaQuery.of(context).size;
    final bool isSmallScreen = screenSize.width < 360;
    final bool isLargeScreen = screenSize.width > 600;

    // Calculate appropriate list height based on screen size
    final double listHeight =
        screenSize.height *
        (isSmallScreen ? 0.35 : (isLargeScreen ? 0.5 : 0.4));

    return SettingsDialog(
      title: 'Set timezone',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SettingsCard(
            children: [
              // Search field for filtering timezones (optional enhancement)
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isSmallScreen ? 8 : 16,
                  vertical: isSmallScreen ? 8 : 12,
                ),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search timezone...',
                    hintStyle: TextStyle(
                      color: Colors.grey,
                      fontSize: isSmallScreen ? 12 : 14,
                    ),
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    filled: true,
                    fillColor: const Color(0xFF1C1C1E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      vertical: isSmallScreen ? 8 : 12,
                      horizontal: isSmallScreen ? 12 : 16,
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                  // TODO: Implement search functionality
                ),
              ),
              SizedBox(
                height: listHeight,
                child: ListView(
                  children:
                      TimeZone.values.map((timezone) {
                        final isSelected = timezone == selectedTimezone;
                        return SettingsItem(
                          title: timezone.display,
                          trailing:
                              isSelected
                                  ? const Icon(
                                    Icons.check_circle,
                                    color: Colors.cyan,
                                    size: 20,
                                  )
                                  : null,
                          onTap: () {
                            ref
                                .read(timezoneProvider.notifier)
                                .setTimezone(timezone);
                            Navigator.of(context).pop();
                          },
                          showDivider: timezone != TimeZone.values.last,
                        );
                      }).toList(),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Button to close dialog without changing timezone
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.grey),
                padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 8 : 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'Cancel',
                style: TextStyle(fontSize: isSmallScreen ? 14 : 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
