import 'package:chessever2/providers/notification_preferences_provider.dart';
import 'package:chessever2/providers/notifications_settings_provider.dart';
import 'package:chessever2/screens/settings/widgets/board_settings_body.dart'
    show TrackPersist;
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/notification_settings/notif_lead_time_control.dart';
import 'package:chessever2/widgets/notification_settings/notif_push_card.dart';
import 'package:chessever2/widgets/notification_settings/notif_section_header.dart';
import 'package:chessever2/widgets/notification_settings/notif_toggle_tile.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Notification preferences as a non-scaffolded body widget.
/// Persist futures are reported via [trackPersist] for the host to await.
class NotificationSettingsBody extends ConsumerWidget {
  const NotificationSettingsBody({super.key, required this.trackPersist});

  final TrackPersist trackPersist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pushSettings = ref.watch(notificationsSettingsProvider);
    final prefsAsync = ref.watch(notificationPreferencesProvider);
    final prefs = prefsAsync.valueOrNull ?? NotificationPreferences.defaults;
    final prefsLoading = prefsAsync.isLoading;
    final pushEnabled = pushSettings.enabled;
    final interactive = pushEnabled && !prefsLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NotifPushCard(
          enabled: pushEnabled,
          onChanged: (value) {
            trackPersist(
              ref
                  .read(notificationsSettingsProvider.notifier)
                  .setEnabled(value),
            );
          },
          interactive: interactive,

          fpEnabled: prefs.favoritePlayerAlerts,
          onFpToggle: () {
            if (!interactive) return;
            trackPersist(
              ref
                  .read(notificationPreferencesProvider.notifier)
                  .setFavoritePlayerAlerts(!prefs.favoritePlayerAlerts),
            );
          },
          fpClassical: prefs.fpClassical,
          onFpClassical: () {
            if (!interactive) return;
            trackPersist(
              ref
                  .read(notificationPreferencesProvider.notifier)
                  .setFpClassical(!prefs.fpClassical),
            );
          },
          fpRapid: prefs.fpRapid,
          onFpRapid: () {
            if (!interactive) return;
            trackPersist(
              ref
                  .read(notificationPreferencesProvider.notifier)
                  .setFpRapid(!prefs.fpRapid),
            );
          },
          fpBlitz: prefs.fpBlitz,
          onFpBlitz: () {
            if (!interactive) return;
            trackPersist(
              ref
                  .read(notificationPreferencesProvider.notifier)
                  .setFpBlitz(!prefs.fpBlitz),
            );
          },

          seEnabled: prefs.favoriteEventAlerts,
          onSeToggle: () {
            if (!interactive) return;
            trackPersist(
              ref
                  .read(notificationPreferencesProvider.notifier)
                  .setFavoriteEventAlerts(!prefs.favoriteEventAlerts),
            );
          },
          seClassical: prefs.seClassical,
          onSeClassical: () {
            if (!interactive) return;
            trackPersist(
              ref
                  .read(notificationPreferencesProvider.notifier)
                  .setSeClassical(!prefs.seClassical),
            );
          },
          seRapid: prefs.seRapid,
          onSeRapid: () {
            if (!interactive) return;
            trackPersist(
              ref
                  .read(notificationPreferencesProvider.notifier)
                  .setSeRapid(!prefs.seRapid),
            );
          },
          seBlitz: prefs.seBlitz,
          onSeBlitz: () {
            if (!interactive) return;
            trackPersist(
              ref
                  .read(notificationPreferencesProvider.notifier)
                  .setSeBlitz(!prefs.seBlitz),
            );
          },
        ),

        SizedBox(height: 24.h),

        const NotifSectionHeader(title: 'Alerts'),

        Container(
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(12.br),
            border: Border.all(
              color: context.colors.divider.withValues(alpha: 0.5),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 14.sp,
              vertical: 14.sp,
            ),
            child: NotifToggleTile(
              showCard: false,
              title: 'Heads-up Alerts',
              subtitle: 'Before rounds start',
              value: prefs.headsUpAlerts,
              onChanged: !interactive
                  ? null
                  : (value) {
                      trackPersist(
                        ref
                            .read(
                              notificationPreferencesProvider.notifier,
                            )
                            .setHeadsUpAlerts(value),
                      );
                    },
              trailing: NotifLeadTimeControl(
                value: prefs.headsUpLeadMinutes,
                onChanged: (!interactive || !prefs.headsUpAlerts)
                    ? null
                    : (minutes) {
                        trackPersist(
                          ref
                              .read(
                                notificationPreferencesProvider.notifier,
                              )
                              .setHeadsUpLeadMinutes(minutes),
                        );
                      },
              ),
            ),
          ),
        ),

        SizedBox(height: 24.h),

        const NotifSectionHeader(title: 'Library'),

        NotifToggleTile(
          title: 'Database Updates',
          subtitle:
              'Get notified when games are added, updated, or removed in your subscribed databases.',
          value: prefs.bookUpdateAlerts,
          onChanged: !interactive
              ? null
              : (value) {
                  trackPersist(
                    ref
                        .read(notificationPreferencesProvider.notifier)
                        .setBookUpdateAlerts(value),
                  );
                },
        ),

        SizedBox(height: 24.h),

        const NotifSectionHeader(title: 'Updates'),

        NotifToggleTile(
          title: 'Chess World',
          subtitle: 'Get occasional highlights from chess.',
          value: prefs.callToActionAlerts,
          onChanged: !interactive
              ? null
              : (value) {
                  trackPersist(
                    ref
                        .read(notificationPreferencesProvider.notifier)
                        .setCallToActionAlerts(value),
                  );
                },
        ),
      ],
    );
  }
}
