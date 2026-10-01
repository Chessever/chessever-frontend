import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_environment.dart';
import 'deep_link_service.dart';
import 'direct_push_tap_router.dart';

/// Receipts are persisted locally and flushed after Supabase is ready.
/// A background callback is evidence of receipt; absence of one is not a failure.
@pragma('vm:entry-point')
Future<void> directPushBackgroundHandler(RemoteMessage message) async {
  if (message.data['delivery_id'] is! String) return;
  await DirectPushService.storeEvent(message.data, 'received');
}

class DirectPushService with WidgetsBindingObserver {
  DirectPushService._();
  static final instance = DirectPushService._();
  static const _enabled = bool.fromEnvironment('CHESSEVER_DIRECT_PUSH_ENABLED', defaultValue: true);
  static const _productionUrl = String.fromEnvironment('CHESSEVER_NOTIFICATION_URL',
      defaultValue: 'https://chessever-notifications.young-sun-69a8.workers.dev');
  static const _testUrl = String.fromEnvironment('CHESSEVER_TEST_NOTIFICATION_URL');
  static String get _url => AppEnvironment.isTest ? _testUrl : _productionUrl;
  final _local = FlutterLocalNotificationsPlugin();
  final _tapRouter = DirectPushTapRouter();
  bool _ready = false;
  bool _syncing = false;
  bool _syncAgain = false;
  String? _oneSignalId;
  bool _optedIn = false;
  String? _owner;
  Future<void>? _starting;
  Timer? _registrationRetry;
  int _registrationAttempts = 0;

  static bool get configured => _enabled && Uri.tryParse(_url)?.scheme == 'https' &&
      (!AppEnvironment.isTest || _url != _productionUrl);

