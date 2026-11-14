import 'dart:async';

import 'package:chessever2/services/forced_update_policy.dart';
import 'package:chessever2/services/phone_store_upgrader.dart';
import 'package:chessever2/services/phone_update_reminder.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/custom_upgrade_alert.dart';
import 'package:chessever2/widgets/phone_update_route_observer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upgrader/upgrader.dart';

class _FakeUpgrader extends PhoneStoreUpgrader {
  _FakeUpgrader() : super(messages: CustomUpgraderMessages()) {
    updateState(
      state.copyWith(
        packageInfo: PackageInfo(
          appName: 'ChessEver',
          packageName: 'test.phone',
          version: '35.25.3',
          buildNumber: '3504',
        ),
      ),
    );
  }

  int checks = 0;
  int storeLaunches = 0;
  int disposals = 0;
  String? offered = '35.25.4';
  bool critical = false;
  bool minimum = false;
  bool fail = false;
  bool ignored = false;
  Completer<void>? pending;

  @override
  Future<bool> initialize() async {
    await updateVersionInfo();
    WidgetsBinding.instance.addObserver(this);
    return true;
  }

  @override
  Future<UpgraderVersionInfo?> updateVersionInfo() async {
    checks++;
    if (pending != null) await pending!.future;
    if (fail) {
      updateState(state.copyWithNull(versionInfo: true));
      throw StateError('test failed check');
    }
    final info = UpgraderVersionInfo(
      appStoreVersion: Upgrader.parseVersion(offered, 'test', false),
      minAppVersion: minimum
          ? Upgrader.parseVersion('35.25.4', 'test', false)
          : null,
      isCriticalUpdate: critical,
      releaseNotes: 'Release notes retained',
    );
    updateState(state.copyWith(versionInfo: info));
    return info;
  }

  @override
  String body(UpgraderMessages messages) => messages.body;

  @override
  bool alreadyIgnoredThisVersion() => ignored;

  @override
  Future<void> sendUserToAppStore() async => storeLaunches++;

  @override
  void dispose() {
    disposals++;
    super.dispose();
  }
}

class _FakePolicySource implements ForcedUpdatePolicySource {
  ForcedUpdatePolicy policy = ForcedUpdatePolicy.fallback;
  final _changes = StreamController<void>.broadcast();
  int loads = 0;

  @override
  Future<ForcedUpdatePolicy> load() async {
    loads++;
    return policy;
  }

  @override
  Stream<void> get changes => _changes.stream;

  /// Publishes [next] the way a Remote Config real-time update would.
  void publish(ForcedUpdatePolicy next) {
    policy = next;
    _changes.add(null);
  }
}

