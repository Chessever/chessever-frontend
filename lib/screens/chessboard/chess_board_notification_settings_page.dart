import 'package:chessever2/providers/notification_preferences_provider.dart';
import 'package:chessever2/providers/notifications_settings_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
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
        backgroundColor: kBackgroundColor,
        appBar: AppBar(
          title: Text(
            'Notification Settings',
            style: AppTypography.textLgMedium.copyWith(
              color: kWhiteColor,
              fontSize: 16.f,
            ),
          ),
          backgroundColor: kBackgroundColor,
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
                _SectionLabel(title: 'Push'),
                SizedBox(height: 12.h),
                _SettingCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Push notifications',
                              style: AppTypography.textMdMedium.copyWith(
                                color: kWhiteColor,
                                fontSize: 13.f,
                              ),
                            ),
                            SizedBox(height: 4.h),
                            Text(
                              'Enable alerts for game starts, finishes, and live updates.',
                              style: AppTypography.textSmRegular.copyWith(
                                color: kWhiteColor70,
                                fontSize: 11.f,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: pushEnabled,
                        thumbColor: WidgetStatePropertyAll(kPrimaryColor),
                        trackColor: WidgetStateProperty.resolveWith(
                          (states) =>
                              states.contains(WidgetState.selected)
                                  ? kPrimaryColor.withValues(alpha: 0.35)
                                  : kDividerColor.withValues(alpha: 0.5),
                        ),
                        onChanged: (value) {
                          _trackPersist(
                            ref
                                .read(notificationsSettingsProvider.notifier)
                                .setEnabled(value),
                          );
                          if (!value) {
                            _trackPersist(
                              ref
                                  .read(
                                    notificationPreferencesProvider.notifier,
                                  )
                                  .disableAll(),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 18.h),
                _SectionLabel(title: 'Favorites & Live'),
                SizedBox(height: 12.h),
                _SettingCard(
                  child: _ToggleRow(
                    title: 'Favorite players',
                    description:
                        'Get updates when your starred players start or finish.',
                    value: prefs.favoritePlayerAlerts,
                    onChanged:
                        (!pushEnabled || prefsLoading)
                            ? null
                            : (value) {
                              _trackPersist(
                                ref
                                    .read(
                                      notificationPreferencesProvider.notifier,
                                    )
                                    .setFavoritePlayerAlerts(value),
                              );
                            },
                  ),
                ),
                SizedBox(height: 12.h),
                _SettingCard(
                  child: _ToggleRow(
                    title: 'Favorite events',
                    description:
                        'Stay notified when your saved tournaments begin.',
                    value: prefs.favoriteEventAlerts,
                    onChanged:
                        (!pushEnabled || prefsLoading)
                            ? null
                            : (value) {
                              _trackPersist(
                                ref
                                    .read(
                                      notificationPreferencesProvider.notifier,
                                    )
                                    .setFavoriteEventAlerts(value),
                              );
                            },
                  ),
                ),
                SizedBox(height: 12.h),
                _SettingCard(
                  child: _ToggleRow(
                    title: 'Heads-up alerts',
                    description:
                        'Optional reminders shortly before a round starts.',
                    value: prefs.headsUpAlerts,
                    onChanged:
                        (!pushEnabled || prefsLoading)
                            ? null
                            : (value) {
                              _trackPersist(
                                ref
                                    .read(
                                      notificationPreferencesProvider.notifier,
                                    )
                                    .setHeadsUpAlerts(value),
                              );
                            },
                  ),
                ),
                SizedBox(height: 12.h),
                _SettingCard(
                  child: _ToggleRow(
                    title: 'Live game updates',
                    titleTrailing: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 6.sp,
                        vertical: 2.sp,
                      ),
                      decoration: BoxDecoration(
                        color: kPrimaryColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4.br),
                      ),
                      child: Text(
                        'Experimental',
                        style: AppTypography.textSmRegular.copyWith(
                          color: kPrimaryColor,
                          fontSize: 9.f,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    description:
                        'Receive move-by-move Live Activity and live alerts.',
                    value: prefs.liveGameUpdates,
                    onChanged:
                        (!pushEnabled || prefsLoading)
                            ? null
                            : (value) {
                              _trackPersist(
                                ref
                                    .read(
                                      notificationPreferencesProvider.notifier,
                                    )
                                    .setLiveGameUpdates(value),
                              );
                            },
                  ),
                ),
                SizedBox(height: 18.h),
                _SectionLabel(title: 'Library'),
                SizedBox(height: 12.h),
                _SettingCard(
                  child: _ToggleRow(
                    title: 'Database updates',
                    description:
                        'Get notified when new games are added to your subscribed databases.',
                    value: prefs.bookUpdateAlerts,
                    onChanged:
                        (!pushEnabled || prefsLoading)
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
                ),
                SizedBox(height: 18.h),
                _SectionLabel(title: 'Updates'),
                SizedBox(height: 12.h),
                _SettingCard(
                  child: _ToggleRow(
                    title: 'Chess world updates',
                    description:
                        'Get occasional highlights from the chess and ChessEver world.',
                    value: prefs.callToActionAlerts,
                    onChanged:
                        (!pushEnabled || prefsLoading)
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: 6.h),
        child: Text(
          title,
          style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
        ),
      ),
    );
  }
}

class _SettingCard extends StatelessWidget {
  const _SettingCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.sp, vertical: 12.sp),
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: kDividerColor.withValues(alpha: 0.5)),
      ),
      child: child,
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.description,
    required this.value,
    this.titleTrailing,
    this.onChanged,
  });

  final String title;
  final String description;
  final bool value;
  final Widget? titleTrailing;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: AppTypography.textMdMedium.copyWith(
                      color: kWhiteColor,
                      fontSize: 13.f,
                    ),
                  ),
                  if (titleTrailing != null) ...[
                    SizedBox(width: 6.sp),
                    titleTrailing!,
                  ],
                ],
              ),
              SizedBox(height: 4.h),
              Text(
                description,
                style: AppTypography.textSmRegular.copyWith(
                  color: kWhiteColor70,
                  fontSize: 11.f,
                ),
              ),
            ],
          ),
        ),
        Switch.adaptive(
          value: value,
          onChanged: onChanged,
          thumbColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected)
                    ? kPrimaryColor
                    : kWhiteColor.withValues(alpha: 0.6),
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected)
                    ? kPrimaryColor.withValues(alpha: 0.35)
                    : kDividerColor.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}
