import 'package:chessever2/screens/my_space/actions/space_menu_action.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/space_database.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/widgets/space_shortcut_drafts.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Uses the real add method, with only initial reads replaced. A rejected
/// add must return before touching SQLite, Supabase or an optimistic list.
class _ReadOnlyStore extends SpaceShortcutsNotifier {
  _ReadOnlyStore(this.initial);
  final List<SpaceShortcut> initial;

  @override
  Future<List<SpaceShortcut>> build() async => initial;
}

SpaceShortcut _draft(
  SpaceShortcutKind kind, {
  Map<String, dynamic> params = const {},
}) => SpaceShortcut.draft(
  kind: kind,
  targetId: 'target',
  title: kind.name,
  params: params,
);

void main() {
  test(
    'events, databases and smart events qualify while folders remain navigation-only',
    () {
      const permitted = {
        SpaceShortcutKind.event,
        SpaceShortcutKind.folder,
        SpaceShortcutKind.collection,
        SpaceShortcutKind.smartEvent,
      };
      for (final kind in SpaceShortcutKind.values) {
        expect(
          _draft(kind).canAddToMySpace,
          permitted.contains(kind),
          reason: kind.name,
        );
      }
      for (final section in SpaceSection.values) {
        expect(
          section.supportsAddingToMySpace,
          {
            SpaceSection.events,
            SpaceSection.library,
            SpaceSection.smartEvents,
          }.contains(section),
          reason: section.name,
        );
      }
      expect(
        _draft(
          SpaceShortcutKind.folder,
          params: {'nodeType': 'folder'},
        ).canAddToMySpace,
        isFalse,
      );
      expect(
        _draft(
          SpaceShortcutKind.folder,
          params: {'nodeType': 'database'},
        ).canAddToMySpace,
        isTrue,
      );
    },
  );

  test(
    'real write boundary refuses every forbidden kind without changing legacy rows',
    () async {
      final legacy = _draft(SpaceShortcutKind.game).copyWith(id: 'legacy-game');
      final container = ProviderContainer(
        overrides: [
          spaceShortcutsProvider.overrideWith(() => _ReadOnlyStore([legacy])),
        ],
      );
      addTearDown(container.dispose);
      await container.read(spaceShortcutsProvider.future);
      final store = container.read(spaceShortcutsProvider.notifier);
      for (final kind in SpaceShortcutKind.values) {
        final draft = _draft(kind);
        if (draft.canAddToMySpace) continue;
        expect(await store.add(draft), isFalse, reason: kind.name);
        expect(container.read(spaceShortcutsProvider).requireValue, [legacy]);
      }
      expect(
        await store.add(
          _draft(SpaceShortcutKind.folder, params: {'nodeType': 'folder'}),
        ),
        isFalse,
      );
      expect(container.read(spaceShortcutsProvider).requireValue, [legacy]);
    },
  );

  test(
    'home and edit expose only allowed pins without changing legacy data',
    () async {
      final seed = [for (final kind in SpaceShortcutKind.values) _draft(kind)];
      final container = ProviderContainer(
        overrides: [
          spaceShortcutsProvider.overrideWith(() => _ReadOnlyStore(seed)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(spaceShortcutsProvider.future);
      final groups = container.read(spaceCompactDatabaseGroupsProvider)!;
      expect(
        [for (final group in groups) ...group.items.map((pin) => pin.kind)],
        [
          SpaceShortcutKind.event,
          SpaceShortcutKind.folder,
          SpaceShortcutKind.smartEvent,
          SpaceShortcutKind.collection,
        ],
      );
      expect(container.read(spaceShortcutsProvider).requireValue, seed);
      expect(
        seed.map((pin) => SpaceShortcut.fromJson(pin.toJson())!.kind),
        SpaceShortcutKind.values,
      );
    },
  );

  testWidgets(
    'shared and labeled menus hide forbidden adds but retain legacy removal',
    (tester) async {
      final legacy = _draft(SpaceShortcutKind.game);
      late List<LibraryMenuAction> rows;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            spaceShortcutsProvider.overrideWith(() => _ReadOnlyStore([legacy])),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Consumer(
              builder: (context, ref, _) {
                ResponsiveHelper.init(context);
                ref.watch(spaceShortcutsProvider);
                rows = [
                  spaceMenuAction(
                    context: context,
                    ref: ref,
                    draft: _draft(SpaceShortcutKind.round),
                  ),
                  labeledSpaceMenuAction(
                    context: context,
                    ref: ref,
                    draft: _draft(SpaceShortcutKind.opening),
                    addLabel: 'Add opening',
                    removeLabel: 'Remove opening',
                  ),
                  spaceMenuAction(context: context, ref: ref, draft: legacy),
                  spaceMenuAction(
                    context: context,
                    ref: ref,
                    draft: _draft(SpaceShortcutKind.event),
                  ),
                ];
                return Scaffold(
                  body: TextButton(
                    onPressed: () =>
                        showLibraryContextMenu(context: context, actions: rows),
                    child: const Text('Actions'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(rows.first.visible, isFalse);
      expect(rows.first.enabled, isFalse);
      expect(rows[1].visible, isFalse);
      expect(rows[1].label, 'Add opening');
      expect(rows[2].visible, isTrue);
      expect(rows[2].label, 'Remove from My Space');
      expect(rows[3].visible, isTrue);
      expect(rows[3].enabled, isTrue);
      expect(rows[3].label, 'Add to My Space');
      await rows.first.onSelected();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