void main() {
  late SharedPreferences prefs;
  late DateTime now;
  late PhoneUpdateReminder reminder;
  late _FakeUpgrader updater;
  late PhoneUpdateRouteObserver observer;
  late GlobalKey<NavigatorState> navigator;
  late GlobalKey<CustomUpgradeAlertState> alert;
  late _FakePolicySource policy;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    now = DateTime.utc(2026, 9, 30);
    reminder = PhoneUpdateReminder(
      now: () => now,
      preferences: () async => prefs,
    );
    updater = _FakeUpgrader();
    observer = PhoneUpdateRouteObserver();
    navigator = GlobalKey<NavigatorState>();
    alert = GlobalKey<CustomUpgradeAlertState>();
    policy = _FakePolicySource();
  });

  Future<void> pumpShell(
    WidgetTester tester, {
    String initial = '/home_screen',
    bool enabled = true,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [observer],
        theme: AppTheme.darkTheme,
        initialRoute: initial,
        routes: {
          '/': (_) => const Scaffold(body: Text('Splash')),
          '/home_screen': (_) => const Scaffold(body: Text('Home')),
          '/board': (_) => const Scaffold(body: Text('Game board')),
          '/calendar_screen': (_) => const Scaffold(body: Text('Calendar')),
        },
        builder: (context, child) {
          ResponsiveHelper.init(context);
          return CustomUpgradeAlert(
            key: alert,
            upgrader: updater,
            navigatorKey: navigator,
            routeObserver: observer,
            reminder: reminder,
            enabled: enabled,
            policySource: policy,
            child: child!,
          );
        },
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> resume(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'launch shows exact label once; no rebuild or resume duplicates',
    (tester) async {
      await pumpShell(tester);
      expect(find.text('Remind me in 3 days'), findsOneWidget);
      expect(find.text('Release notes retained'), findsOneWidget);
      expect(updater.checks, 1);
      await resume(tester);
      alert.currentState!.checkForUpdate();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(updater.checks, 1);
      await tester.tap(find.text('Remind me in 3 days'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(prefs.containsKey(PhoneUpdateReminder.preferencesKey), isTrue);
    },
  );

  testWidgets('resume before, exactly at and after 72h honors click deadline', (
    tester,
  ) async {
    await pumpShell(tester);
    await tester.tap(find.text('Remind me in 3 days'));
    await tester.pumpAndSettle();
    now = now.add(const Duration(hours: 72) - const Duration(microseconds: 1));
    await resume(tester);
    expect(find.byType(AlertDialog), findsNothing);
    now = now.add(const Duration(microseconds: 1));
    await resume(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    // Dismissing (outside tap, back) counts as "later", as Upgrader's own
    // alert-again window did: it must not return on every resume.
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    now = now.add(const Duration(hours: 1));
    await resume(tester);
    expect(find.byType(AlertDialog), findsNothing);
    now = now.add(const Duration(hours: 72));
    await resume(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('cold restart reads the same persisted snooze', (tester) async {
    await reminder.snooze('35.25.4');
    await pumpShell(tester);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    updater = _FakeUpgrader();
    observer = PhoneUpdateRouteObserver();
    navigator = GlobalKey<NavigatorState>();
    alert = GlobalKey<CustomUpgradeAlertState>();
    reminder = PhoneUpdateReminder(
      now: () => now,
      preferences: () async => prefs,
    );
    now = now.add(const Duration(hours: 72));
    await pumpShell(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('board cold launch defers until a safe route', (tester) async {
    await pumpShell(tester, initial: '/board');
    expect(find.byType(AlertDialog), findsNothing);
    expect(updater.checks, 0);
    navigator.currentState!.pushReplacementNamed('/home_screen');
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(updater.checks, 1);
  });

  testWidgets('due resume on game waits for pop to home', (tester) async {
    await reminder.snooze('35.25.4');
    await pumpShell(tester);
    navigator.currentState!.pushNamed('/board');
    await tester.pumpAndSettle();
    now = now.add(const Duration(hours: 72));
    await resume(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(updater.checks, 1);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets(
    'anonymous board and modal both defer; sheet close retries safely',
    (tester) async {
      await reminder.snooze('35.25.4');
      await pumpShell(tester);
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Unnamed board')),
        ),
      );
      await tester.pumpAndSettle();
      now = now.add(const Duration(hours: 72));
      await resume(tester);
      expect(find.byType(AlertDialog), findsNothing);
      navigator.currentState!.pop();
      unawaited(
        showModalBottomSheet<void>(
          context: navigator.currentContext!,
          builder: (_) => const Text('Open sheet'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    },
  );

  testWidgets('navigation during an in-flight check cannot interrupt a game', (
    tester,
  ) async {
    updater.pending = Completer<void>();
    await pumpShell(tester);
    navigator.currentState!.pushNamed('/board');
    await tester.pumpAndSettle();
    updater.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets(
    'background during in-flight check invalidates display; resume retries',
    (tester) async {
      updater.pending = Completer<void>();
      await pumpShell(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      updater.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      await resume(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
    },
  );

  testWidgets('failed check is quiet and retry succeeds on next resume', (
    tester,
  ) async {
    updater.fail = true;
    await pumpShell(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(updater.checks, 1);
    updater.fail = false;
    await resume(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(updater.checks, 2);
  });

  testWidgets('newer optional release still waits for full 72h', (
    tester,
  ) async {
    await reminder.snooze('35.25.4');
    updater.offered = '35.26.0';
    await pumpShell(tester);
    expect(find.byType(AlertDialog), findsNothing);
    now = now.add(const Duration(hours: 72));
    await resume(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Remind me in 3 days'));
    await tester.pumpAndSettle();
    expect(
      prefs.getString(PhoneUpdateReminder.preferencesKey),
      contains('35.26.0'),
    );
  });

  testWidgets('store launch keeps snooze until installation is proven', (
    tester,
  ) async {
    await reminder.snooze('35.25.4');
    await pumpShell(tester);
    alert.currentState!.checkForUpdate(manual: true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update Now'));
    await tester.pumpAndSettle();
    expect(updater.storeLaunches, 1);
    expect(prefs.containsKey(PhoneUpdateReminder.preferencesKey), isTrue);
    updater.updateState(
      updater.state.copyWith(
        packageInfo: PackageInfo(
          appName: 'ChessEver',
          packageName: 'test.phone',
          version: '35.25.4',
          buildNumber: '3505',
        ),
      ),
    );
    await resume(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(prefs.containsKey(PhoneUpdateReminder.preferencesKey), isFalse);
  });

  for (final minimum in [false, true]) {
    testWidgets(
      '${minimum ? 'minimum' : 'critical'} mandatory update bypasses snooze and cannot be dismissed',
      (tester) async {
        await reminder.snooze('35.25.4');
        updater.critical = !minimum;
        updater.minimum = minimum;
        await pumpShell(tester);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Remind me in 3 days'), findsNothing);
        await navigator.currentState!.maybePop();
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.text('Update Now'));
        await tester.pumpAndSettle();
        expect(updater.storeLaunches, 1);
        expect(find.byType(AlertDialog), findsOneWidget);
      },
    );
  }

  testWidgets(
    'manual check bypasses snooze and ignored version without duplicates',
    (tester) async {
      await reminder.snooze('35.25.4');
      updater.ignored = true;
      await pumpShell(tester);
      for (var i = 0; i < 5; i++) {
        alert.currentState!.checkForUpdate(manual: true);
      }
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(updater.checks, 2);
    },
  );

  testWidgets('failed preference save leaves dialog open with retry', (
    tester,
  ) async {
    var unavailable = false;
    reminder = PhoneUpdateReminder(
      now: () => now,
      preferences: () async => unavailable ? null : prefs,
    );
    await pumpShell(tester);
    unavailable = true;
    await tester.tap(find.text('Remind me in 3 days'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not save reminder. Please try again.'),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsOneWidget);
    unavailable = false;
    await tester.tap(find.text('Remind me in 3 days'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    'dispose during async initialization never opens a dialog or leaks observer',
    (tester) async {
      updater.pending = Completer<void>();
      await pumpShell(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      updater.pending!.complete();
      await tester.pumpAndSettle();
      expect(updater.disposals, 2);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('concurrent manual/resume requests share an in-flight check', (
    tester,
  ) async {
    updater.pending = Completer<void>();
    await pumpShell(tester);
    for (var i = 0; i < 5; i++) {
      alert.currentState!.checkForUpdate(manual: true);
    }
    await tester.pumpAndSettle();
    expect(updater.checks, 1);
    updater.pending!.complete();
    await tester.pumpAndSettle();
    expect(updater.checks, 1);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('pending snooze cannot pop a newly deep-linked game', (
    tester,
  ) async {
    final pendingSave = Completer<SharedPreferences?>();
    var delaySave = false;
    reminder = PhoneUpdateReminder(
      now: () => now,
      preferences: () => delaySave ? pendingSave.future : Future.value(prefs),
    );
    await pumpShell(tester);
    delaySave = true;
    await tester.tap(find.text('Remind me in 3 days'));
    await tester.pump();
    navigator.currentState!.pushNamed('/board');
    await tester.pumpAndSettle();
    pendingSave.complete(prefs);
    await tester.pumpAndSettle();
    expect(find.text('Game board'), findsOneWidget);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'splash waits for startup routing instead of interrupting launch',
    (tester) async {
      await pumpShell(tester, initial: '/');
      expect(updater.checks, 0);
      navigator.currentState!.pushReplacementNamed('/home_screen');
      await tester.pumpAndSettle();
      expect(updater.checks, 1);
      expect(find.byType(AlertDialog), findsOneWidget);
    },
  );

  testWidgets('disabled/non-phone host performs no checks', (tester) async {
    await pumpShell(tester, enabled: false);
    await resume(tester);
    expect(updater.checks, 0);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('removing/replacing a covered route cannot mark game safe', (
    tester,
  ) async {
    await reminder.snooze('35.25.4');
    await pumpShell(tester);
    final middle = MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/calendar_screen'),
      builder: (_) => const Scaffold(),
    );
    navigator.currentState!.push(middle);
    await tester.pumpAndSettle();
    navigator.currentState!.pushNamed('/board');
    await tester.pumpAndSettle();
    navigator.currentState!.removeRoute(middle);
    await tester.pumpAndSettle();
    expect(observer.isSafe, isFalse);
    now = now.add(const Duration(hours: 72));
    await resume(tester);
    expect(find.byType(AlertDialog), findsNothing);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  group('remote forced update', () {
    Future<void> expectLocked(WidgetTester tester) async {
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text(CustomUpgraderMessages.requiredTitle), findsOneWidget);
      expect(find.text('Remind me in 3 days'), findsNothing);
      await navigator.currentState!.maybePop();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    }

    testWidgets('a new major version is mandatory and ignores the snooze', (
      tester,
    ) async {
      await reminder.snooze('36.0.0');
      updater.offered = '36.0.0';
      await pumpShell(tester);
      await expectLocked(tester);
      await tester.tap(find.text('Update Now'));
      await tester.pumpAndSettle();
      expect(updater.storeLaunches, 1);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('outside tap cannot dismiss a mandatory dialog', (
      tester,
    ) async {
      updater.offered = '36.0.0';
      await pumpShell(tester);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      await expectLocked(tester);
    });

    testWidgets('major rule switched off remotely keeps the offer optional', (
      tester,
    ) async {
      policy.policy = const ForcedUpdatePolicy(forceOnMajor: false);
      await reminder.snooze('36.0.0');
      updater.offered = '36.0.0';
      await pumpShell(tester);
      expect(find.byType(AlertDialog), findsNothing);
      now = now.add(const Duration(hours: 72));
      await resume(tester);
      expect(find.text('Remind me in 3 days'), findsOneWidget);
      expect(find.text(CustomUpgraderMessages.requiredTitle), findsNothing);
    });

    testWidgets('remote minimum forces a patch release', (tester) async {
      policy.policy = const ForcedUpdatePolicy(minimumVersion: '35.25.4');
      await reminder.snooze('35.25.4');
      await pumpShell(tester);
      await expectLocked(tester);
    });

    testWidgets('minimum ahead of the store never locks the app', (
      tester,
    ) async {
      policy.policy = const ForcedUpdatePolicy(minimumVersion: '40.0.0');
      updater.offered = '35.25.3';
      await pumpShell(tester);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('a live minimum reaches someone already in the app', (
      tester,
    ) async {
      await reminder.snooze('35.25.4');
      await pumpShell(tester);
      expect(find.byType(AlertDialog), findsNothing);
      policy.publish(const ForcedUpdatePolicy(minimumVersion: '35.25.4'));
      await tester.pumpAndSettle();
      await expectLocked(tester);
    });

    testWidgets('a live minimum locks an optional dialog that is open', (
      tester,
    ) async {
      await pumpShell(tester);
      expect(find.text('Remind me in 3 days'), findsOneWidget);
      policy.publish(const ForcedUpdatePolicy(minimumVersion: '35.25.4'));
      await tester.pumpAndSettle();
      await expectLocked(tester);
    });

    testWidgets('switching the rule off releases an open dialog on resume', (
      tester,
    ) async {
      updater.offered = '36.0.0';
      await pumpShell(tester);
      await expectLocked(tester);
      policy.policy = const ForcedUpdatePolicy(forceOnMajor: false);
      await resume(tester);
      expect(find.text('Remind me in 3 days'), findsOneWidget);
      expect(find.text(CustomUpgraderMessages.requiredTitle), findsNothing);
      await tester.tap(find.text('Remind me in 3 days'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        prefs.getString(PhoneUpdateReminder.preferencesKey),
        contains('36.0.0'),
      );
    });

    testWidgets('released by a live update, back dismisses with a snooze', (
      tester,
    ) async {
      updater.offered = '36.0.0';
      await pumpShell(tester);
      await expectLocked(tester);
      policy.publish(const ForcedUpdatePolicy(forceOnMajor: false));
      await tester.pumpAndSettle();
      await navigator.currentState!.maybePop();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(prefs.containsKey(PhoneUpdateReminder.preferencesKey), isTrue);
    });

    testWidgets('a failing policy source falls back to the major rule', (
      tester,
    ) async {
      final failing = _ThrowingPolicySource();
      updater.offered = '36.0.0';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: [observer],
          theme: AppTheme.darkTheme,
          initialRoute: '/home_screen',
          routes: {'/home_screen': (_) => const Scaffold(body: Text('Home'))},
          builder: (context, child) {
            ResponsiveHelper.init(context);
            return CustomUpgradeAlert(
              upgrader: updater,
              navigatorKey: navigator,
              routeObserver: observer,
              reminder: reminder,
              enabled: true,
              policySource: failing,
              child: child!,
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(failing.loads, 1);
      await expectLocked(tester);
    });

    testWidgets('stack-clearing navigation cannot remove a mandatory dialog', (
      tester,
    ) async {
      updater.offered = '36.0.0';
      await pumpShell(tester);
      await expectLocked(tester);
      // A push deep link or sign-out resets the stack under the dialog.
      navigator.currentState!.pushNamedAndRemoveUntil(
        '/home_screen',
        (_) => false,
      );
      await tester.pumpAndSettle();
      await expectLocked(tester);
      expect(updater.checks, 1);
    });

    testWidgets('a mandatory dialog removed onto a game returns at home', (
      tester,
    ) async {
      updater.offered = '36.0.0';
      await pumpShell(tester);
      await expectLocked(tester);
      navigator.currentState!.pushNamedAndRemoveUntil('/board', (_) => false);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      navigator.currentState!.pushReplacementNamed('/home_screen');
      await tester.pumpAndSettle();
      await expectLocked(tester);
    });

    testWidgets('a minimum published during a store check still locks', (
      tester,
    ) async {
      await reminder.snooze('35.25.4');
      updater.pending = Completer<void>();
      await pumpShell(tester);
      expect(policy.loads, 1);
      policy.publish(const ForcedUpdatePolicy(minimumVersion: '35.25.4'));
      await tester.pumpAndSettle();
      updater.pending!.complete();
      await tester.pumpAndSettle();
      await expectLocked(tester);
      expect(updater.checks, 1);
    });

    testWidgets('a release published during a store check is honoured', (
      tester,
    ) async {
      updater.offered = '36.0.0';
      updater.pending = Completer<void>();
      await pumpShell(tester);
      policy.publish(const ForcedUpdatePolicy(forceOnMajor: false));
      await tester.pumpAndSettle();
      updater.pending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Remind me in 3 days'), findsOneWidget);
      expect(find.text(CustomUpgraderMessages.requiredTitle), findsNothing);
    });

    testWidgets('disabled host never subscribes to policy updates', (
      tester,
    ) async {
      await pumpShell(tester, enabled: false);
      policy.publish(const ForcedUpdatePolicy(minimumVersion: '99.0.0'));
      await tester.pumpAndSettle();
      expect(updater.checks, 0);
      expect(policy.loads, 0);
    });
  });
}

class _ThrowingPolicySource implements ForcedUpdatePolicySource {
  int loads = 0;

  @override
  Future<ForcedUpdatePolicy> load() async {
    loads++;
    throw StateError('Remote Config down');
  }

  @override
  Stream<void> get changes => Stream<void>.error(StateError('no realtime'));
}
