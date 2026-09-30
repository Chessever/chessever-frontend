import 'package:chessever2/screens/my_space/defaults/space_defaults.dart';
import 'package:chessever2/screens/my_space/defaults/space_seed_gate.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart'
    show smartEventSpaceDraft;
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:flutter_test/flutter_test.dart';

SpaceShortcut _pin(String target, double sort) => SpaceShortcut(
  id: 'id-$target',
  kind: SpaceShortcutKind.player,
  targetId: target,
  title: target,
  sortIndex: sort,
);

void main() {
  group('planSeed', () {
    test('adds every default after the pins, in order', () {
      final current = [_pin('a', 3), _pin('b', 1)];
      final seed = spaceSeedDrafts();
      final plan = SpaceShortcutsNotifier.planSeed(current, seed);
      expect(plan, hasLength(seed.length));
      expect(plan.map((s) => s.key), seed.map((s) => s.key));
      // Below the lowest pin, descending in list order.
      expect(plan.first.sortIndex, lessThan(0));
      for (var i = 1; i < plan.length; i++) {
        expect(plan[i].sortIndex, lessThan(plan[i - 1].sortIndex));
      }
      // Each gets its own local id.
      expect(plan.map((s) => s.id).toSet(), hasLength(plan.length));
      expect(plan.every((s) => s.isLocal), isTrue);
    });

    test('skips a default already pinned and stays below negative pins', () {
      final seed = spaceSeedDrafts();
      final already = seed[2].copyWith(id: 'server', sortIndex: -7);
      final plan = SpaceShortcutsNotifier.planSeed([already], seed);
      expect(plan, hasLength(seed.length - 1));
      expect(plan.any((s) => s.key == already.key), isFalse);
      expect(plan.first.sortIndex, -8);
    });

    test('an account that holds everything gets nothing', () {
      final seed = spaceSeedDrafts();
      expect(SpaceShortcutsNotifier.planSeed(seed, seed), isEmpty);
    });
  });

  group('planSpaceSeed', () {
    test('a guest seeds once per device', () {
      expect(
        planSpaceSeed(signedIn: false, local: SpaceSeedMark.none),
        SpaceSeedStep.seed,
      );
      expect(
        planSpaceSeed(signedIn: false, local: SpaceSeedMark.seeded),
        SpaceSeedStep.skip,
      );
    });

    test('an account waits for the server before seeding', () {
      expect(
        planSpaceSeed(signedIn: true, local: SpaceSeedMark.none),
        SpaceSeedStep.skip,
      );
      expect(
        planSpaceSeed(
          signedIn: true,
          local: SpaceSeedMark.none,
          serverKnown: true,
        ),
        SpaceSeedStep.seed,
      );
    });

    test('an account seeded anywhere is never seeded again', () {
      // The account flag, from another device or an earlier install.
      expect(
        planSpaceSeed(
          signedIn: true,
          local: SpaceSeedMark.none,
          serverKnown: true,
          remoteFlag: true,
        ),
        SpaceSeedStep.markOnly,
      );
      // A seeded row on the server, flag write lost.
      expect(
        planSpaceSeed(
          signedIn: true,
          local: SpaceSeedMark.none,
          serverKnown: true,
          serverHasSeededRows: true,
        ),
        SpaceSeedStep.markOnly,
      );
      // Seeded on this device, flag not written yet.
      expect(
        planSpaceSeed(
          signedIn: true,
          local: SpaceSeedMark.seeded,
          serverKnown: true,
        ),
        SpaceSeedStep.markOnly,
      );
      // Done for good.
      expect(
        planSpaceSeed(
          signedIn: true,
          local: SpaceSeedMark.synced,
          serverKnown: true,
        ),
        SpaceSeedStep.skip,
      );
    });
  });

  group('planSpaceDefaultTrim', () {
    SpaceShortcut tag(SpaceShortcut s) =>
        s.copyWith(params: {...s.params, kSpaceSeedParam: kSpaceSeedTag});
    SpaceShortcut opening(SpaceEliteOpening o) => spaceEliteOpeningDraft(o)!;

    // What builds before 2026-09-24 seeded: twelve openings, then GM and
    // Classical, laid out by the same planner.
    final legacy = [
      for (final o in [
        ...kSpaceDefaultOpenings,
        ...kSpaceRetiredDefaultOpenings,
      ])
        tag(opening(o)),
      for (final r in kSpaceDefaultSmartEvents) tag(smartEventSpaceDraft(r)),
    ];
    List<SpaceShortcut> seededOld([List<SpaceShortcut> before = const []]) => [
      ...before,
      ...SpaceShortcutsNotifier.planSeed(before, legacy),
    ];
    final retiredKeys = {
      for (final o in kSpaceRetiredDefaultOpenings) opening(o).key,
    };
    String keyOf(String eco) => opening(
      kSpaceRetiredDefaultOpenings.firstWhere((o) => o.eco == eco),
    ).key;
    List<SpaceShortcut> replace(
      List<SpaceShortcut> rows,
      String key,
      SpaceShortcut Function(SpaceShortcut) change,
    ) => [for (final s in rows) s.key == key ? change(s) : s];

    test('an untouched old seed gives back exactly its ten retired lines', () {
      final rows = seededOld([_pin('mine', 4)]);
      final trim = planSpaceDefaultTrim(rows);
      expect(trim.map((s) => s.key).toSet(), retiredKeys);
      // The two defaults, the Smart Events and the user's pin stay.
      final kept = rows.where((s) => !trim.contains(s)).map((s) => s.title);
      expect(kept, containsAll(['QGD Three Knights', 'Sicilian Rossolimo']));
      expect(kept, contains('mine'));
    });

    test('rows the user already removed do not change the run', () {
      final rows = seededOld()
        ..removeWhere((s) => s.key == keyOf('C65') || s.title == 'GM Games');
      expect(planSpaceDefaultTrim(rows), hasLength(9));
    });

    test('an opened line stays', () {
      var rows = replace(seededOld(), keyOf('B90'), (s) {
        return s.copyWith(openCount: 1);
      });
      rows = replace(rows, keyOf('C42'), (s) {
        return s.copyWith(lastOpenedAt: DateTime(2026, 9, 1));
      });
      final trim = planSpaceDefaultTrim(rows).map((s) => s.key);
      expect(trim, hasLength(8));
      expect(trim, isNot(contains(keyOf('B90'))));
      expect(trim, isNot(contains(keyOf('C42'))));
    });

    test('a moved line stays', () {
      final rows = seededOld();
      final moved = SpaceShortcutsNotifier.planSectionMove(
        rows,
        keyOf('C50'),
        0,
      )!;
      final between = SpaceShortcutsNotifier.planSectionMove(
        moved.list,
        keyOf('E05'),
        3,
      )!;
      final trim = planSpaceDefaultTrim(between.list).map((s) => s.key);
      expect(trim, hasLength(8));
      expect(trim, isNot(contains(keyOf('C50'))));
      expect(trim, isNot(contains(keyOf('E05'))));
    });

    test('a line the user pinned themselves is never taken', () {
      final rows = replace(seededOld(), keyOf('D35'), (s) {
        return s.copyWith(params: {...s.params}..remove(kSpaceSeedParam));
      });
      final trim = planSpaceDefaultTrim(rows).map((s) => s.key);
      expect(trim, hasLength(9));
      expect(trim, isNot(contains(keyOf('D35'))));
    });

    test('a line pinned before the seed splits the run: the smaller part '
        'stays', () {
      // The old seed skipped C50 (already pinned), so the lines after it sit
      // one place higher than the ones before it.
      final mine = opening(
        kSpaceRetiredDefaultOpenings[2],
      ).copyWith(id: 'server', sortIndex: 2);
      final rows = seededOld([mine]);
      final trim = planSpaceDefaultTrim(rows).map((s) => s.key).toSet();
      expect(trim, {
        for (final o in kSpaceRetiredDefaultOpenings.skip(3)) opening(o).key,
      });
    });

    test('a new account has nothing to give back', () {
      final rows = [
        ...SpaceShortcutsNotifier.planSeed(const [], spaceSeedDrafts()),
      ];
      expect(rows, hasLength(4));
      expect(planSpaceDefaultTrim(rows), isEmpty);
      expect(planSpaceDefaultTrim(const []), isEmpty);
    });

    test('no shared anchor, or a tie, takes nothing', () {
      final rows = seededOld();
      SpaceShortcut at(String eco, double sort) =>
          rows.firstWhere((s) => s.key == keyOf(eco)).copyWith(sortIndex: sort);
      // Two pairs, each agreeing only with itself.
      final tie = [at('D35', -30), at('B90', -31), at('C50', 5), at('C65', 4)];
      expect(planSpaceDefaultTrim(tie), isEmpty);
      // One row alone proves nothing.
      expect(planSpaceDefaultTrim([rows[4]]), isEmpty);
    });
  });

  test('seed tags survive the round trip older builds ignore', () {
    final s = spaceSeedDrafts().first;
    final back = SpaceShortcut.fromJson(s.toJson())!;
    expect(isSpaceSeeded(back), isTrue);
    expect(back.params[kSpaceSeedParam], kSpaceSeedTag);
  });
}
