import 'package:chessever2/providers/notification_preferences_provider.dart';
import 'package:chessever2/providers/notifications_settings_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/notification_settings/beta_badge.dart';
import 'package:chessever2/widgets/notification_settings/notif_lead_time_control.dart';
import 'package:chessever2/widgets/notification_settings/notif_push_card.dart';
import 'package:chessever2/widgets/notification_settings/notif_section_header.dart';
import 'package:chessever2/widgets/notification_settings/notif_toggle_tile.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ChessBoardNotificationSettingsPage extends ConsumerStatefulWidget {
  const ChessBoardNotificationSettingsPage({super.key});

  static Route<void> route() {
    return MaterialPageRoute<void>(
      builder: (_) => const ChessBoardNotificationSettingsPage(),
    );
  }

  @override
  ConsumerState<ChessBoardNotificationSettingsPage> createState() =>
      _ChessBoardNotificationSettingsPageState();
}

class _ChessBoardNotificationSettingsPageState
    extends ConsumerState<ChessBoardNotificationSettingsPage> {
  final Set<Future<void>> _pendingPersists = {};

  void _trackPersist(Future<void> future) {
    _pendingPersists.add(future);
    future.whenComplete(() => _pendingPersists.remove(future));
  }

  Future<bool> _onWillPop() async {
    if (_pendingPersists.isNotEmpty) {
      await Future.wait(_pendingPersists);
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final pushSettings = ref.watch(notificationsSettingsProvider);
    final prefsAsync = ref.watch(notificationPreferencesProvider);
    final prefs = prefsAsync.valueOrNull ?? NotificationPreferences.defaults;
    final prefsLoading = prefsAsync.isLoading;
    final pushEnabled = pushSettings.enabled;
    final interactive = pushEnabled && !prefsLoading;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final canPop = await _onWillPop();
        if (canPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(
          title: Text(
            'Notification Settings',
            style: AppTypography.textLgMedium.copyWith(
              color: context.colors.textPrimary,
              fontSize: 16.f,
            ),
          ),
          backgroundColor: context.colors.background,
          centerTitle: false,
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveHelper.contentMaxWidth,
            ),
            child: ListView(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.adaptive(
                  phone: 20.sp,
                  tablet: 32.sp,
                ),
                vertical: 16.sp,
              ),
              children: [
                // ── Push Notifications card (master toggle + category rows) ─
                NotifPushCard(
                  enabled: pushEnabled,
                  onChanged: (value) {
                    _trackPersist(
                      ref
                          .read(notificationsSettingsProvider.notifier)
                          .setEnabled(value),
                    );
                  },
                  interactive: interactive,

                  // ── Favourite Players ─────────────────────────────────────
                  fpEnabled: prefs.favoritePlayerAlerts,
                  onFpToggle: () {
                    if (!interactive) return;
                    _trackPersist(
                      ref
                          .read(notificationPreferencesProvider.notifier)
                          .setFavoritePlayerAlerts(!prefs.favoritePlayerAlerts),
                    );
                  },
                  fpClassical: prefs.fpClassical,
                  onFpClassical: () {
                    if (!interactive) return;
                    _trackPersist(
                      ref
                          .read(notificationPreferencesProvider.notifier)
                          .setFpClassical(!prefs.fpClassical),
                    );
                  },
                  fpRapid: prefs.fpRapid,
                  onFpRapid: () {
                    if (!interactive) return;
                    _trackPersist(
                      ref
                          .read(notificationPreferencesProvider.notifier)
                          .setFpRapid(!prefs.fpRapid),
                    );
                  },
                  fpBlitz: prefs.fpBlitz,
                  onFpBlitz: () {
                    if (!interactive) return;
                    _trackPersist(
                      ref
                          .read(notificationPreferencesProvider.notifier)
                          .setFpBlitz(!prefs.fpBlitz),
                    );
                  },

                  // ── Starred Events ────────────────────────────────────────
                  seEnabled: prefs.favoriteEventAlerts,
                  onSeToggle: () {
                    if (!interactive) return;
                    _trackPersist(
                      ref
                          .read(notificationPreferencesProvider.notifier)
                          .setFavoriteEventAlerts(!prefs.favoriteEventAlerts),
                    );
                  },
                  seClassical: prefs.seClassical,
                  onSeClassical: () {
                    if (!interactive) return;
                    _trackPersist(
                      ref
                          .read(notificationPreferencesProvider.notifier)
                          .setSeClassical(!prefs.seClassical),
                    );
                  },
                  seRapid: prefs.seRapid,
                  onSeRapid: () {
                    if (!interactive) return;
                    _trackPersist(
                      ref
                          .read(notificationPreferencesProvider.notifier)
                          .setSeRapid(!prefs.seRapid),
                    );
                  },
                  seBlitz: prefs.seBlitz,
                  onSeBlitz: () {
                    if (!interactive) return;
                    _trackPersist(
                      ref
                          .read(notificationPreferencesProvider.notifier)
                          .setSeBlitz(!prefs.seBlitz),
                    );
                  },
                ),

                SizedBox(height: 24.h),

                // ── ALERTS ────────────────────────────────────────────────
                const NotifSectionHeader(title: 'Alerts'),

                // Heads-up Alerts + Live Updates share a single card
                Container(
                  decoration: BoxDecoration(
                    color: context.colors.surface,
                    borderRadius: BorderRadius.circular(12.br),
                    border: Border.all(
                      color: context.colors.divider.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 14.sp,
                          vertical: 14.sp,
                        ),
                        child: NotifToggleTile(
                          showCard: false,
                          title: 'Heads-up Alerts',
                          subtitle: 'Before rounds start',
                          value: prefs.headsUpAlerts,
                          onChanged:
                              !interactive
                                  ? null
                                  : (value) {
                                    _trackPersist(
                                      ref
                                          .read(
                                            notificationPreferencesProvider
                                                .notifier,
                                          )
                                          .setHeadsUpAlerts(value),
                                    );
                                  },
                          trailing: NotifLeadTimeControl(
                            value: prefs.headsUpLeadMinutes,
                            onChanged:
                                (!interactive || !prefs.headsUpAlerts)
                                    ? null
                                    : (minutes) {
                                      _trackPersist(
                                        ref
                                            .read(
                                              notificationPreferencesProvider
                                                  .notifier,
                                            )
                                            .setHeadsUpLeadMinutes(minutes),
                                      );
                                    },
                          ),
                        ),
                      ),
                      /*
                      Divider(
                        height: 1,
                        color: context.colors.divider.withValues(alpha: 0.4),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 14.sp,
                          vertical: 14.sp,
                        ),
                        child: NotifToggleTile(
                          showCard: false,
                          title: 'Live Updates',
                          subtitle: 'Get live move-by-move updates and alerts.',
                          value: prefs.liveGameUpdates,
                          badge: const BetaBadge(),
                          onChanged:
                              !interactive
                                  ? null
                                  : (value) {
                                    _trackPersist(
                                      ref
                                          .read(
                                            notificationPreferencesProvider
                                                .notifier,
                                          )
                                          .setLiveGameUpdates(value),
                                    );
                                  },
                        ),
                      ),
                      */
                    ],
                  ),
                ),

                SizedBox(height: 24.h),

                // ── LIBRARY ───────────────────────────────────────────────
                const NotifSectionHeader(title: 'Library'),

                NotifToggleTile(
                  title: 'Database Updates',
                  subtitle:
                      'Get notified when games are added, updated, or removed in your subscribed databases.',
                  value: prefs.bookUpdateAlerts,
                  onChanged:
                      !interactive
                          ? null
                          : (value) {
                            _trackPersist(
                              ref
                                  .read(
                                    notificationPreferencesProvider.notifier,
                                  )
                                  .setBookUpdateAlerts(value),
                            );
                          },
                ),

                SizedBox(height: 24.h),

                // ── UPDATES ───────────────────────────────────────────────
                const NotifSectionHeader(title: 'Updates'),

                NotifToggleTile(
                  title: 'Chess World',
                  subtitle: 'Get occasional highlights from chess.',
                  value: prefs.callToActionAlerts,
                  onChanged:
                      !interactive
                          ? null
                          : (value) {
                            _trackPersist(
                              ref
                                  .read(
                                    notificationPreferencesProvider.notifier,
                                  )
                                  .setCallToActionAlerts(value),
                            );
                          },
                ),

                SizedBox(height: 24.h),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
