import 'dart:async';
import 'dart:io';

import 'package:amplitude_flutter/amplitude.dart';
import 'package:amplitude_flutter/configuration.dart';
import 'package:amplitude_flutter/constants.dart' show LogLevel;
import 'package:amplitude_flutter/default_tracking.dart';
import 'package:amplitude_flutter/events/base_event.dart';
import 'package:amplitude_flutter/events/identify.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../repository/authentication/model/app_user.dart';
import 'package:chessever2/services/appsflyer_service.dart';

/// Centralized Amplitude wrapper to keep event names/metadata consistent.
class AnalyticsService {
  AnalyticsService._();

  static final AnalyticsService instance = AnalyticsService._();
  static const String fallbackApiKey = 'c19481babdae8a9f2d4c20b9bacecfb3';

  Amplitude? _client;
  Future<void>? _initFuture;
  Map<String, dynamic> _baseEventProperties = {};
  String? _userId;

  final AnalyticsRouteObserver routeObserver = AnalyticsRouteObserver();

  Future<void> initialize({required String apiKey}) {
    _initFuture ??= _initialize(apiKey);
    return _initFuture!;
  }

  bool get isReady => _client != null;

  Future<void> _initialize(String apiKey) async {
    if (apiKey.trim().isEmpty) {
      if (kDebugMode) {
        debugPrint('[Analytics] Skipping init because apiKey is empty');
      }
      return;
    }

    final config = Configuration(
      apiKey: apiKey,
      flushQueueSize: 20,
      flushIntervalMillis: 10000,
      logLevel: kDebugMode ? LogLevel.debug : LogLevel.error,
      defaultTracking: DefaultTrackingOptions.none(),
    );

    final amplitude = Amplitude(config);
    await amplitude.isBuilt;

    _client = amplitude;
    _baseEventProperties = await _buildBaseEventProperties();

    trackEventDetached(
      'App Launched',
      properties: {
        'build_mode': kDebugMode ? 'debug' : 'release',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<void> syncUser(AppUser? user) async {
    await _initFuture;
    final client = _client;
    if (client == null) return;

    _userId = user?.id;
    await client.setUserId(user?.id);

    if (user != null) {
      final identify = Identify()..set('is_anonymous', user.isAnonymous);

      if (user.email != null && user.email!.isNotEmpty) {
        identify.set('email', user.email);
      }
      if (user.displayName != null && user.displayName!.isNotEmpty) {
        identify.set('display_name', user.displayName);
      }

      identify.set('created_at', user.createdAt.toIso8601String());
      await client.identify(identify);
    }
  }

  Future<void> clearUser() async {
    await _initFuture;
    final client = _client;
    if (client == null) return;
    _userId = null;
    await client.setUserId(null);
  }

  Future<void> trackScreenView({
    required String screenName,
    String? previousScreen,
    Map<String, dynamic>? properties,
  }) {
    return trackEvent(
      'Screen Viewed',
      properties: {
        'screen_name': screenName,
        if (previousScreen != null) 'previous_screen': previousScreen,
        ...?properties,
      },
    );
  }

  Future<void> trackAuthEvent({
    required String action,
    String? method,
    bool? success,
    String? reason,
    AppUser? user,
  }) {
    return trackEvent(
      'Auth Event',
      properties: {
        'action': action,
        if (method != null) 'method': method,
        if (success != null) 'success': success,
        if (reason != null) 'reason': reason,
        'is_anonymous': user?.isAnonymous,
        if (user != null) 'user_id': user.id,
      },
    );
  }

  Future<void> setUserProperties(Map<String, dynamic> properties) async {
    await _initFuture;
    final client = _client;
    if (client == null || properties.isEmpty) return;

    final normalized = _normalizeProperties(properties);
    if (normalized.isEmpty) return;

    final identify = Identify();
    normalized.forEach(identify.set);

    await client.identify(identify);
  }

  Future<void> trackEvent(
    String eventName, {
    Map<String, dynamic>? properties,
    Map<String, dynamic>? userProperties,
  }) async {
    await _initFuture;
    final client = _client;
    if (client == null) return;

    final eventProps = _normalizeProperties({
      ..._baseEventProperties,
      if (properties != null) ...properties,
    });

    final normalizedUserProps =
        userProperties != null ? _normalizeProperties(userProperties) : null;

    final event = BaseEvent(
      eventName,
      eventProperties: eventProps.isEmpty ? null : eventProps,
      userProperties:
          normalizedUserProps != null && normalizedUserProps.isNotEmpty
              ? normalizedUserProps
              : null,
    );

    try {
      await client.track(event);

      // Also log to AppsFlyer for affiliate marketing tracking
      unawaited(AppsflyerService.instance.logEvent(eventName, eventProps));
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[Analytics] Failed to send $eventName: $e');
        debugPrintStack(stackTrace: st);
      }
    }
  }

  void trackEventDetached(
    String eventName, {
    Map<String, dynamic>? properties,
    Map<String, dynamic>? userProperties,
  }) {
    unawaited(
      trackEvent(
        eventName,
        properties: properties,
        userProperties: userProperties,
      ),
    );
  }

  Future<Map<String, dynamic>> _buildBaseEventProperties() async {
    String? appVersion;
    String? buildNumber;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      appVersion = packageInfo.version;
      buildNumber = packageInfo.buildNumber;
    } catch (_) {
      // Safe to ignore; app version is a nice-to-have
    }

    Locale? locale;
    try {
      locale = WidgetsBinding.instance.platformDispatcher.locale;
    } catch (_) {}

    final platformName = kIsWeb ? 'web' : Platform.operatingSystem;
    final osVersion = kIsWeb ? null : Platform.operatingSystemVersion;

    return _normalizeProperties({
      'app_version': appVersion,
      'build_number': buildNumber,
      'platform': platformName,
      'os_version': osVersion,
      'user_id': _userId,
    });
  }

  Map<String, dynamic> _normalizeProperties(Map<String, dynamic> properties) {
    final normalized = <String, dynamic>{};

    properties.forEach((key, value) {
      if (value == null) return;
      final normalizedKey = _toSnakeCase(key);
      final normalizedValue = _normalizeValue(value);
      if (normalizedValue != null) {
        normalized[normalizedKey] = normalizedValue;
      }
    });

    return normalized;
  }

  dynamic _normalizeValue(dynamic value) {
    if (value is DateTime) return value.toIso8601String();
    if (value is Enum) return value.name;
    if (value is Map<String, dynamic>) return _normalizeProperties(value);
    if (value is Iterable) {
      return value.map(_normalizeValue).whereType<Object>().toList();
    }
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    return value;
  }

  String _toSnakeCase(String value) {
    final withUnderscores = value
        .replaceAll(RegExp(r'[\s\-]+'), '_')
        .replaceAllMapped(
          RegExp(r'(?<=[a-z0-9])([A-Z])'),
          (match) => '_${match.group(0)}',
        );
    final collapsed = withUnderscores.replaceAll(RegExp('_+'), '_');
    final trimmed = collapsed.replaceAll(RegExp('^_+|_+\$'), '');
    return trimmed.toLowerCase();
  }
}

class AnalyticsRouteObserver extends RouteObserver<PageRoute<dynamic>> {
  String? _currentScreen;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _track(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _track(newRoute, oldRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _track(previousRoute, route);
  }

  void _track(Route<dynamic>? route, Route<dynamic>? previousRoute) {
    final screen = _routeName(route);
    if (screen == null || screen == _currentScreen) return;
    _currentScreen = screen;

    AnalyticsService.instance.trackScreenView(
      screenName: screen,
      previousScreen: _routeName(previousRoute),
    );
  }

  String? _routeName(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name != null && name.isNotEmpty) return name;
    final runtimeName = route?.runtimeType.toString();
    return runtimeName != null && runtimeName.isNotEmpty ? runtimeName : null;
  }
}
