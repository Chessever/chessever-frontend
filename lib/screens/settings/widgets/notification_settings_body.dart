import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/live_activity_mode_provider.dart';
import 'package:chessever2/providers/notification_permission_provider.dart';
import 'package:chessever2/providers/notification_preferences_provider.dart';
import 'package:chessever2/providers/pip_mode_provider.dart';
import 'package:chessever2/screens/settings/widgets/board_settings_body.dart'
    show TrackPersist;
import 'package:chessever2/screens/settings/widgets/settings_primitives.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
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
  const NotificationSettingsBody({
    super.key,
    required this.trackPersist,
    this.liveWidgetsKey,
  });

  final TrackPersist trackPersist;

  /// Optional anchor on the Live Game Widgets group so the host can scroll the
  /// PiP + Live Activity cards into view (used when opening straight here).
  final Key? liveWidgetsKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Master toggle reflects the live OS notification permission — not a stored
    // app preference. Permission is owned by the OS; we mirror it and route the
    // user to native controls when they tap.
    final permissionAsync = ref.watch(notificationPermissionProvider);
    final prefsAsync = ref.watch(notificationPreferencesProvider);
    final prefs = prefsAsync.valueOrNull ?? NotificationPreferences.defaults;
    final prefsLoading = prefsAsync.isLoading;
    final pushEnabled = permissionAsync.valueOrNull ?? false;
    final interactive = pushEnabled && !prefsLoading;

    // Live game widgets (PiP + Live Activity) live with notifications now —
    // they are how a live game stays visible outside the app.
    final boardSettings = ref.watch(boardSettingsProviderNew).valueOrNull;
    final boardNotifier = ref.read(boardSettingsProviderNew.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NotifPushCard(
          enabled: pushEnabled,
          onChanged: (value) {
            // Permission can't be set from code — hand off to native controls.
            // The provider re-reads the OS state afterwards (and on resume), so
            // the toggle reflects whatever the user actually chose.
            trackPersist(
              ref
                  .read(notificationPermissionProvider.notifier)
                  .handleMasterToggle(),
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

        if (boardSettings != null) ...[
          KeyedSubtree(
            key: liveWidgetsKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const NotifSectionHeader(title: 'Live Game Widgets'),
                SizedBox(height: 12.h),
                _PipSettingCard(
                  selected: boardSettings.pipMode,
                  onSelected: (mode) =>
                      trackPersist(boardNotifier.setPipMode(mode)),
                ),
                SizedBox(height: 18.h),
                _LiveActivitySettingCard(
                  selected: boardSettings.liveActivityMode,
                  onSelected: (mode) =>
                      trackPersist(boardNotifier.setLiveActivityMode(mode)),
                ),
              ],
            ),
          ),
          SizedBox(height: 24.h),
        ],

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
          title: 'Folder Updates',
          subtitle:
              'Get notified when games are added, updated, or removed in your subscribed folders.',
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

/// Picture in Picture mode card. PiP draws the board natively and refreshes in
/// real time, so the note emphasizes its live, continuous nature.
class _PipSettingCard extends StatelessWidget {
  const _PipSettingCard({required this.selected, required this.onSelected});

  final PipMode selected;
  final ValueChanged<PipMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return SettingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Picture in Picture',
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary,
              fontSize: 13.f,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            'A floating mini-board that stays on top of other apps and follows '
            'the game live. Pick which games can float.',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textSecondary,
              fontSize: 11.f,
            ),
          ),
          SizedBox(height: 14.h),
          _PipModeSelector(
            selected: selected,
            // PiP is free for everyone — no paywall.
            onSelected: onSelected,
          ),
        ],
      ),
    );
  }
}

/// Live Activity mode card. A move-only lock-screen card (board, players, last
/// move, evaluation — no clocks); iOS repaints it on each move push.
class _LiveActivitySettingCard extends StatelessWidget {
  const _LiveActivitySettingCard({
    required this.selected,
    required this.onSelected,
  });

  final LiveActivityMode selected;
  final ValueChanged<LiveActivityMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return SettingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Live Activity',
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary,
              fontSize: 13.f,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            'A lock-screen card with the board, players and evaluation, '
            'updated on every move. A quick glance, not a live stream.',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textSecondary,
              fontSize: 11.f,
            ),
          ),
          SizedBox(height: 14.h),
          _LiveActivityModeSelector(selected: selected, onSelected: onSelected),
        ],
      ),
    );
  }
}

class _PipModeSelector extends StatelessWidget {
  const _PipModeSelector({required this.selected, required this.onSelected});

  final PipMode selected;
  final ValueChanged<PipMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(4.sp),
      decoration: BoxDecoration(
        color: context.colors.surfaceRecessed,
        borderRadius: BorderRadius.circular(12.br),
      ),
      child: Row(
        children: [
          _buildOption(context, mode: PipMode.off, icon: Icons.block_rounded),
          SizedBox(width: 4.w),
          _buildOption(context, mode: PipMode.live, icon: Icons.sensors_rounded),
        ],
      ),
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required PipMode mode,
    required IconData icon,
  }) {
    final isSelected = selected == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => onSelected(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(vertical: 8.sp),
          decoration: BoxDecoration(
            color: isSelected
                ? kPrimaryColor.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8.br),
            border: Border.all(
              color: isSelected ? kPrimaryColor : Colors.transparent,
              width: isSelected ? 1.5 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: kPrimaryColor.withValues(alpha: 0.18),
                      blurRadius: 8,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected
                    ? context.colors.textPrimary
                    : context.colors.textTertiary,
                size: 20.ic,
              ),
              SizedBox(height: 4.h),
              Text(
                mode.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.textXsMedium.copyWith(
                  color: isSelected
                      ? context.colors.textPrimary
                      : context.colors.textTertiary,
                  fontSize: 10.f,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveActivityModeSelector extends StatelessWidget {
  const _LiveActivityModeSelector({
    required this.selected,
    required this.onSelected,
  });

  final LiveActivityMode selected;
  final ValueChanged<LiveActivityMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(4.sp),
      decoration: BoxDecoration(
        color: context.colors.surfaceRecessed,
        borderRadius: BorderRadius.circular(12.br),
      ),
      child: Row(
        children: [
          _buildOption(
            context,
            mode: LiveActivityMode.off,
            icon: Icons.block_rounded,
          ),
          SizedBox(width: 4.w),
          _buildOption(
            context,
            mode: LiveActivityMode.live,
            icon: Icons.sensors_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required LiveActivityMode mode,
    required IconData icon,
  }) {
    final isSelected = selected == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => onSelected(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(vertical: 8.sp),
          decoration: BoxDecoration(
            color: isSelected
                ? kPrimaryColor.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8.br),
            border: Border.all(
              color: isSelected ? kPrimaryColor : Colors.transparent,
              width: isSelected ? 1.5 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: kPrimaryColor.withValues(alpha: 0.18),
                      blurRadius: 8,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected
                    ? context.colors.textPrimary
                    : context.colors.textTertiary,
                size: 20.ic,
              ),
              SizedBox(height: 4.h),
              Text(
                mode.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.textXsMedium.copyWith(
                  color: isSelected
                      ? context.colors.textPrimary
                      : context.colors.textTertiary,
                  fontSize: 10.f,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
