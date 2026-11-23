import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_actions.dart'
    show prepProfileMenu;
import 'package:chessever2/screens/my_prep/prep_space_shortcut.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_profile_card.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_watch_star.dart';
import 'package:chessever2/screens/my_space/actions/space_prep_actions.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_auto_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/space_database.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _Store extends SpaceShortcutsNotifier {
  _Store([this.seed = const []]);

  final List<SpaceShortcut> seed;

  @override
  Future<List<SpaceShortcut>> build() async => seed;

  @override
  Future<bool> add(SpaceShortcut draft) async {
    if (!draft.canAddToMySpace || this.contains(draft.kind, draft.targetId)) {
      return false;
    }
    state = AsyncData([draft, ...state.requireValue]);
    return true;
  }

  @override
  Future<SpaceShortcut?> removeTarget(
    SpaceShortcutKind kind,
    String targetId,
  ) async {
    final pin = pinFor(kind, targetId);
    state = AsyncData([
      for (final s in state.requireValue)
        if (s.key != pin?.key) s,
    ]);
    return pin;
  }

  @override
  Future<void> restore(SpaceShortcut pin) async {
    state = AsyncData([pin, ...state.requireValue]);
  }
}

class _Hidden extends SpaceHiddenAutoKeys {
  @override
  Set<String> build() => const {};
  @override
  void hide(String key) => state = {...state, key};
  @override
  void unhide(String key) => state = {...state}..remove(key);
}

PrepProfile _profile(PrepKind kind, PrepSource source) => PrepProfile(
  id: 'prep-${kind.name}-${source.name}',
  kind: kind,
  name: 'Club preparation',
  createdAtMs: 1,
  accounts: [PrepAccount(source: source, username: 'clubplayer')],
);

/// [profile] stored in a temporary `prep/profiles.json`, loaded into a
/// container whose My Space holds [pins].
Future<(ProviderContainer, _Store)> _loadedPrep(
  WidgetTester tester,
  PrepProfile profile, {
  List<SpaceShortcut> pins = const [],
}) async {
  final directory = Directory.systemTemp.createTempSync('prep_space_');
  addTearDown(() => directory.deleteSync(recursive: true));
  final source = File('${directory.path}/prep/profiles.json');
  source.parent.createSync(recursive: true);
  source.writeAsStringSync(
    jsonEncode({
      'version': 1,
      'profiles': [profile.toJson()],
    }),
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => directory.path,
  );
  addTearDown(
    () => messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    ),
  );
  final store = _Store(pins);
  final container = ProviderContainer(
    overrides: [
      spaceShortcutsProvider.overrideWith(() => store),
      spaceHiddenAutoKeysProvider.overrideWith(_Hidden.new),
    ],
  );
  addTearDown(container.dispose);
  await tester.runAsync(() async {
    final ready = Completer<void>();
    final sub = container.listen(prepProfilesProvider, (_, value) {
      if (!value.isLoading && !ready.isCompleted) ready.complete();
    }, fireImmediately: true);
    await ready.future;
    sub.close();
  });
  return (container, store);
}

