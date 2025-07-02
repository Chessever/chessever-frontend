import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    try {
      // Request notification permission during initialization
      print('Requesting notification permissions...');
      await _requestNotificationPermission();

      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/launcher_icon');

      final DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings(
            requestAlertPermission: false, // We handled it manually above
            requestBadgePermission: false, // We handled it manually above
            requestSoundPermission: false, // We handled it manually above
          );

      final InitializationSettings initializationSettings =
          InitializationSettings(
            android: initializationSettingsAndroid,
            iOS: initializationSettingsIOS,
          );

      await _notificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          // Handle tap on notification
        },
      );

      // Create notification channel for Android
      if (Platform.isAndroid) {
        await _createNotificationChannel();
      }

      // Check final permission status
      final hasPermission = await isNotificationPermissionGranted();
      if (hasPermission) {
        print(
          'Notifications initialized successfully with permissions granted',
        );
      } else {
        print('Notifications initialized but permissions not granted');
      }
    } catch (e) {
      print('Error initializing notifications: $e');
      // Don't rethrow - let the app continue without notifications
    }
  }

  /// Request notification permission for both Android and iOS
  static Future<bool> _requestNotificationPermission() async {
    if (Platform.isAndroid) {
      if (await Permission.notification.isGranted) {
        print('Android notification permission already granted');
        return true;
      }

      print('Requesting Android notification permission...');
      final status = await Permission.notification.request();
      final granted = status == PermissionStatus.granted;

      if (granted) {
        print('Android notification permission granted');
      } else {
        print('Android notification permission denied: $status');
      }

      return granted;
    } else if (Platform.isIOS) {
      // Check if already granted
      final currentPermissions =
          await _notificationsPlugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.checkPermissions();

      if (currentPermissions?.isAlertEnabled == true ||
          currentPermissions?.isBadgeEnabled == true ||
          currentPermissions?.isSoundEnabled == true) {
        print('iOS notification permissions already granted');
        return true;
      }

      print('Requesting iOS notification permissions...');
      // For iOS, use the flutter_local_notifications plugin method
      final bool? result = await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);

      final granted = result ?? false;
      if (granted) {
        print('iOS notification permissions granted');
      } else {
        print('iOS notification permissions denied');
      }

      return granted;
    }

    print('Unknown platform for notification permissions');
    return false;
  }

  /// Create notification channel for Android
  static Future<void> _createNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel', // channel ID
      'High Importance Notifications', // channel name
      description: 'This channel is used for important notifications.',
      importance: Importance.max,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  /// Check if notification permission is granted for both platforms
  static Future<bool> isNotificationPermissionGranted() async {
    if (Platform.isAndroid) {
      return await Permission.notification.isGranted;
    } else if (Platform.isIOS) {
      final bool? result = await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.checkPermissions()
          .then(
            (permissions) =>
                permissions?.isAlertEnabled == true ||
                permissions?.isBadgeEnabled == true ||
                permissions?.isSoundEnabled == true,
          );
      return result ?? false;
    }
    return false;
  }

  /// Show notification with permission check
  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      // Check permission before showing notification
      if (!await isNotificationPermissionGranted()) {
        print('Cannot show notification: Permission not granted');
        print(
          'Use NotificationService.requestPermissionWithDialog() to request permission',
        );
        return;
      }

      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
            'high_importance_channel', // channel ID
            'High Importance Notifications', // channel name
            importance: Importance.max,
            priority: Priority.high,
            showWhen: true,
            icon: '@mipmap/launcher_icon',
          );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

      const NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notificationsPlugin.show(
        id,
        title,
        body,
        platformDetails,
        payload: 'Default_Sound',
      );

      print('Notification shown successfully: $title');
    } catch (e) {
      print('Error showing notification: $e');
    }
  }

  /// Request permission with user-friendly dialog for both platforms
  static Future<bool> requestPermissionWithDialog() async {
    print('Checking current notification permission status...');

    if (await isNotificationPermissionGranted()) {
      print('Notification permission already granted');
      return true;
    }

    print('Requesting notification permission...');

    if (Platform.isAndroid) {
      final status = await Permission.notification.request();

      if (status == PermissionStatus.granted) {
        print('Android notification permission granted via dialog');
        return true;
      } else if (status == PermissionStatus.permanentlyDenied) {
        print(
          'Android notification permission permanently denied - opening app settings',
        );
        // Guide user to app settings
        await openAppSettings();
        return false;
      } else {
        print('Android notification permission denied: $status');
        return false;
      }
    } else if (Platform.isIOS) {
      // For iOS, request permissions through flutter_local_notifications
      final bool? result = await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);

      final granted = result ?? false;
      if (granted) {
        print('iOS notification permissions granted via dialog');
      } else {
        print('iOS notification permissions denied via dialog');
      }

      return granted;
    }

    print('Unknown platform for notification permission dialog');
    return false;
  }

  /// Get detailed permission status (mainly for iOS)
  static Future<Map<String, bool>> getDetailedPermissionStatus() async {
    if (Platform.isIOS) {
      final permissions =
          await _notificationsPlugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.checkPermissions();

      return {
        'alert': permissions?.isAlertEnabled ?? false,
        'badge': permissions?.isBadgeEnabled ?? false,
        'sound': permissions?.isSoundEnabled ?? false,
        'criticalAlert': permissions?.isCriticalEnabled ?? false,
        'provisional': permissions?.isBadgeEnabled ?? false,
      };
    } else if (Platform.isAndroid) {
      final granted = await Permission.notification.isGranted;
      return {'notification': granted};
    }

    return {};
  }
}
