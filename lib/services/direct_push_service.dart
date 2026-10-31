import 'news_binding_store.dart';
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
import 'direct_push_registration_controller.dart';
import 'favorite_player_news_preference_store.dart';
import 'favorite_player_news_token_sync.dart';

/// Receipts are persisted locally and flushed after Supabase is ready.
/// A background callback is evidence of receipt; absence of one is not a failure.
@pragma('vm:entry-point')
Future<void> directPushBackgroundHandler(RemoteMessage message) async {
  if (await NewsBindingStore().receive(message.data)) return;
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
  String? _oneSignalId;
  bool _optedIn = false;
  Future<void>? _starting;
  StreamSubscription<AuthState>? _authSubscription;
  late final _registration = DirectPushRegistrationController(
    store: FavoritePlayerNewsPreferenceStore(),
    transport: DirectPushDeviceTransport(
      baseUri: Uri.parse(_url),
      client: http.Client(),
    ),
    readSession: () {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null || session.isExpired) return null;
      return DirectPushSession(session.user.id, session.accessToken);
    },
    readProof: _proof,
    readRegistration: _registrationData,
  );
  ValueListenable<FavoritePlayerNewsSyncStatus> get newsSyncStatus =>
      _registration.status;

  Future<void> syncNewsPreference() async {
    if (!configured) {
      throw StateError('Saved on this device. News alert sync is pending.');
    }
    await _registration.preferenceChanged();
  }

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
    try {
      // Category opt-out and durable detach do not depend on Firebase/APNs or
      // the OneSignal mirror. Install auth reconciliation before platform setup.
      _authSubscription ??= Supabase.instance.client.auth.onAuthStateChange
          .listen((state) {
            final session = state.session;
            unawaited(
              _registration.authChanged(
                session == null || session.isExpired ? null : session.user.id,
              ),
            );
          });
      if (!_observingLifecycle) {
        WidgetsBinding.instance.addObserver(this);
        _observingLifecycle = true;
      }
      await _registration.initialize();
      unawaited(_registration.sync());
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _tapRouter.initializeNative(_open);
      }
      await ensureFirebaseInitialized();
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
      FirebaseMessaging.onMessage.listen((message) async {
        if (await _bindingCallback(message.data)) return;
        // Inline tester pushes intentionally have no persisted delivery ID.
        if (message.data['delivery_id'] is String) {
          unawaited(
            storeEvent(message.data, 'received').then((_) => flushEvents()),
          );
        }
        if (defaultTargetPlatform == TargetPlatform.android &&
            message.notification != null) {
          final notificationId =
              message.messageId ??
              message.data['delivery_id'] as String? ??
              DateTime.now().microsecondsSinceEpoch.toString();
          unawaited(
            _local.show(
              notificationId.hashCode & 0x7fffffff,
              message.notification!.title,
              message.notification!.body,
              const NotificationDetails(
                android: AndroidNotificationDetails(
                  'chessever_direct',
                  'ChessEver alerts',
                  importance: Importance.high,
                  priority: Priority.high,
                ),
              ),
              payload: jsonEncode(message.data),
            ),
          );
        }
      });
      FirebaseMessaging.onMessageOpenedApp.listen(
        (m) => _tapRouter.open(m.messageId, m.data, _open),
      );
      FirebaseMessaging.instance.onTokenRefresh.listen(
        (_) => unawaited(sync()),
      );
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
        '[DirectPush] Not ready (${e.runtimeType}); OneSignal remains active.',
      );
      _starting = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_registration.sync(register: true, resetRetries: true));
    }
  }

  /// Call only after the existing OneSignal token mirror was successfully saved.
  Future<void> mirrorReady(String subscriptionId, bool optedIn) async {
    _oneSignalId = subscriptionId;
    _optedIn = optedIn;
    if (!_ready) await initialize();
    await _registration.sync(register: true, resetRetries: true);
    if (_ready) await flushEvents();
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
    if ((id == null) != (secret == null)) {
      throw StateError('Incomplete installation proof, sync remains pending');
    }
    if (id == null || secret == null) {
      final lifecycle = await FavoritePlayerNewsPreferenceStore().load();
      if (lifecycle.revision > 0 ||
          lifecycle.owner != null ||
          lifecycle.detachPending) {
        throw StateError('Missing installation proof, sync remains pending');
      }
      final h = _randomHex(16);
      id =
          '${h.substring(0, 8)}-${h.substring(8, 12)}-4${h.substring(13, 16)}-8${h.substring(17, 20)}-${h.substring(20)}';
      secret = _randomHex(32);
      if (!await prefs.setString('direct_push_installation', id) ||
          !await prefs.setString('direct_push_secret', secret)) {
        throw StateError('Installation proof was not saved');
      }
    }
    return {'installationId': id, 'installationSecret': secret};
  }

  Future<void> sync() async {
    if (!configured) return;
    await _registration.sync(register: true, resetRetries: true);
    if (_ready) await flushEvents();
  }

  Future<Map<String, dynamic>?> _registrationData() async {
    if (!_ready || _oneSignalId == null) return null;
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        await FirebaseMessaging.instance.getAPNSToken() == null) {
      return null;
    }
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return null;
    final package = await PackageInfo.fromPlatform();
    final timezone = await deviceTimezone();
    return {
      'token': token,
      'oneSignalSubscriptionId': _oneSignalId,
      'platform': defaultTargetPlatform == TargetPlatform.iOS
          ? 'ios'
          : 'android',
      'optedIn':
          _optedIn &&
          [
            AuthorizationStatus.authorized,
            AuthorizationStatus.provisional,
          ].contains(settings.authorizationStatus),
      'appVersion': '${package.version}+${package.buildNumber}',
      'language': WidgetsBinding.instance.platformDispatcher.locale
          .toLanguageTag(),
      if (timezone != null) 'timezone': timezone,
    };
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
    return _registration.detach();
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

  Future<void> recordOneSignalOpen(Map<String, dynamic> data) async {
    if (!configured) return;
    await storeEvent(data, 'opened');
    await flushEvents();
  }

  Future<bool> _bindingCallback(Map<String, dynamic> data) async {
    if (!await NewsBindingStore().receive(data)) return false;
    unawaited(_registration.sync(resetRetries: true));
    return true;
  }

  void _open(Map<String, dynamic> data) {
    if (data['type'] == NewsBindingStore.type) {
      unawaited(_bindingCallback(data));
      return;
    }
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
