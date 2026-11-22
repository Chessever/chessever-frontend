import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:chessever2/services/firebase_app.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_environment.dart';
import 'deep_link_service.dart';
import 'direct_push_tap_router.dart';
import 'native_push_permission.dart';
import 'onesignal_push_payload.dart';

/// Receipts are persisted locally and flushed after Supabase is ready.
/// A background callback is evidence of receipt; absence of one is not a failure.
///
/// On Android a data-only message in OneSignal's format (O6) is drawn here
/// while this install has not registered directly (with the SDK gone nothing
/// else would show it); once it has, such a message is a mirror's duplicate
/// and is dropped ([DirectPushService.presentOneSignalPush]).
@pragma('vm:entry-point')
Future<void> directPushBackgroundHandler(RemoteMessage message) async {
  if (message.notification == null &&
      await DirectPushService.presentOneSignalPush(
        message.data,
        background: true,
      )) {
    return;
  }
  if (message.data['delivery_id'] is! String) return;
  await DirectPushService.storeEvent(message.data, 'received');
}

class DirectPushService with WidgetsBindingObserver {
  DirectPushService._();
  static final instance = DirectPushService._();
  static const _enabled = bool.fromEnvironment(
    'CHESSEVER_DIRECT_PUSH_ENABLED',
    defaultValue: true,
  );
  static const _productionUrl = String.fromEnvironment(
    'CHESSEVER_NOTIFICATION_URL',
    defaultValue: 'https://chessever-notifications.young-sun-69a8.workers.dev',
  );
  static const _testUrl = String.fromEnvironment(
    'CHESSEVER_TEST_NOTIFICATION_URL',
  );
  static String get _url => AppEnvironment.isTest ? _testUrl : _productionUrl;
  final _local = FlutterLocalNotificationsPlugin();
  final _tapRouter = DirectPushTapRouter();
  bool _ready = false;
  bool _observingLifecycle = false;
  bool _syncing = false;
  bool _syncAgain = false;
  String? _owner;

  /// The account this install registered for directly ([sync]), removed
  /// once it is detached ([detach]). Legacy [SharedPreferences], which the
  /// background isolate reads too ([presentOneSignalPush]).
  static const _ownerKey = 'direct_push_owner';
  Future<void>? _starting;
  Timer? _registrationRetry;
  int _registrationAttempts = 0;

  static bool get configured =>
      _enabled &&
      Uri.tryParse(_url)?.scheme == 'https' &&
      (!AppEnvironment.isTest || _url != _productionUrl);

