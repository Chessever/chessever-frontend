import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/prep_space_shortcut.dart';
import 'package:chessever2/screens/my_prep/providers/prep_providers.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_profile_card.dart';
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
  @override
  Future<List<SpaceShortcut>> build() async => [];

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
}