  Future<void> initialize() => _starting ??= _initialize();
  Future<void> _initialize() async {
    if (!configured || kIsWeb || ![TargetPlatform.iOS, TargetPlatform.android].contains(defaultTargetPlatform)) return;
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _tapRouter.initializeNative(_open);
      }
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(directPushBackgroundHandler);
      await _local.initialize(
        const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false)),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null) _open(Map<String, dynamic>.from(jsonDecode(payload) as Map));
        },
      );
      await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel('chessever_direct', 'ChessEver alerts',
              description: 'ChessEver notifications', importance: Importance.high));
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);
      FirebaseMessaging.onMessage.listen((message) {
        // Inline tester pushes intentionally have no persisted delivery ID.
        if (message.data['delivery_id'] is String) {
          unawaited(storeEvent(message.data, 'received').then((_) => flushEvents()));
        }
        if (defaultTargetPlatform == TargetPlatform.android && message.notification != null) {
          final notificationId = message.messageId ?? message.data['delivery_id'] as String? ??
              DateTime.now().microsecondsSinceEpoch.toString();
          unawaited(_local.show(notificationId.hashCode & 0x7fffffff,
            message.notification!.title, message.notification!.body,
            const NotificationDetails(android: AndroidNotificationDetails('chessever_direct','ChessEver alerts',
              importance: Importance.high, priority: Priority.high)), payload: jsonEncode(message.data)));
        }
      });
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _tapRouter.open(m.messageId, m.data, _open));
      FirebaseMessaging.instance.onTokenRefresh.listen((_) => unawaited(sync()));
      Supabase.instance.client.auth.onAuthStateChange.listen((state) {
        final next = state.session?.user.id;
        if (_owner != null && next != _owner) {
          unawaited(detach().then((_) => sync()));
        } else {
          unawaited(sync());
        }
      });
      _owner = (await SharedPreferences.getInstance()).getString('direct_push_owner');
      WidgetsBinding.instance.addObserver(this);
      _ready = true;
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _tapRouter.open(initial.messageId, initial.data, _open);
      final localLaunch = await _local.getNotificationAppLaunchDetails();
      final payload = localLaunch?.notificationResponse?.payload;
      if (localLaunch?.didNotificationLaunchApp == true && payload != null) _open(Map<String,dynamic>.from(jsonDecode(payload) as Map));
      await sync();
    } catch (e) {
      debugPrint('[DirectPush] Not ready (${e.runtimeType}); OneSignal remains active.');
      _starting = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _registrationAttempts = 0;
      unawaited(sync());
    }
  }

  /// Call only after the existing OneSignal token mirror was successfully saved.
  Future<void> mirrorReady(String subscriptionId, bool optedIn) async {
    _oneSignalId = subscriptionId;
    _optedIn = optedIn;
    if (!_ready) await initialize();
    await sync();
  }

  static String _randomHex(int bytes) {
    final random = Random.secure();
    return List.generate(bytes, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
  Future<Map<String,String>> _proof() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('direct_push_installation');
    var secret = prefs.getString('direct_push_secret');
    if (id == null || secret == null) {
      final h = _randomHex(16);
      id = '${h.substring(0,8)}-${h.substring(8,12)}-4${h.substring(13,16)}-8${h.substring(17,20)}-${h.substring(20)}';
      secret = _randomHex(32);
      await prefs.setString('direct_push_installation',id);
      await prefs.setString('direct_push_secret',secret);
    }
    return {'installationId':id,'installationSecret':secret};
  }

  void _retryRegistration() {
    if (_registrationAttempts >= 5) return;
    _registrationAttempts++;
    _registrationRetry?.cancel();
    _registrationRetry = Timer(const Duration(seconds: 5), () => unawaited(sync()));
  }

  Future<void> sync() async {
    if (!_ready) return;
    if (_syncing) { _syncAgain = true; return; }
    _syncing = true;
    try {
      final session = Supabase.instance.client.auth.currentSession;
      final prefs = await SharedPreferences.getInstance();
      if ((_owner != null && _owner != session?.user.id) || prefs.getBool('direct_push_detach_pending') == true) {
        if (!await detach()) return;
      }
      if (session == null || _oneSignalId == null) return;
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      if (defaultTargetPlatform == TargetPlatform.iOS &&
          await FirebaseMessaging.instance.getAPNSToken() == null) {
        debugPrint('[DirectPush] Waiting for APNs token; registration retry scheduled.');
        _retryRegistration();
        return;
      }
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        _retryRegistration();
        return;
      }
      final package = await PackageInfo.fromPlatform();
      final response = await http.post(Uri.parse('$_url/v1/devices'),headers:{
        'authorization':'Bearer ${session.accessToken}','content-type':'application/json'},body:jsonEncode({
          ...await _proof(), 'token':token, 'oneSignalSubscriptionId':_oneSignalId,
          'platform':defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
          'optedIn':_optedIn && [AuthorizationStatus.authorized,AuthorizationStatus.provisional].contains(settings.authorizationStatus),
          'appVersion':'${package.version}+${package.buildNumber}',
          'language':WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag(),
        })).timeout(const Duration(seconds:15));
      if (response.statusCode >= 300) {
        debugPrint('[DirectPush] Registration rejected (HTTP ${response.statusCode}).');
        throw StateError('Registration rejected');
      }
      _registrationRetry?.cancel();
      _registrationAttempts = 0;
      debugPrint('[DirectPush] Installation registered (${package.version}+${package.buildNumber}).');
      _owner = session.user.id;
      await prefs.setString('direct_push_owner', _owner!);
      if (Supabase.instance.client.auth.currentUser?.id != _owner) {
        await detach();
        return;
      }
      await flushEvents();
    } catch (e) {
      debugPrint('[DirectPush] Sync deferred (${e.runtimeType}); retry scheduled.');
      _retryRegistration();
    }
    finally { _syncing = false; if (_syncAgain) { _syncAgain=false; unawaited(sync()); } }
  }

  Future<bool> detach() async {
    if (!configured) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('direct_push_detach_pending', true);
    try {
      final response = await http.post(Uri.parse('$_url/v1/devices/logout'),headers:{'content-type':'application/json'},
        body:jsonEncode(await _proof())).timeout(const Duration(seconds:10));
      if (response.statusCode != 200) return false;
      _owner = null;
      await prefs.remove('direct_push_owner');
      await prefs.remove('direct_push_detach_pending');
      return true;
    } catch (e) { debugPrint('[DirectPush] Detach deferred (${e.runtimeType})'); return false; }
  }

  static Future<void> storeEvent(Map<String,dynamic> data,String event) async {
    final id = data['delivery_id']; if (id is! String) return;
    final prefs = SharedPreferencesAsync();
    // One key per event avoids losing receipts to foreground/background list races.
    await prefs.setString('direct_push_event_${id}_$event', jsonEncode({'deliveryId':id,'event':event}));
  }
  Future<void> recordOneSignalOpen(Map<String,dynamic> data) async {
    if (!configured) return;
    await storeEvent(data,'opened'); await flushEvents();
  }
  void _open(Map<String,dynamic> data) {
    if (data['delivery_id'] is String) {
      unawaited(storeEvent(data,'opened').then((_) => flushEvents()));
    }
    DeepLinkService.instance.ingestNotificationData(data);
  }
  Future<void> flushEvents() async {
    if (!configured) return;
    final session = Supabase.instance.client.auth.currentSession;if (session == null) return;
    final prefs = SharedPreferencesAsync();
    final keys = await prefs.getKeys();
    for (final key in keys.where((k)=>k.startsWith('direct_push_event_')).take(100)) {
      try {
        final payload=await prefs.getString(key);if(payload==null)continue;
        final response=await http.post(Uri.parse('$_url/v1/events'),headers:{'authorization':'Bearer ${session.accessToken}',
          'content-type':'application/json'},body:payload).timeout(const Duration(seconds:10));
        if(response.statusCode==200) await prefs.remove(key);
      } catch (_) { break; }
    }
  }
}
