import 'dart:async';
import 'dart:io';

import 'package:chessever2/chat/botvinnik_provider.dart';
import 'package:chessever2/providers/auto_pin_preferences_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/providers/board_engine_lines_visibility_provider.dart';
import 'package:chessever2/providers/notification_permission_provider.dart';
import 'package:chessever2/providers/notification_preferences_provider.dart';
import 'package:chessever2/repository/local_storage/auto_pin_preferences/auto_pin_preferences_repository.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/for_you/providers/for_you_tab_provider.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/settings/settings_page.dart';
import 'package:chessever2/screens/settings/widgets/board_settings_body.dart';
import 'package:chessever2/screens/settings/widgets/botvinnik_settings_body.dart';
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

class _BoardLinesVisibility extends BoardEngineLinesVisibleNotifier {
  @override
  Future<bool> build() async => true;
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

class _Botvinnik extends BotvinnikEnabledNotifier {
  final calls = <bool>[];

  @override
  Future<bool> build() async => true;

  @override
  Future<void> setEnabled(bool enabled) async {
    calls.add(enabled);
    state = AsyncData(enabled);
  }
}

Future<ProviderContainer> _pumpSettings(
  WidgetTester tester, {
  SettingsSection? initiallyExpanded,
  bool light = false,
  _AutoPin? autoPin,
  _Botvinnik? botvinnik,
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
      boardEngineLinesVisibleProvider.overrideWith(_BoardLinesVisibility.new),
      notificationPreferencesProvider.overrideWith(_Notifications.new),
      notificationPermissionProvider.overrideWith((_) => _Permission()),
      subscriptionProvider.overrideWith((_) => _Subscription()),
      autoPinPreferencesProvider.overrideWith(() => autoPin ?? _AutoPin()),
      botvinnikEnabledProvider.overrideWith(() => botvinnik ?? _Botvinnik()),
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
          'Botvinnik',
        ]) {
          expect(find.text(label), findsOneWidget);
        }
        final ordered = [
          'Appearance',
          'Start section',
          'Home page',
          'Auto Pin',
          'Botvinnik',
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
          BotvinnikSettingsBody,
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

  testWidgets('moved switches keep callbacks, state and Botvinnik expansion', (
    tester,
  ) async {
    final autoPin = _AutoPin();
    final botvinnik = _Botvinnik();
    final container = await _pumpSettings(
      tester,
      initiallyExpanded: SettingsSection.customization,
      autoPin: autoPin,
      botvinnik: botvinnik,
    );
    await _tap(tester, _switchIn(AutoPinSettingsBody, 0));
    await _tap(tester, _switchIn(AutoPinSettingsBody, 1));
    expect(autoPin.calls, ['favorite:false', 'countrymen:true']);
    expect(
      container
          .read(autoPinPreferencesProvider)
          .requireValue
          .favoritePlayersAutoPinEnabled,
      isFalse,
    );
    expect(
      container
          .read(autoPinPreferencesProvider)
          .requireValue
          .countrymenAutoPinEnabled,
      isTrue,
    );
    await _tap(tester, find.text('Botvinnik'));
    await _tap(tester, _switchIn(BotvinnikSettingsBody, 0));
    expect(botvinnik.calls, [false]);
    expect(container.read(botvinnikEnabledProvider).requireValue, isFalse);
    await _tap(tester, find.text('Customization'));
    expect(find.text('Appearance').hitTestable(), findsNothing);
    await _tap(tester, find.text('Customization'));
    await tester.ensureVisible(_switchIn(BotvinnikSettingsBody, 0));
    await tester.pumpAndSettle();
    expect(_switchIn(BotvinnikSettingsBody, 0).hitTestable(), findsOneWidget);
    expect(
      tester.widget<Switch>(_switchIn(BotvinnikSettingsBody, 0)).value,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('initial Botvinnik destination expands both parent and child', (
    tester,
  ) async {
    await _pumpSettings(tester, initiallyExpanded: SettingsSection.botvinnik);
    expect(find.text('Light').hitTestable(), findsOneWidget);
    await tester.ensureVisible(_switchIn(BotvinnikSettingsBody, 0));
    await tester.pumpAndSettle();
    expect(_switchIn(BotvinnikSettingsBody, 0).hitTestable(), findsOneWidget);
    await _tap(tester, find.text('Botvinnik'));
    expect(_switchIn(BotvinnikSettingsBody, 0).hitTestable(), findsNothing);
    await _tap(tester, find.text('Botvinnik'));
    await tester.ensureVisible(_switchIn(BotvinnikSettingsBody, 0));
    await tester.pumpAndSettle();
    expect(_switchIn(BotvinnikSettingsBody, 0).hitTestable(), findsOneWidget);
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
