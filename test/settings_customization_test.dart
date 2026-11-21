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
import 'package:chessever2/screens/stories/story_row_prefs.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/theme/theme_provider.dart';
import 'package:chessever2/utils/adaptive_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'fixtures/duo_window_matrix.dart';

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
  _Botvinnik({this.initial = true});

  final bool initial;
  final calls = <bool>[];

  @override
  Future<bool> build() async => initial;

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
  Size size = const Size(393, 852),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
        builder: (_, child) => AdaptiveWindowScope(child: child!),
        home: Builder(
          builder: (context) {
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
    for (final section in SettingsSection.values) {
      testWidgets(
        'Duo ${section.name} settings retains its expanded state in every window (${light ? 'light' : 'dark'})',
        (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = 1.6;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          for (final start in duoWindowCases) {
            tester.view.devicePixelRatio = 1;
            applyDuoWindow(tester, start);
            await _pumpSettings(
              tester,
              initiallyExpanded: section,
              light: light,
              size: start.size,
            );
            final state = tester.state(find.byType(SettingsPage));
            final route = ModalRoute.of(
              tester.element(find.byType(SettingsPage)),
            );
            for (final end in duoWindowCases) {
              applyDuoWindow(tester, start);
              await tester.pump();
              applyDuoWindow(tester, end, mirrorInsets: true);
              await tester.pumpAndSettle();
              expect(
                tester.takeException(),
                isNull,
                reason: '${section.name}: ${start.name} to ${end.name}',
              );
              expect(tester.state(find.byType(SettingsPage)), same(state));
              expect(
                ModalRoute.of(tester.element(find.byType(SettingsPage))),
                same(route),
              );
            }
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
          }
        },
      );
    }
  }

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
      await _tap(tester, find.text('Collections'));
      expect(readDefaultBottomTab(), BottomNavBarItem.collections);
      await _tap(tester, find.text('Home page'));
      await _tap(tester, find.text('My Space'));
      expect(readDefaultForYouTab(), ForYouTab.mySpace);
      expect(find.text('Used when Home is the start section'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a start section saved as Search reads, and opens, as Home', (
    tester,
  ) async {
    // Search left the dock for Today's button; Collections took its slot.
    await SharedPreferencesService.instance.prefsOrNull!.setString(
      defaultBottomTabPrefsKey,
      'search',
    );
    await _pumpSettings(
      tester,
      initiallyExpanded: SettingsSection.customization,
    );
    final row = find.ancestor(
      of: find.text('Start section'),
      matching: find.byType(InkWell),
    );
    expect(
      find.descendant(of: row.first, matching: find.text('Home')),
      findsOneWidget,
    );
    expect(readDefaultBottomTab(), BottomNavBarItem.forYou);
    expect(tester.takeException(), isNull);
  });

  testWidgets('start section offers only the sections on the bar', (
    tester,
  ) async {
    // Botvinnik saved as the start section, then switched off: a launch
    // opens Home, so Settings says Home and does not offer Botvinnik.
    await writeDefaultBottomTab(BottomNavBarItem.botvinnik);
    final container = await _pumpSettings(
      tester,
      initiallyExpanded: SettingsSection.customization,
      botvinnik: _Botvinnik(initial: false),
    );
    final row = find.ancestor(
      of: find.text('Start section'),
      matching: find.byType(InkWell),
    );
    expect(
      find.descendant(of: row.first, matching: find.text('Home')),
      findsOneWidget,
    );
    await _tap(tester, find.text('Start section'));
    final sheet = find.byType(BottomSheet);
    for (final title in ['Home', 'Feed', 'Collections', 'Profile']) {
      expect(
        find.descendant(of: sheet, matching: find.text(title)),
        findsOneWidget,
        reason: title,
      );
    }
    expect(
      find.descendant(of: sheet, matching: find.text('Botvinnik')),
      findsNothing,
    );
    await _tap(tester, find.descendant(of: sheet, matching: find.text('Home')));
    expect(readDefaultBottomTab(), BottomNavBarItem.forYou);

    // Switched back on, it is offered again.
    await container.read(botvinnikEnabledProvider.notifier).setEnabled(true);
    await tester.pumpAndSettle();
    await _tap(tester, find.text('Start section'));
    expect(
      find.descendant(of: sheet, matching: find.text('Botvinnik')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('Collection stories sits in Customization beside Start screen, '
      'On or Off, and its choice is kept on the device', (tester) async {
    final container = await _pumpSettings(
      tester,
      initiallyExpanded: SettingsSection.customization,
    );
    final start = tester.getRect(find.byType(StartScreenSettingsBody));
    final stories = tester.getRect(find.text('Collection stories'));
    expect(stories.top, greaterThan(start.bottom));
    // On by default.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('settings_story_row')),
        matching: find.text('On'),
      ),
      findsOneWidget,
    );
    await _tap(tester, find.text('Collection stories'));
    // Two choices, no more: the old "When there's something new" and
    // "Always" are both On now.
    expect(find.text("When there's something new"), findsNothing);
    expect(find.text('Always'), findsNothing);
    // The sheet's row, the last laid out.
    await tester.tap(find.text('Off').last);
    await tester.pumpAndSettle();
    expect(container.read(storyRowPrefsProvider).mode, StoryRowMode.off);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('settings_story_row')),
        matching: find.text('Off'),
      ),
      findsOneWidget,
    );
    final saved = SharedPreferencesService.instance.prefsOrNull!.getString(
      AppStoryRowPrefsStore.localKey,
    );
    expect(saved, contains('"m":"off"'));
    // The next launch reads it before its first frame.
    expect(
      StoryRowPrefs.decodeLocal(const AppStoryRowPrefsStore().readLocal()).mode,
      StoryRowMode.off,
    );
    expect(tester.takeException(), isNull);
  });

  test('a choice saved by 39.1.0 and older reads as On: "When there\'s '
      'something new" and "Always" alike; Off stays Off', () {
    for (final (wire, mode) in [
      ('new', StoryRowMode.on),
      ('always', StoryRowMode.on),
      ('on', StoryRowMode.on),
      ('off', StoryRowMode.off),
    ]) {
      expect(
        StoryRowPrefs.decodeLocal('{"m":"$wire","u":5}').mode,
        mode,
        reason: wire,
      );
      expect(StoryRowPrefs.fromAccountJson({'m': wire}).mode, mode);
    }
    // Written as "on", which builds before the change read as their own
    // default (When new), never as Off.
    expect(
      const StoryRowPrefs(mode: StoryRowMode.on).toAccountJson()['m'],
      'on',
    );
  });
}
