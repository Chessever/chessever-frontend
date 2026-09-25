import 'dart:async';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/space_database.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_rounds_id_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

SpaceShortcut _s(SpaceShortcutKind kind, String id, {double sort = 0}) =>
    SpaceShortcut(
      id: 'id-$id',
      kind: kind,
      targetId: id,
      title: id,
      sortIndex: sort,
    );

class _Store extends SpaceShortcutsNotifier {
  _Store(this.seed);

  final List<SpaceShortcut> seed;

  @override
  Future<List<SpaceShortcut>> build() async => seed;
}

class _NoFavorites extends FavoritePlayersNotifierNew {
  @override
  Future<List<FavoritePlayer>> build() async => const [];
}

void main() {
  group('spaceDatabaseGroups', () {
    test('groups by type in page order, empty groups left out', () {
      final groups = spaceDatabaseGroups([
        _s(SpaceShortcutKind.smartEvent, 'smart'),
        _s(SpaceShortcutKind.link, 'https://chessever.com/x'),
        _s(SpaceShortcutKind.folder, 'db'),
        _s(SpaceShortcutKind.opening, 'C67'),
        _s(SpaceShortcutKind.game, 'g1'),
        _s(SpaceShortcutKind.player, '1503014'),
        _s(SpaceShortcutKind.event, 'ev'),
        _s(SpaceShortcutKind.miniatures, 'today'),
        _s(SpaceShortcutKind.position, 'fen'),
        _s(SpaceShortcutKind.countrymen, 'IN'),
        _s(SpaceShortcutKind.round, 'r7'),
      ]);
      expect(
        [for (final g in groups) g.section],
        [
          SpaceSection.events,
          SpaceSection.players,
          SpaceSection.games,
          SpaceSection.openings,
          SpaceSection.library,
          SpaceSection.links,
          SpaceSection.smartEvents,
        ],
      );
      expect([for (final s in groups[0].items) s.targetId], ['ev', 'r7']);
      expect([for (final s in groups[1].items) s.targetId], ['1503014', 'IN']);
      expect([for (final s in groups[4].items) s.targetId], ['db', 'today']);
    });

    test('keeps store order inside a group', () {
      final groups = spaceDatabaseGroups([
        _s(SpaceShortcutKind.event, 'c'),
        _s(SpaceShortcutKind.player, 'p'),
        _s(SpaceShortcutKind.event, 'a'),
        _s(SpaceShortcutKind.event, 'b'),
      ]);
      expect([for (final s in groups.first.items) s.targetId], ['c', 'a', 'b']);
    });

    test('My Likes and (while streaks are hidden) streak pins stay out', () {
      final groups = spaceDatabaseGroups([
        _s(SpaceShortcutKind.likes, 'me'),
        _s(SpaceShortcutKind.streak, '1503014'),
      ]);
      expect(groups, isEmpty);
    });

    test('live events lead their group, each class in store order', () {
      final list = [
        _s(SpaceShortcutKind.event, 'a'),
        _s(SpaceShortcutKind.event, 'b'),
        _s(SpaceShortcutKind.round, 'r'),
        _s(SpaceShortcutKind.event, 'c'),
      ];
      final live = spaceLiveKeys(
        list,
        liveEventIds: const ['c', 'b'],
        liveRoundIds: const ['r'],
      );
      final groups = spaceDatabaseGroups(list, liveFirst: live);
      expect(
        [for (final s in groups.first.items) s.targetId],
        ['b', 'r', 'c', 'a'],
      );
    });
  });

  test('the Players group takes the players My Space shows, follows '
      'included, in place of its pins alone', () {
    final groups = spaceDatabaseGroups(
      [_s(SpaceShortcutKind.player, 'p1'), _s(SpaceShortcutKind.event, 'e')],
      players: [
        _s(SpaceShortcutKind.player, 'f1'),
        _s(SpaceShortcutKind.player, 'p1'),
      ],
    );
    expect([for (final g in groups) g.section], [
      SpaceSection.events,
      SpaceSection.players,
    ]);
    expect([for (final s in groups[1].items) s.targetId], ['f1', 'p1']);
    // Follows alone make a Players group with no pin at all.
    expect(
      spaceDatabaseGroups(
        const [],
        players: [_s(SpaceShortcutKind.player, 'f1')],
      ).single.section,
      SpaceSection.players,
    );
  });

  group('live-first latch', () {
    late ProviderContainer container;
    late StreamController<List<String>> liveEvents;

    setUp(() {
      liveEvents = StreamController<List<String>>.broadcast();
      container = ProviderContainer(
        overrides: [
          spaceShortcutsProvider.overrideWith(
            () => _Store([
              _s(SpaceShortcutKind.event, 'a'),
              _s(SpaceShortcutKind.event, 'b'),
            ]),
          ),
          liveGroupBroadcastIdsProvider.overrideWith(
            (ref) => liveEvents.stream,
          ),
          liveRoundsIdProvider.overrideWith(
            (ref) => Stream.value(const <String>[]),
          ),
          currentUserProvider.overrideWithValue(null),
          favoritePlayersProviderNew.overrideWith(_NoFavorites.new),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(liveEvents.close);
    });

    List<String> order() => [
      for (final s in container.read(spaceDatabaseGroupsProvider)!.first.items)
        s.targetId,
    ];

    test('holds its order when an event goes live after the latch; a '
        'refresh (a cleared latch) reorders', () async {
      final sub = container.listen(spaceDatabaseGroupsProvider, (_, _) {});
      addTearDown(sub.close);
      await container.read(spaceShortcutsProvider.future);
      liveEvents.add(const []);
      await Future<void>.delayed(Duration.zero);
      expect(order(), ['a', 'b']);

      // The page takes the latch once both feeds have answered.
      container.read(spaceLiveFirstLatchProvider.notifier).state = const {};
      liveEvents.add(const ['b']);
      await Future<void>.delayed(Duration.zero);
      expect(order(), ['a', 'b'], reason: 'no jump under the reader');

      // Pull to refresh clears the latch: live first again.
      container.read(spaceLiveFirstLatchProvider.notifier).state = null;
      await Future<void>.delayed(Duration.zero);
      expect(order(), ['b', 'a']);
    });
  });
}