  Future<void> initialize() => _starting ??= _initialize();
  Future<void> _initialize() async {
    if (!configured ||
        kIsWeb ||
        ![
          TargetPlatform.iOS,
          TargetPlatform.android,
        ].contains(defaultTargetPlatform)) {
      return;
    }
    if (!_observingLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      _observingLifecycle = true;
    }
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _tapRouter.initializeNative(_open);
      }
      await ensureFirebaseInitialized();
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await refreshNativeAPNsRegistration();
      }
      FirebaseMessaging.onBackgroundMessage(directPushBackgroundHandler);
      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null) {
            _open(Map<String, dynamic>.from(jsonDecode(payload) as Map));
          }
        },
      );
      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              'chessever_direct',
              'ChessEver alerts',
              description: 'ChessEver notifications',
              importance: Importance.high,
            ),
          );
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
            alert: true,
            badge: true,
            sound: true,
          );
      FirebaseMessaging.onMessage.listen(
        (message) => unawaited(handleForegroundMessage(message)),
      );
      FirebaseMessaging.onMessageOpenedApp.listen(
        (m) => _tapRouter.open(m.messageId, m.data, _open),
      );
      FirebaseMessaging.instance.onTokenRefresh.listen(
        (_) => unawaited(sync()),
      );
      Supabase.instance.client.auth.onAuthStateChange.listen((state) {
        final next = state.session?.user.id;
        if (_owner != null && next != _owner) {
          unawaited(detach().then((_) => sync()));
        } else {
          unawaited(sync());
        }
      });
      _owner = (await SharedPreferences.getInstance()).getString(_ownerKey);
      _ready = true;
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        _tapRouter.open(initial.messageId, initial.data, _open);
      }
      final localLaunch = await _local.getNotificationAppLaunchDetails();
      final payload = localLaunch?.notificationResponse?.payload;
      if (localLaunch?.didNotificationLaunchApp == true && payload != null) {
        _open(Map<String, dynamic>.from(jsonDecode(payload) as Map));
      }
      await sync();
    } catch (e) {
      debugPrint(
        '[DirectPush] Not ready (${e.runtimeType}); registration will retry.',
      );
      _starting = null;
      _retryRegistration();
    }
  }

  /// A push arriving while the app is in the foreground
  /// ([FirebaseMessaging.onMessage]). Its receipt is stored, and on Android,
  /// where the system draws nothing then, the app shows it: a notification
  /// push through its own channel, a data-only one only in OneSignal's
  /// format and only while this install has not registered directly (O6,
  /// [presentOneSignalPush]).
  @visibleForTesting
  Future<void> handleForegroundMessage(RemoteMessage message) async {
    // Inline tester pushes intentionally have no persisted delivery ID.
    if (message.data['delivery_id'] is String) {
      unawaited(
        storeEvent(message.data, 'received').then((_) => flushEvents()),
      );
    }
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final notification = message.notification;
    if (notification == null) {
      // OneSignal's data-only format (O6): drawn by the app now.
      await presentOneSignalPush(message.data);
      return;
    }
    final notificationId =
        message.messageId ??
        message.data['delivery_id'] as String? ??
        DateTime.now().microsecondsSinceEpoch.toString();
    await _local.show(
      notificationId.hashCode & 0x7fffffff,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'chessever_direct',
          'ChessEver alerts',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _registrationAttempts = 0;
      unawaited(_ready ? sync() : initialize());
    }
  }

  static String _randomHex(int bytes) {
    final random = Random.secure();
    return List.generate(
      bytes,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<Map<String, String>> _proof() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('direct_push_installation');
    var secret = prefs.getString('direct_push_secret');
    if (id == null || secret == null) {
      final h = _randomHex(16);
      id =
          '${h.substring(0, 8)}-${h.substring(8, 12)}-4${h.substring(13, 16)}-8${h.substring(17, 20)}-${h.substring(20)}';
      secret = _randomHex(32);
      await prefs.setString('direct_push_installation', id);
      await prefs.setString('direct_push_secret', secret);
    }
    return {'installationId': id, 'installationSecret': secret};
  }

  void _retryRegistration() {
    if (_registrationAttempts >= 5) return;
    _registrationAttempts++;
    _registrationRetry?.cancel();
    _registrationRetry = Timer(
      const Duration(seconds: 5),
      () => unawaited(_ready ? sync() : initialize()),
    );
  }

  Future<void> sync() async {
    if (!_ready) return;
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    try {
      final session = Supabase.instance.client.auth.currentSession;
      final prefs = await SharedPreferences.getInstance();
      if ((_owner != null && _owner != session?.user.id) ||
          prefs.getBool('direct_push_detach_pending') == true) {
        if (!await detach()) return;
      }
      if (session == null) return;
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      final apnsToken = defaultTargetPlatform == TargetPlatform.iOS
          ? await FirebaseMessaging.instance.getAPNSToken()
          : null;
      if (defaultTargetPlatform == TargetPlatform.iOS && apnsToken == null) {
        final nativeError = await refreshNativeAPNsRegistration();
        if (nativeError != null) {
          debugPrint('[DirectPush] APNs registration error: $nativeError');
        }
        debugPrint(
          '[DirectPush] Waiting for APNs token; registration retry scheduled.',
        );
        _retryRegistration();
        return;
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        _retryRegistration();
        return;
      }
      final package = await PackageInfo.fromPlatform();
      final timezone = await deviceTimezone();
      Future<http.Response> register({required bool withTimezone}) async => http
          .post(
            Uri.parse('$_url/v1/devices'),
            headers: {
              'authorization': 'Bearer ${session.accessToken}',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              ...await _proof(), 'token': token,
              // Match only an owned legacy mirror on upgrade, to prevent duplicate delivery.
              if (defaultTargetPlatform == TargetPlatform.iOS &&
                  apnsToken != null)
                'legacyPushToken': apnsToken,
              'platform': defaultTargetPlatform == TargetPlatform.iOS
                  ? 'ios'
                  : 'android',
              'optedIn': [
                AuthorizationStatus.authorized,
                AuthorizationStatus.provisional,
              ].contains(settings.authorizationStatus),
              'appVersion': '${package.version}+${package.buildNumber}',
              'language': WidgetsBinding.instance.platformDispatcher.locale
                  .toLanguageTag(),
              // Pushes timed to the reader's day (smart events, Prep) read it.
              if (withTimezone && timezone != null) 'timezone': timezone,
            }),
          )
          .timeout(const Duration(seconds: 15));
      var response = await register(withTimezone: true);
      // A zone the service does not accept never costs the registration.
      if (response.statusCode == 400 && timezone != null) {
        response = await register(withTimezone: false);
      }
      if (response.statusCode >= 300) {
        debugPrint(
          '[DirectPush] Registration rejected (HTTP ${response.statusCode}).',
        );
        throw StateError('Registration rejected');
      }
      _registrationRetry?.cancel();
      _registrationAttempts = 0;
      debugPrint(
        '[DirectPush] Installation registered (${package.version}+${package.buildNumber}).',
      );
      _owner = session.user.id;
      await prefs.setString(_ownerKey, _owner!);
      if (Supabase.instance.client.auth.currentUser?.id != _owner) {
        await detach();
        return;
      }
      await flushEvents();
    } catch (e) {
      debugPrint(
        '[DirectPush] Sync deferred (${e.runtimeType}); retry scheduled.',
      );
      _retryRegistration();
    } finally {
      _syncing = false;
      if (_syncAgain) {
        _syncAgain = false;
        unawaited(sync());
      }
    }
  }

  /// The phone's IANA timezone ("Asia/Baku"), or null when the platform
  /// gives something else (an abbreviation, a bare offset).
  @visibleForTesting
  static Future<String?> deviceTimezone({
    Future<String> Function()? read,
  }) async {
    try {
      final zone =
          await (read ??
                  () async =>
                      (await FlutterTimezone.getLocalTimezone()).identifier)()
              .timeout(const Duration(seconds: 2));
      return isIanaTimezone(zone) ? zone : null;
    } catch (_) {
      return null;
    }
  }

  /// "Europe/Berlin", "America/Argentina/Buenos_Aires", "Etc/GMT-4" or "UTC".
  @visibleForTesting
  static bool isIanaTimezone(String zone) =>
      zone == 'UTC' ||
      RegExp(
        r'^[A-Za-z][A-Za-z0-9_+\-]*(/[A-Za-z0-9][A-Za-z0-9_+\-]*)+$',
      ).hasMatch(zone);

  Future<bool> detach() async {
    if (!configured) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('direct_push_detach_pending', true);
    try {
      final response = await http
          .post(
            Uri.parse('$_url/v1/devices/logout'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(await _proof()),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return false;
      _owner = null;
      await prefs.remove(_ownerKey);
      await prefs.remove('direct_push_detach_pending');
      return true;
    } catch (e) {
      debugPrint('[DirectPush] Detach deferred (${e.runtimeType})');
      return false;
    }
  }

  static Future<void> storeEvent(
    Map<String, dynamic> data,
    String event,
  ) async {
    final id = data['delivery_id'];
    if (id is! String) return;
    final prefs = SharedPreferencesAsync();
    // One key per event avoids losing receipts to foreground/background list races.
    await prefs.setString(
      'direct_push_event_${id}_$event',
      jsonEncode({'deliveryId': id, 'event': event}),
    );
  }

  /// Android's channel for every push the app draws itself.
  static const _androidDetails = AndroidNotificationDetails(
    'chessever_direct',
    'ChessEver alerts',
    channelDescription: 'ChessEver notifications',
    importance: Importance.high,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher',
  );

  /// OneSignal ids already drawn, newest last, across launches and isolates.
  static const _oneSignalShownKey = 'direct_push_onesignal_shown';
  static const _oneSignalShownMax = 50;

  /// Draws an Android data-only push in OneSignal's format (O6) through the
  /// app's own notification path: its title and text, and the unwrapped data
  /// as the payload, so a tap routes like any push
  /// ([FlutterLocalNotificationsPlugin]'s response, or its launch details).
  /// One OneSignal notification is drawn once: its id names the
  /// notification and is remembered. False when [data] is not such a push
  /// (or not on Android), so the caller handles it as before.
  ///
  /// Drawn only while this install has not registered directly
  /// ([_registeredDirectly]). Once it has, the notification service sends
  /// every push itself, and the same push arriving in OneSignal's format
  /// comes from the account's old OneSignal registration (a mirror) the
  /// server has not dropped yet: it is taken (true) and not drawn, so the
  /// reader never sees one push twice.
  ///
  /// [background] for the background isolate: the plugin is set up there,
  /// and the registration is read anew, since the app may have registered
  /// after that isolate first read it.
  static Future<bool> presentOneSignalPush(
    Map<String, dynamic> data, {
    bool background = false,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    final push = parseOneSignalPush(data);
    if (push == null) return false;
    // A silent one (no text) has nothing to show and nothing to tap.
    if (push.title == null && push.body == null) return true;
    // A mirror's copy of a push the service delivers directly.
    if (await _registeredDirectly(reread: background)) return true;
    try {
      final prefs = SharedPreferencesAsync();
      final shown = await prefs.getStringList(_oneSignalShownKey) ?? const [];
      if (shown.contains(push.id)) return true;
      await prefs.setStringList(_oneSignalShownKey, [
        ...shown.skip(
          (shown.length - _oneSignalShownMax + 1).clamp(0, shown.length),
        ),
        push.id,
      ]);
    } catch (_) {
      // No memory to check: the notification id still keeps it single.
    }
    final local = FlutterLocalNotificationsPlugin();
    if (background) {
      await local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
    }
    await local.show(
      oneSignalNotificationId(push.id),
      push.title,
      push.body,
      const NotificationDetails(android: _androidDetails),
      payload: jsonEncode(push.data),
    );
    return true;
  }

  /// Whether this install has registered with the notification service
  /// directly: [sync] stores the account it registered for ([_ownerKey]) and
  /// [detach] removes it. [reread] in the background isolate, whose cached
  /// copy predates any registration the app made since; the app's own
  /// isolate writes through the cache it reads. Unreadable counts as not
  /// registered: the push is drawn, once per OneSignal id.
  static Future<bool> _registeredDirectly({required bool reread}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (reread) await prefs.reload();
      return prefs.getString(_ownerKey) != null;
    } catch (_) {
      return false;
    }
  }

  void _open(Map<String, dynamic> raw) {
    final data = unwrapOneSignalPush(raw);
    if (data['delivery_id'] is String) {
      unawaited(storeEvent(data, 'opened').then((_) => flushEvents()));
    }
    DeepLinkService.instance.ingestNotificationData(data);
  }

  Future<void> flushEvents() async {
    if (!configured) return;
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return;
    final prefs = SharedPreferencesAsync();
    final keys = await prefs.getKeys();
    for (final key
        in keys.where((k) => k.startsWith('direct_push_event_')).take(100)) {
      try {
        final payload = await prefs.getString(key);
        if (payload == null) continue;
        final response = await http
            .post(
              Uri.parse('$_url/v1/events'),
              headers: {
                'authorization': 'Bearer ${session.accessToken}',
                'content-type': 'application/json',
              },
              body: payload,
            )
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) await prefs.remove(key);
      } catch (_) {
        break;
      }
    }
  }
}
