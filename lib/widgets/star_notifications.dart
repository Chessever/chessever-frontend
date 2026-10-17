import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/notification_permission_provider.dart';
import 'package:chessever2/providers/notification_preferences_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:chessever2/services/push_notifications_service.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/alert_dialog/alert_modal.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The flag a starred collection carries in its favorites row's `metadata`
/// once its owner has answered whether it notifies. The dispatcher reads it
/// the way [starNotificationsEnabled] does.
const String kStarNotificationsKey = 'notificationsEnabled';

/// Set on a starred smart event when its owner turns its pushes off, and
/// cleared when they turn them back on. [kStarNotificationsKey] cannot say
/// that for smart events: older builds saved every new smart star with it
/// false. The four-hour "new games" push
/// (`queue_smart_event_digests`) reads this key alone.
const String kStarMutedKey = 'notificationsMuted';

bool _isSmartEventStar(String eventId, Map<String, dynamic> metadata) =>
    eventId.startsWith('smart_event:') || metadata['type'] == 'smart_event';

/// Whether the starred row [favorite] sends notifications.
///
/// A smart event's star does unless its owner muted it: starring one is
/// subscribing to its new games. So does a collection's, unless its owner
/// turned that off: starring one is asking to hear about its new games
/// (Trello #1225), and a star made before the question, on the desktop app
/// or on an older build never answered it.
bool starNotificationsEnabled(FavoriteEvent favorite) {
  if (_isSmartEventStar(favorite.eventId, favorite.metadata)) {
    return favorite.metadata[kStarMutedKey] != true;
  }
  final flag = favorite.metadata[kStarNotificationsKey];
  if (flag is bool) return flag;
  return favorite.eventId.startsWith('collection:') ||
      favorite.metadata['kind'] == 'collection';
}

/// Asks, right after a star, whether it should also send notifications.
/// [message] says what would arrive ("Get an alert when a round starts or
/// finishes in GM Games."). True only on an explicit yes: dismissing the
/// dialog keeps the star and leaves it quiet.
Future<bool> askStarNotifications(
  BuildContext context, {
  required String message,
}) async {
  final answer = await showSmoothConfirmDialog(
    context: context,
    title: 'Turn on notifications?',
    message: message,
    confirmText: 'Turn on',
    cancelText: 'Not now',
  );
  return answer == true;
}

/// Sets whether the starred row [eventId] notifies, and when turning it on
/// makes sure this account and this device can actually be reached.
///
/// Takes the container and the messenger rather than a `ref` and a
/// `context`: it runs after a dialog or a menu has closed, by which time the
/// card that asked may be gone. [confirm] raises a snack for the new state,
/// for callers with no dialog of their own to show that it took.
Future<void> setStarNotifications({
  required ProviderContainer container,
  required ScaffoldMessengerState? messenger,
  required String eventId,
  required bool enabled,
  required String surface,
  bool confirm = false,
}) async {
  void snack(String message, {AppSnackTone tone = AppSnackTone.neutral}) {
    if (messenger == null || !messenger.mounted) return;
    showAppSnackOn(messenger, message, tone: tone);
  }

  try {
    await container
        .read(favoriteEventsProvider.notifier)
        .updateMetadata(eventId, {
          kStarNotificationsKey: enabled,
          if (_isSmartEventStar(eventId, const {})) kStarMutedKey: !enabled,
        });
  } catch (error) {
    snack(
      userFacingError(
        error,
        fallback: 'Could not change notifications. Try again.',
      ),
      tone: AppSnackTone.danger,
    );
    return;
  }
  AnalyticsService.instance.trackEventDetached(
    'Star Notifications Toggled',
    properties: {'surface': surface, 'enabled': enabled},
  );
  if (!enabled) {
    if (confirm) snack('Notifications turned off');
    return;
  }
  final reachable = await _makeReachable(container, messenger);
  if (reachable && confirm) snack('Notifications turned on');
}

/// Makes a new smart event star's four-hour push reachable: starring one
/// turns its pushes on, with no question. Sent under starred-event alerts.
Future<bool> makeSmartEventStarReachable({
  required ProviderContainer container,
  required ScaffoldMessengerState? messenger,
}) => _makeReachable(container, messenger);

/// Makes a starred My Prep player's daily push reachable, as a yes does for
/// a starred event. The dispatcher sends it under favorite-player alerts.
Future<bool> makePlayerStarReachable({
  required ProviderContainer container,
  required ScaffoldMessengerState? messenger,
}) => _makeReachable(container, messenger, playerAlerts: true);

/// A yes means nothing if starred alerts are switched off for the account or
/// the device refuses ChessEver's notifications: turn the first back on, and
/// for the second show the system prompt, or point at Settings when the
/// system will not ask again. False when it ended on that Settings hint.
/// [playerAlerts] picks the favorite-player switch over the event one.
Future<bool> _makeReachable(
  ProviderContainer container,
  ScaffoldMessengerState? messenger, {
  bool playerAlerts = false,
}) async {
  try {
    final prefs = await container.read(notificationPreferencesProvider.future);
    final settings = container.read(notificationPreferencesProvider.notifier);
    if (playerAlerts) {
      if (!prefs.favoritePlayerAlerts) {
        await settings.setFavoritePlayerAlerts(true);
      }
    } else if (!prefs.favoriteEventAlerts) {
      await settings.setFavoriteEventAlerts(true);
    }
  } catch (_) {
    // The dispatcher treats a missing preference row as allowed.
  }

  final service = PushNotificationsService.instance;
  bool granted;
  try {
    granted = await service.isPermissionGranted();
    if (!granted && await service.canRequestPermission()) {
      granted = await service.requestPermissionWithDialog();
    }
    // Keeps the Settings switch and the account's push flag on the OS truth.
    unawaited(
      container.read(notificationPermissionProvider.notifier).refresh(),
    );
  } catch (_) {
    // Permission could not be read: say nothing rather than guess a denial.
    return true;
  }
  if (granted) return true;
  if (messenger != null && messenger.mounted) {
    showAppSnackOn(
      messenger,
      'Notifications are off for ChessEver on this device.',
      actionLabel: 'Settings',
      onAction: () =>
          AppSettings.openAppSettings(type: AppSettingsType.notification),
    );
  }
  return false;
}

/// The focus-menu row that turns a starred row's notifications on or off.
/// Hidden while [favorite] is null: only a star can notify.
///
/// Like every menu row it runs after the menu route has popped, so what it
/// needs is resolved here, while the host is still mounted.
LibraryMenuAction starNotificationsMenuAction({
  required BuildContext context,
  required FavoriteEvent? favorite,
  required String surface,
}) {
  final enabled = favorite != null && starNotificationsEnabled(favorite);
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);
  return LibraryMenuAction(
    icon: enabled
        ? Icons.notifications_off_outlined
        : Icons.notifications_none_outlined,
    label: enabled ? 'Turn off notifications' : 'Turn on notifications',
    visible: favorite != null,
    enabled: favorite != null,
    onSelected: () async {
      if (favorite == null) return;
      await setStarNotifications(
        container: container,
        messenger: messenger,
        eventId: favorite.eventId,
        enabled: !enabled,
        surface: surface,
        confirm: true,
      );
    },
  );
}
