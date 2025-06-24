import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../providers/notifications_settings_provider.dart';
import 'settings_card.dart';
import 'settings_dialog.dart';
import 'settings_item.dart';

class NotificationsSettingsDialog extends ConsumerWidget {
  const NotificationsSettingsDialog({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsSettings = ref.watch(notificationsSettingsProvider);

    return SettingsDialog(
      title: 'Notification settings',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SettingsCard(
            children: [
              SettingsItem(
                title: 'Notifications',
                subtitle: notificationsSettings.enabled ? 'On' : 'Off',
                trailing: Switch(
                  value: notificationsSettings.enabled,
                  onChanged: (value) {
                    ref
                        .read(notificationsSettingsProvider.notifier)
                        .toggleEnabled();
                  },
                  activeColor: const Color(0xFF0FB4E5),
                  activeTrackColor: const Color(0xFF0FB4E5).withOpacity(0.3),
                ),
                showDivider: false,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Button to save settings and close dialog
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0FB4E5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Save',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
