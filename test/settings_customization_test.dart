import 'dart:async';
import 'dart:io';

import 'package:chessever2/providers/auto_pin_preferences_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/providers/notification_permission_provider.dart';
import 'package:chessever2/providers/notification_preferences_provider.dart';
import 'package:chessever2/repository/local_storage/auto_pin_preferences/auto_pin_preferences_repository.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/for_you/providers/for_you_tab_provider.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/settings/settings_page.dart';
import 'package:chessever2/screens/settings/widgets/board_settings_body.dart';
import 'package:chessever2/screens/settings/widgets/start_screen_settings_body.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/theme/theme_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _Board extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

class _Engine extends EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async => const EngineSettings();
}

class _Notifications extends NotificationPreferencesNotifier {
  @override
  Future<NotificationPreferences> build() async =>
      NotificationPreferences.defaults;
}

class _Permission extends StateNotifier<AsyncValue<bool>>
    implements NotificationPermissionNotifier {
  _Permission() : super(const AsyncData(false));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription() : super(SubscriptionState(isSubscribed: true));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _AutoPin extends AutoPinPreferencesNotifier {
  final calls = <String>[];
  Completer<void>? pending;

  @override
  Future<AutoPinPreferences> build() async => AutoPinPreferences.defaults;

  @override
  Future<void> setFavoritePlayersAutoPin(bool enabled) async {
    calls.add('favorite:$enabled');
    state = AsyncData(
      state.requireValue.copyWith(favoritePlayersAutoPinEnabled: enabled),
    );
    await pending?.future;
  }

  @override
  Future<void> setCountrymenAutoPin(bool enabled) async {
    calls.add('countrymen:$enabled');
    state = AsyncData(
      state.requireValue.copyWith(countrymenAutoPinEnabled: enabled),
    );
  }
}

Future<ProviderContainer> _pumpSettings(
  WidgetTester tester, {
  SettingsSection? initiallyExpanded,
  bool light = false,
  _AutoPin? autoPin,
  bool viaRoute = false,
}) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      boardSettingsProviderNew.overrideWith(_Board.new),
      engineSettingsProviderNew.overrideWith(_Engine.new),
      notificationPreferencesProvider.overrideWith(_Notifications.new),
      notificationPermissionProvider.overrideWith((_) => _Permission()),
      subscriptionProvider.overrideWith((_) => _Subscription()),
      autoPinPreferencesProvider.overrideWith(() => autoPin ?? _AutoPin()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            if (!viaRoute) {
              return SettingsPage(initiallyExpanded: initiallyExpanded);
            }
            return Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  SettingsPage.route(initiallyExpanded: initiallyExpanded),
                ),
                child: const Text('Open settings'),
              ),
            );
          },
        ),
      ),
    ),
  );
  if (viaRoute) {
    await tester.tap(find.text('Open settings'));
  }
  await tester.pumpAndSettle();
  return container;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Finder _switchIn(Type body, int index) => find
    .descendant(of: find.byType(body), matching: find.byType(Switch))
    .at(index);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Measure the existing board controls in the app font, not square Ahem.
    final fonts = FontLoader('InterDisplay');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      fonts.addFont(
        File(
          'assets/fonts/Inter-$weight.otf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    }
    await fonts.load();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferencesService.instance.ensureInitialized();
  });

  setUp(() async {
    final prefs = SharedPreferencesService.instance.prefsOrNull!;
    await prefs.clear();
  });

  for (final light in [false, true]) {
    testWidgets(
      'Customization first, unique grouped controls (${light ? 'light' : 'dark'})',
      (tester) async {
        await _pumpSettings(tester, light: light);
        final list = tester.widget<ListView>(find.byType(ListView).first);
        final children =
            (list.childrenDelegate as SliverChildListDelegate).children;
        final titles = <String>[];
        for (final child in children) {
          final text = find.descendant(
            of: find.byWidget(child),
            matching: find.byType(Text),
          );
          if (text.evaluate().isNotEmpty) {
            titles.add(tester.widget<Text>(text.first).data!);
          }
        }
        expect(titles, [
          'Customization',
          'Board Settings',
          'Engine Experience',
          'Notification Settings',
          'Delete Account',
        ]);
        expect(find.text('Appearance').hitTestable(), findsNothing);
        await _tap(tester, find.text('Customization'));
        for (final label in [
          'Appearance',
          'Start section',
          'Home page',
          'Auto Pin',
          'Favorite Players',
          'Countrymen',
        ]) {
          expect(find.text(label), findsOneWidget);
        }
        final ordered = [
          'Appearance',
          'Start section',
          'Home page',
          'Auto Pin',
        ];
        for (var i = 1; i < ordered.length; i++) {
          expect(
            tester.getTopLeft(find.text(ordered[i])).dy,
            greaterThan(tester.getTopLeft(find.text(ordered[i - 1])).dy),
          );
        }
        final customization = find.ancestor(
          of: find.byType(StartScreenSettingsBody),
          matching: find.byWidgetPredicate(
            (widget) => widget.runtimeType.toString() == '_CollapsibleSection',
          ),
        );
        for (final type in [
          SettingsAppearanceSection,
          StartScreenSettingsBody,
          AutoPinSettingsBody,
        ]) {
          expect(
            find.descendant(of: customization, matching: find.byType(type)),
            findsOneWidget,
          );
          expect(find.byType(type), findsOneWidget);
        }
        expect(
          find.byKey(const ValueKey('settings_light_beta')),
          findsOneWidget,
        );
        expect(find.text('Dark'), findsOneWidget);
        expect(find.text('Light'), findsOneWidget);
        // Botvinnik no longer has a Settings section.
        expect(find.textContaining('Botvinnik'), findsNothing);
        await _tap(tester, find.text('Customization'));
        await _tap(tester, find.text('Board Settings'));
        expect(
          find.descendant(
            of: find.byType(BoardSettingsBody),
            matching: find.byType(AutoPinSettingsBody),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(BoardSettingsBody),
            matching: find.text('Games View Mode'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(BoardSettingsBody),
            matching: find.text('Board Theme'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('moved auto-pin switches keep callbacks and state', (
    tester,
  ) async {
    final autoPin = _AutoPin();
    final container = await _pumpSettings(
      tester,
      initiallyExpanded: SettingsSection.customization,
      autoPin: autoPin,
    );
    await _tap(tester, _switchIn(AutoPinSettingsBody, 0));
    await _tap(tester, _switchIn(AutoPinSettingsBody, 1));
    expect(autoPin.calls, ['favorite:false', 'countrymen:true']);
    final prefs = container.read(autoPinPreferencesProvider).requireValue;
    expect(prefs.favoritePlayersAutoPinEnabled, isFalse);
    expect(prefs.countrymenAutoPinEnabled, isTrue);
    await _tap(tester, find.text('Customization'));
    expect(find.text('Appearance').hitTestable(), findsNothing);
    await _tap(tester, find.text('Customization'));
    await tester.ensureVisible(_switchIn(AutoPinSettingsBody, 0));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Switch>(_switchIn(AutoPinSettingsBody, 0)).value,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'appearance and start pickers retain existing selection/storage',
    (tester) async {
      final container = await _pumpSettings(
        tester,
        initiallyExpanded: SettingsSection.customization,
      );
      await tester.tap(find.text('Light'));
      await tester.pump();
      expect(container.read(themeModeProvider), ThemeMode.light);
      expect(find.text(kLightModeBetaNotice), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Dark'));
      expect(container.read(themeModeProvider), ThemeMode.dark);
      await _tap(tester, find.text('Start section'));
      await _tap(tester, find.text('Events'));
      expect(readDefaultBottomTab(), BottomNavBarItem.tournaments);
      await _tap(tester, find.text('Home page'));
      await _tap(tester, find.text('My Space'));
      expect(readDefaultForYouTab(), ForYouTab.mySpace);
      expect(find.text('Used when Home is the start section'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('back navigation still awaits moved auto-pin persistence', (
    tester,
  ) async {
    final autoPin = _AutoPin()..pending = Completer<void>();
    await _pumpSettings(
      tester,
      initiallyExpanded: SettingsSection.customization,
      autoPin: autoPin,
      viaRoute: true,
    );
    await _tap(tester, _switchIn(AutoPinSettingsBody, 0));
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    autoPin.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsNothing);
    expect(find.text('Open settings'), findsOneWidget);
  });
}
