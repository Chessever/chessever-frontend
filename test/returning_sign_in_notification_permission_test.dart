import 'dart:async';

import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/local_storage/onboarding/onboarding_repository.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/screens/authentication/auth_screen.dart';
import 'package:chessever2/screens/authentication/auth_screen_provider.dart';
import 'package:chessever2/screens/authentication/auth_screen_state.dart';
import 'package:chessever2/screens/onboarding/notification_permission_step.dart';
import 'package:chessever2/services/push_notifications_service.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/auth_state_listener.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sqflite/sqflite.dart';

final _returningUser = AppUser(
  id: 'returning-account',
  createdAt: DateTime.utc(2025),
);

class _Auth extends AuthScreenNotifier {
  _Auth(super.ref);

  @override
  Future<AppUser?> signInWithGoogle() async {
    state = AuthScreenState(user: _returningUser);
    return _returningUser;
  }
}

class _Onboarding extends OnboardingRepository {
  _Onboarding(this.completed);

  final bool completed;

  @override
  Future<bool> isCompleted(String? userId) async => completed;
}

class _Country extends StateNotifier<AsyncValue<Country>>
    implements SelectedCountryNotifier {
  _Country() : super(AsyncData(CountryService().findByCode('US')!));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Only the native platform boundary is faked. Eligibility, persistence, the
/// real auth-screen completion, and the notification step run production code.
class _Native {
  final values = <String, String>{};
  final notificationCalls = <String>[];
  bool? granted = false;
  bool canRequest = true;
  bool failPermission = false;
  bool failPromptHistory = false;
  bool failCanRequest = false;
  Completer<bool>? permissionReply;
  Completer<bool>? requestReply;

  int get requests => notificationCalls
      .where((method) => method == 'OneSignal#requestPermission')
      .length;

  void reset() {
    values.clear();
    notificationCalls.clear();
    granted = false;
    canRequest = true;
    failPermission = false;
    failPromptHistory = false;
    failCanRequest = false;
    permissionReply = null;
    requestReply = null;
  }

  Future<Object?> notifications(MethodCall call) async {
    notificationCalls.add(call.method);
    switch (call.method) {
      case 'OneSignal#permission':
        if (failPermission) throw PlatformException(code: 'unavailable');
        return permissionReply?.future ?? granted;
      case 'OneSignal#canRequest':
        if (failCanRequest) throw PlatformException(code: 'unavailable');
        return canRequest;
      case 'OneSignal#requestPermission':
        final result = await (requestReply?.future ?? Future.value(true));
        granted = result;
        return result;
      default:
        return null;
    }
  }

  Future<Object?> sqlite(MethodCall call) async {
    switch (call.method) {
      case 'getDatabasesPath':
        return '/test-notification-permission';
      case 'openDatabase':
        return <String, Object>{'id': 1};
      case 'query':
        final arguments = call.arguments as Map;
        final sql = arguments['sql'] as String;
        if (sql.contains('user_version')) {
          return <Map<String, Object>>[
            {'user_version': 1},
          ];
        }
        if (!sql.contains('key_value_store')) return <Map<String, Object>>[];
        final key = (arguments['arguments'] as List).first as String;
        if (key == 'notifications_prompted_once' && failPromptHistory) {
          throw PlatformException(code: 'unavailable');
        }
        return <Map<String, Object>>[
          if (values[key] case final value?) {'value': value},
        ];
      case 'insert':
        final arguments = (call.arguments as Map)['arguments'] as List;
        values[arguments[0] as String] = arguments[1] as String;
        return 1;
      default:
        return null;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final native = _Native();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const notificationChannel = MethodChannel('OneSignal#notifications');
  const sqliteChannel = MethodChannel('com.tekartik.sqflite');
  const otherChannels = [
    MethodChannel('OneSignal'),
    MethodChannel('OneSignal#debug'),
    MethodChannel('OneSignal#user'),
    MethodChannel('OneSignal#inappmessages'),
    MethodChannel('OneSignal#pushsubscription'),
  ];

  setUpAll(() async {
    messenger.setMockMethodCallHandler(
      notificationChannel,
      native.notifications,
    );
    messenger.setMockMethodCallHandler(sqliteChannel, native.sqlite);
    for (final channel in otherChannels) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'OneSignal#pushSubscriptionOptedIn') return false;
        return null;
      });
    }
    SqflitePlugin.registerWith();
    await AppDatabase.instance.database;
    await PushNotificationsService.instance.initialize(appId: 'test-app');
    // OneSignal.initialize also hydrates its own Dart permission cache.
    await Future<void>.delayed(Duration.zero);
  });

  setUp(native.reset);

  tearDownAll(() {
    messenger.setMockMethodCallHandler(notificationChannel, null);
    messenger.setMockMethodCallHandler(sqliteChannel, null);
    for (final channel in otherChannels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  Future<GlobalKey<NavigatorState>> signIn(
    WidgetTester tester, {
    bool completedOnboarding = true,
  }) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authScreenProvider.overrideWith(_Auth.new),
          countryDropdownProvider.overrideWith((ref) => _Country()),
          onboardingRepositoryProvider.overrideWithValue(
            _Onboarding(completedOnboarding),
          ),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: AppTheme.darkTheme,
          initialRoute: '/auth_screen',
          builder: (context, child) {
            ResponsiveHelper.init(context);
            return child!;
          },
          routes: {
            '/auth_screen': (_) => const AuthScreen(),
            '/home_screen': (_) => const Scaffold(body: Text('Home')),
            '/onboarding': (_) => const Scaffold(body: Text('Onboarding')),
          },
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Continue with Google'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    return navigatorKey;
  }

  testWidgets('returning sign-in asks only after Continue over home', (
    tester,
  ) async {
    await signIn(tester);

    expect(find.text('Home', skipOffstage: false), findsOneWidget);
    expect(find.byType(NotificationPermissionStep), findsOneWidget);
    expect(native.requests, 0);
    expect(native.values['notifications_prompted_once'], isNull);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(native.requests, 1);
    expect(native.values['notifications_prompted_once'], '1');
    expect(find.byType(NotificationPermissionStep), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });

  for (final permission in [
    (asked: false, granted: false, canRequest: false, offer: false),
    (asked: false, granted: false, canRequest: true, offer: true),
    (asked: false, granted: true, canRequest: false, offer: false),
    (asked: false, granted: true, canRequest: true, offer: false),
    (asked: true, granted: false, canRequest: false, offer: false),
    (asked: true, granted: false, canRequest: true, offer: false),
    (asked: true, granted: true, canRequest: false, offer: false),
    (asked: true, granted: true, canRequest: true, offer: false),
  ]) {
    test(
      'eligibility: asked=${permission.asked}, granted=${permission.granted}, '
      'OS can ask=${permission.canRequest}',
      () async {
        native.values['notifications_prompted_once'] = permission.asked
            ? '1'
            : '0';
        native.granted = permission.granted;
        native.canRequest = permission.canRequest;
        final before = Map<String, String>.of(native.values);

        expect(
          await PushNotificationsService.instance.shouldOfferPermissionPrompt(),
          permission.offer,
        );
        expect(native.values, before, reason: 'Eligibility only reads state.');
        expect(native.requests, 0);
      },
    );
  }

  for (final failure in ['history', 'permission', 'missing permission', 'OS']) {
    test('unreadable $failure skips the permission offer', () async {
      switch (failure) {
        case 'history':
          native.failPromptHistory = true;
        case 'permission':
          native.failPermission = true;
        case 'missing permission':
          native.granted = null;
        case 'OS':
          native.failCanRequest = true;
      }

      expect(
        await PushNotificationsService.instance.shouldOfferPermissionPrompt(),
        isFalse,
      );
      expect(native.requests, 0);
      expect(native.values, isEmpty);
    });
  }

  for (final skipReason in [
    'already asked',
    'already granted',
    'permanently denied',
    'unreadable',
  ]) {
    testWidgets('returning sign-in stays home when $skipReason', (
      tester,
    ) async {
      switch (skipReason) {
        case 'already asked':
          native.values['notifications_prompted_once'] = '1';
        case 'already granted':
          native.granted = true;
        case 'permanently denied':
          native.canRequest = false;
        case 'unreadable':
          native.failPermission = true;
      }

      await signIn(tester);

      expect(find.text('Home'), findsOneWidget);
      expect(find.byType(NotificationPermissionStep), findsNothing);
      expect(native.requests, 0);
    });
  }

  testWidgets('new account goes to onboarding without the returning offer', (
    tester,
  ) async {
    await signIn(tester, completedOnboarding: false);

    expect(find.text('Onboarding'), findsOneWidget);
    expect(find.byType(NotificationPermissionStep), findsNothing);
    expect(native.notificationCalls, isEmpty);
  });

  testWidgets('duplicate checks cannot stack permission pages', (tester) async {
    native.permissionReply = Completer<bool>();
    final navigatorKey = await signIn(tester);

    expect(find.text('Home'), findsOneWidget);
    expect(find.byType(NotificationPermissionStep), findsNothing);
    await offerNotificationsAfterSignIn(navigatorKey.currentState!);
    native.permissionReply!.complete(false);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationPermissionStep), findsOneWidget);
    expect(
      native.notificationCalls.where((call) => call == 'OneSignal#permission'),
      hasLength(1),
    );
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('leaving home while permission is read cancels the offer', (
    tester,
  ) async {
    native.permissionReply = Completer<bool>();
    final navigatorKey = await signIn(tester);
    navigatorKey.currentState!.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Another screen')),
      ),
    );
    native.permissionReply!.complete(false);
    await tester.pumpAndSettle();

    expect(find.text('Another screen'), findsOneWidget);
    expect(find.byType(NotificationPermissionStep), findsNothing);
    expect(native.requests, 0);
  });

  testWidgets('failed Continue permission read safely returns home', (
    tester,
  ) async {
    await signIn(tester);
    expect(find.byType(NotificationPermissionStep), findsOneWidget);
    native.failPermission = true;

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.byType(NotificationPermissionStep), findsNothing);
    expect(native.requests, 0);
    expect(native.values['notifications_prompted_once'], isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Continue does not dismiss a newer route during a native prompt',
    (tester) async {
      final navigatorKey = await signIn(tester);
      native.requestReply = Completer<bool>();
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(native.requests, 1);
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Another screen')),
        ),
      );
      native.requestReply!.complete(true);
      await tester.pumpAndSettle();

      expect(find.text('Another screen'), findsOneWidget);
      // Dismiss the newer page and the explanation to complete the outstanding
      // route future before the next test exercises the shared in-flight guard.
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
    },
  );
}