void main() {
  test('all saved prep kinds and sources retain their profile identity', () {
    for (final kind in PrepKind.values) {
      for (final source in PrepSource.values) {
        final profile = _profile(kind, source);
        final pin = prepProfileSpaceDraft(profile);
        expect(pin.canAddToMySpace, isTrue);
        expect(pin.targetId, profile.id);
        expect(pin.section, SpaceSection.library);
        expect(SpaceShortcut.fromJson(pin.toJson())!.key, pin.key);
        expect(
          prepProfileSpaceDraft(profile.copyWith(name: 'Renamed')).key,
          pin.key,
        );
      }
    }
  });

  for (final kind in PrepKind.values) {
    testWidgets('pin and remove a ${kind.name} card without changing My Prep', (
      tester,
    ) async {
      final directory = Directory.systemTemp.createTempSync('prep_space_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final profile = _profile(kind, PrepSource.lichess);
      final source = File('${directory.path}/prep/profiles.json');
      source.parent.createSync(recursive: true);
      final sourceJson = jsonEncode({
        'version': 1,
        'profiles': [profile.toJson()],
      });
      source.writeAsStringSync(sourceJson);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => directory.path,
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        ),
      );
      final store = _Store();
      final container = ProviderContainer(
        overrides: [
          spaceShortcutsProvider.overrideWith(() => store),
          spaceHiddenAutoKeysProvider.overrideWith(_Hidden.new),
        ],
      );
      addTearDown(container.dispose);
      await tester.runAsync(() async {
        final ready = Completer<void>();
        final sub = container.listen(prepProfilesProvider, (_, value) {
          if (!value.isLoading && !ready.isCompleted) ready.complete();
        }, fireImmediately: true);
        await ready.future;
        sub.close();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Consumer(
              builder: (context, ref, _) {
                ResponsiveHelper.init(context);
                final profiles = ref.watch(prepProfilesProvider);
                ref.watch(spaceShortcutsProvider);
                return Scaffold(
                  body: profiles.hasValue
                      ? PrepProfileCard(profile: profile, onTap: () {})
                      : const SizedBox(),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.longPress(find.byType(PrepProfileCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to My Space'));
      await tester.pumpAndSettle();
      expect(store.contains(SpaceShortcutKind.prepProfile, profile.id), isTrue);
      expect(
        container.read(prepProfileProvider(profile.id))!.toJson(),
        profile.toJson(),
      );

      await tester.longPress(find.byType(PrepProfileCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from My Space'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        store.contains(SpaceShortcutKind.prepProfile, profile.id),
        isFalse,
      );
      expect(
        container.read(prepProfileProvider(profile.id))!.toJson(),
        profile.toJson(),
      );
      expect(source.readAsStringSync(), sourceJson);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(store.contains(SpaceShortcutKind.prepProfile, profile.id), isTrue);
      expect(source.readAsStringSync(), sourceJson);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  for (final width in [175.0, 358.0]) {
    testWidgets('prep shortcut fits a $width wide card with large text', (
      tester,
    ) async {
      final profile = _profile(
        PrepKind.opponent,
        PrepSource.manual,
      ).copyWith(name: 'Long named opponent preparation profile');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            spaceShortcutsProvider.overrideWith(_Store.new),
            spaceHiddenAutoKeysProvider.overrideWith(_Hidden.new),
            prepProfileProvider(profile.id).overrideWithValue(profile),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return Scaffold(
                  body: MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: const TextScaler.linear(1.5)),
                    child: Center(
                      child: SizedBox(
                        width: width,
                        child: SpaceSavedRow(
                          shortcut: prepProfileSpaceDraft(profile),
                          stacked: width < 200,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text(profile.name), findsOneWidget);
      expect(find.text('0 games'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  for (final kind in [PrepKind.opponent, PrepKind.favorite]) {
    testWidgets('a ${kind.name} Prep card holds into the Prep page\'s own '
        'rows, in its order, with Remove from My Space for its My Space row '
        'and nothing that deletes', (tester) async {
      final profile = PrepProfile(
        id: 'prep-${kind.name}-menu',
        kind: kind,
        name: 'Club preparation',
        createdAtMs: 1,
        favoriteId: kind == PrepKind.favorite ? 'fav-1' : null,
        accounts: const [
          PrepAccount(source: PrepSource.lichess, username: 'clubplayer'),
        ],
      );
      final pin = prepProfileSpaceDraft(profile);
      final (container, _) = await _loadedPrep(tester, profile, pins: [pin]);
      late List<LibraryMenuAction> prepRows;
      late List<LibraryMenuAction> spaceRows;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Consumer(
              builder: (context, ref, _) {
                ResponsiveHelper.init(context);
                ref.watch(prepProfilesProvider);
                ref.watch(spaceShortcutsProvider);
                prepRows = prepProfileMenu(context, ref, profile);
                spaceRows = spacePrepProfileMenu(context, ref, pin, profile);
                return Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 358,
                      child: SpaceSavedRow(shortcut: pin),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final expected = [
        for (final row in prepRows)
          if (row.label == 'Add to My Space' ||
              row.label == 'Remove from My Space')
            'Remove from My Space'
          else if (!row.destructive)
            row.label,
      ];
      expect([for (final row in spaceRows) row.label], expected);
      expect(spaceRows.where((row) => row.destructive), isEmpty);
      expect(
        [for (final row in spaceRows) row.prominent],
        [
          for (final row in prepRows)
            if (!row.destructive) row.prominent,
        ],
      );

      await tester.longPress(find.byType(SpaceSavedRow));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Refresh games'), findsOneWidget);
      expect(find.text('Remove from My Space'), findsOneWidget);
      expect(find.text('Remove'), findsNothing);
      expect(find.text('Clear downloaded games'), findsNothing);
      expect(find.textContaining('Open'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  /// One saved Prep row, as My Space draws it.
  Future<void> pumpRow(
    WidgetTester tester,
    PrepProfile profile, {
    double width = 358,
    bool disclosure = true,
    bool editing = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          spaceShortcutsProvider.overrideWith(_Store.new),
          spaceHiddenAutoKeysProvider.overrideWith(_Hidden.new),
          prepProfileProvider(profile.id).overrideWithValue(profile),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(1.5)),
                  child: Center(
                    child: SizedBox(
                      width: width,
                      child: SpaceSavedRow(
                        shortcut: prepProfileSpaceDraft(profile),
                        stacked: width < 200,
                        disclosure: disclosure,
                        editing: editing,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
  }

  final chevron = find.byIcon(Icons.chevron_right_rounded);
  final star = find.byType(PrepWatchStar);

  for (final source in [PrepSource.lichess, PrepSource.chesscom]) {
    for (final width in [175.0, 358.0]) {
      testWidgets('a ${source.name} player ends in its star at $width wide', (
        tester,
      ) async {
        await pumpRow(
          tester,
          _profile(
            PrepKind.opponent,
            source,
          ).copyWith(name: 'Long named opponent preparation profile'),
          width: width,
        );
        expect(star, findsOneWidget);
        expect(chevron, findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  // The report: an over-the-board player ended in an arrow. Every Prep
  // card is starrable now.
  testWidgets('a player with no online account ends in its star too', (
    tester,
  ) async {
    await pumpRow(tester, _profile(PrepKind.opponent, PrepSource.manual));
    expect(star, findsOneWidget);
    expect(chevron, findsNothing);
  });

  for (final choice in ['Just star', 'Notify me', 'Dismiss']) {
    testWidgets('Prep star asks before subscribing: $choice', (tester) async {
      final profile = _profile(PrepKind.opponent, PrepSource.lichess);
      final (container, _) = await _loadedPrep(tester, profile);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return Scaffold(body: PrepWatchStar(profileId: profile.id));
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(star);
      await tester.pumpAndSettle();
      expect(find.text('Get notifications for this player?'), findsOneWidget);
      final notifier = container.read(prepProfilesProvider.notifier);
      expect(notifier.byId(profile.id)!.watching, isFalse);
      if (choice == 'Dismiss') {
        await tester.tapAt(const Offset(790, 590));
      } else {
        await tester.tap(find.text(choice));
      }
      await tester.pumpAndSettle();
      final saved = notifier.byId(profile.id)!;
      expect(saved.watching, choice == 'Notify me');
      expect(find.bySemanticsLabel('Unstar ${profile.name}'), findsOneWidget);
      final restored = PrepProfile.fromJson(saved.toJson())!;
      expect(restored.watching, saved.watching);
      expect(restored.isStarred, isTrue);
      expect(
        prepProfileFromPin(prepProfileSpaceDraft(restored))!.isStarred,
        isTrue,
      );
      expect(prepProfileSpaceDraft(restored).targetId, profile.id);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  testWidgets('your own online account is starred too', (tester) async {
    await pumpRow(tester, _profile(PrepKind.mine, PrepSource.lichess));
    expect(star, findsOneWidget);
    expect(chevron, findsNothing);
  });

  testWidgets('in the home\'s Edit a Prep row keeps its star\'s place, faded '
      'out and inert, so nothing on the card moves', (tester) async {
    final profile = _profile(PrepKind.opponent, PrepSource.lichess);
    await pumpRow(tester, profile);
    final rest = tester.getSize(find.byType(SpaceSavedRow));
    final restTitle = tester.getRect(find.text(profile.name));

    final handle = tester.ensureSemantics();
    await pumpRow(tester, profile, editing: true);
    await tester.pump(const Duration(milliseconds: 400));
    expect(star, findsOneWidget);
    final fade = tester.widget<Opacity>(
      find.ancestor(of: star, matching: find.byType(Opacity)).first,
    );
    expect(fade.opacity, 0);
    expect(
      tester
          .widget<IgnorePointer>(
            find.ancestor(of: star, matching: find.byType(IgnorePointer)).first,
          )
          .ignoring,
      isTrue,
    );
    expect(tester.getSize(find.byType(SpaceSavedRow)), rest);
    expect(tester.getRect(find.text(profile.name)), restTitle);
    final node = tester.getSemantics(find.byType(SpaceSavedRow));
    expect(node.getSemanticsData().customSemanticsActionIds ?? [], isEmpty);
    handle.dispose();
  });

  testWidgets('in Edit a Prep row has no star, a tap selects', (tester) async {
    await pumpRow(
      tester,
      _profile(PrepKind.opponent, PrepSource.lichess),
      disclosure: false,
    );
    expect(star, findsNothing);
    expect(chevron, findsNothing);
  });

  testWidgets('screen readers get the star as an action of the row', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpRow(tester, _profile(PrepKind.opponent, PrepSource.lichess));
    final node = tester.getSemantics(find.byType(SpaceSavedRow));
    expect(node.getSemanticsData().customSemanticsActionIds, isNotEmpty);
    handle.dispose();
  });
}
