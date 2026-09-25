import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart'
    show smartEventSpaceDraft;
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_state.dart';
import 'package:chessever2/screens/my_space/defaults/space_defaults.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/navigation/space_shortcut_navigator.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/utils/eco_openings.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:chessever2/widgets/search/search_overlay_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A store that starts from [initial] and never reaches the server (no
/// signed-in user), so remove and Undo run their real local paths.
class _LocalStore extends SpaceShortcutsNotifier {
  _LocalStore(this.initial);

  final List<SpaceShortcut> initial;

  @override
  Future<List<SpaceShortcut>> build() async => initial;
}

/// Answers the store's SQLite cache writes in memory, so the real remove and
/// Undo paths run without the native plugin.
void _stubSqlite() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('com.tekartik.sqflite'),
        (call) async => switch (call.method) {
          'getDatabasesPath' => '/tmp',
          'openDatabase' => 1,
          // PRAGMA user_version reads 1: the schema is already in place.
          'query' => {
            'columns': ['v'],
            'rows': [
              [1],
            ],
          },
          'insert' => 1,
          'update' || 'delete' => 0,
          'batch' => <Object?>[],
          _ => null,
        },
      );
}

void main() {
  test('the elite lines are catalogue rows, verbatim', () {
    final all = [...kSpaceDefaultOpenings, ...kSpacePopularOpenings];
    // Two defaults, so each is easy to keep or remove; the picker has the
    // rest, the ten lines older builds seeded first.
    expect(kSpaceDefaultOpenings, hasLength(2));
    expect(kSpaceRetiredDefaultOpenings, hasLength(10));
    expect(kSpacePopularOpenings, hasLength(15));
    expect(
      kSpacePopularOpenings.take(10).map((o) => o.eco),
      kSpaceRetiredDefaultOpenings.map((o) => o.eco),
    );
    for (final o in all) {
      final hit = EcoOpenings.catalog.where(
        (r) =>
            r.code == o.eco && r.name == o.catalogueName && r.moves == o.moves,
      );
      expect(hit, isNotEmpty, reason: '${o.eco} ${o.catalogueName}');
    }
    // The most played 1.d4 and 1.e4 lines at 2700+, then the rest of the
    // old seed in the order it was laid out (the trim relies on it).
    expect(kSpaceDefaultOpenings.map((o) => o.eco).toList(), ['D37', 'B30']);
    expect(
      kSpaceDefaultOpenings.first.moves,
      '1. d4 d5 2. c4 e6 3. Nc3 Nf6 4. Nf3',
    );
    expect(kSpaceDefaultOpenings.last.moves, '1. e4 c5 2. Nf3 Nc6 3. Bb5');
    expect(kSpaceRetiredDefaultOpenings.map((o) => o.eco).toList(), [
      'D35', 'B90', 'C50', 'C65', 'D38', //
      'C42', 'E05', 'C84', 'E11', 'B12',
    ]);
  });

  test('each default is the same position a search pin of that line is', () {
    final keys = <String>{};
    for (final o in [
      ...kSpaceDefaultOpenings,
      ...kSpaceRetiredDefaultOpenings,
    ]) {
      final draft = spaceEliteOpeningDraft(o)!;
      expect(draft.kind, SpaceShortcutKind.position);
      expect(draft.section, SpaceSection.openings);
      expect(keys.add(draft.key), isTrue, reason: 'unique ${o.eco}');

      final line = resolveSpaceLine(moves: o.sans)!;
      expect(line.ucis, hasLength(o.sans.length), reason: 'replays ${o.eco}');
      expect(draft.targetId, line.fen);
      expect(draft.params['moves'], line.ucis);

      final fromSearch = openingSearchSpaceDraft(
        OpeningSearchSelection(
          filter: GameEcoFilter.forCode(o.eco),
          hierarchyLabel: o.catalogueName,
          movePath: o.sans,
          isAggregate: false,
        ),
        name: o.catalogueName,
      );
      expect(fromSearch.key, draft.key, reason: o.eco);

      // The tile's name, code and the editor position.
      expect(draft.title, o.tileName);
      expect(draft.params['openingName'], o.tileName);
      expect(draft.params['eco'], o.eco);
      expect(spaceShortcutFen(draft), line.fen);
    }
  });

  test('the seeded Smart Events are the app\'s own GM and Classical', () {
    final gm = kSpaceDefaultSmartEvents[0];
    final classical = kSpaceDefaultSmartEvents[1];
    expect(gm.criteriaKey, kDiscoverySmartPresets.first.criteriaKey);
    expect(gm.displayName, 'GM Games');
    expect(classical.displayName, 'Classical Games');

    // What the Events filter builds for "Classical" alone.
    final fromFilter = smartEventRequestFromFilterState(
      const FilterPopupState(
        formatsAndStates: {'standard'},
        eloRange: RangeValues(kFilterMinElo, kFilterMaxElo),
      ),
    )!;
    expect(classical.criteriaKey, fromFilter.criteriaKey);
    expect(fromFilter.displayName, 'Classical Games');
    expect(
      smartEventRequestFromFilterState(
        const FilterPopupState(
          formatsAndStates: {},
          eloRange: RangeValues(kFilterMinElo, kFilterMaxElo),
        ),
      ),
      isNull,
    );
  });

  test('the seed is every default once, tagged, in row order', () {
    final seed = spaceSeedDrafts();
    expect(seed, hasLength(4));
    expect(seed.map((s) => s.key).toSet(), hasLength(4));
    expect(seed.every(isSpaceSeeded), isTrue);
    expect(seed.take(2).map((s) => s.title), [
      'QGD Three Knights',
      'Sicilian Rossolimo',
    ]);
    expect(
      seed.take(2).every((s) => s.section == SpaceSection.openings),
      isTrue,
    );
    expect(
      seed.skip(2).every((s) => s.kind == SpaceShortcutKind.smartEvent),
      isTrue,
    );
  });

  test('a saved board-editor position opens back in the editor', () {
    const custom = '8/8/4k3/8/8/4K3/4P3/8 w - - 0 1';
    final bare = SpaceShortcut.draft(
      kind: SpaceShortcutKind.position,
      targetId: custom,
      title: 'Custom position',
    );
    expect(spaceShortcutFen(bare), custom);
    final code = SpaceShortcut.draft(
      kind: SpaceShortcutKind.opening,
      targetId: 'B90',
      title: 'Sicilian, Najdorf',
    );
    expect(spaceShortcutFen(code), isNotNull);
    final player = SpaceShortcut.draft(
      kind: SpaceShortcutKind.player,
      targetId: '1503014',
      title: 'Carlsen',
    );
    expect(spaceShortcutFen(player), isNull);
  });
  group('the Openings picker', () {
    List<String> ecos(List<SpacePickerOpening> picks) => [
      for (final p in picks) p.opening.eco,
    ];
    String keyOf(SpaceEliteOpening o) => spaceEliteOpeningDraft(o)!.key;

    test('an empty My Space is offered every line, most played first', () {
      final picks = spacePickerOpenings(const {});
      expect(picks.added, isEmpty);
      expect(picks.fresh, hasLength(17));
      expect(ecos(picks.fresh).take(3), ['D37', 'B30', 'D35']);
      expect(ecos(picks.fresh).toSet(), hasLength(17));
    });

    test('what is not in My Space yet comes first, the rest after', () {
      final seeded = {for (final s in spaceSeedDrafts()) s.key};
      final picks = spacePickerOpenings(seeded);
      // The two defaults are in: new options lead.
      expect(ecos(picks.fresh).first, 'D35');
      expect(picks.fresh, hasLength(15));
      expect(ecos(picks.added), ['D37', 'B30']);
    });

    test('a removed default is a new option again, ready to re-add', () {
      final pinned = {keyOf(kSpaceDefaultOpenings.last)};
      final picks = spacePickerOpenings(pinned);
      expect(ecos(picks.fresh).first, 'D37');
      expect(ecos(picks.fresh), isNot(contains('B30')));
      expect(ecos(picks.added), ['B30']);
      // The draft is the very pin the seed made, so adding it back dedupes.
      expect(picks.fresh.first.draft.key, spaceSeedDrafts().first.key);
    });
  });

  group('Undo keeps a retired default', () {
    SpaceShortcut tag(SpaceShortcut s) =>
        s.copyWith(params: {...s.params, kSpaceSeedParam: kSpaceSeedTag});
    // What builds before 2026-09-24 seeded: twelve openings, then GM and
    // Classical, laid out by the same planner.
    final legacy = SpaceShortcutsNotifier.planSeed(const [], [
      for (final o in [
        ...kSpaceDefaultOpenings,
        ...kSpaceRetiredDefaultOpenings,
      ])
        tag(spaceEliteOpeningDraft(o)!),
      for (final r in kSpaceDefaultSmartEvents) tag(smartEventSpaceDraft(r)),
    ]);
    final najdorf = legacy.firstWhere(
      (s) => s.title == 'Najdorf, English Attack',
    );
    Iterable<String> trimmed(List<SpaceShortcut> rows) =>
        planSpaceDefaultTrim(rows).map((s) => s.key);

    test('a restored default is marked kept, and the trim leaves it', () {
      // Untouched, it would be taken back.
      expect(trimmed(legacy), contains(najdorf.key));

      final back = spaceRestoredShortcut(najdorf);
      expect(isSpaceKept(back), isTrue);
      expect(isSpaceSeeded(back), isTrue);
      expect(back.sortIndex, najdorf.sortIndex);
      final rows = [for (final s in legacy) s.key == back.key ? back : s];
      expect(trimmed(rows), hasLength(9));
      expect(trimmed(rows), isNot(contains(najdorf.key)));
      // The mark survives the round trip older builds ignore.
      expect(isSpaceKept(SpaceShortcut.fromJson(back.toJson())!), isTrue);
    });

    test('a pin the user made comes back exactly as it was', () {
      final mine = SpaceShortcut.draft(
        kind: SpaceShortcutKind.player,
        targetId: '1503014',
        title: 'Carlsen',
      );
      expect(identical(spaceRestoredShortcut(mine), mine), isTrue);
      final kept = spaceRestoredShortcut(najdorf);
      expect(identical(spaceRestoredShortcut(kept), kept), isTrue);
    });

    test('remove then Undo through the store keeps it from the trim', () async {
      _stubSqlite();
      final container = ProviderContainer(
        overrides: [
          spaceShortcutsProvider.overrideWith(() => _LocalStore(legacy)),
        ],
      );
      addTearDown(container.dispose);
      await container.read(spaceShortcutsProvider.future);
      final store = container.read(spaceShortcutsProvider.notifier);

      final removed = await store.remove(najdorf.id);
      expect(removed?.key, najdorf.key);
      await store.restore(removed!);

      final list = container.read(spaceShortcutsProvider).requireValue;
      final back = list.firstWhere((s) => s.key == najdorf.key);
      expect(isSpaceKept(back), isTrue);
      expect(back.sortIndex, najdorf.sortIndex);
      expect(trimmed(list), hasLength(9));
      expect(trimmed(list), isNot(contains(najdorf.key)));
    });
  });
}
