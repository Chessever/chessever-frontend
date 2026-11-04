import 'dart:async';

import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/screens/group_event/smart_event/saved_smart_event_editor.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_shortcut.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/utils/confirmed_saved_row_edit.dart';
import 'package:chessever2/utils/smart_event_mutation.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'helpers/saved_smart_event_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(installSavedEventFixtureCache);
  late SavedRowsTransport transport;
  late FixturePins pins;
  late FixtureFavorites favorites;
  late ProviderContainer container;
  late SavedSmartEventEditor editor;
  final old = fixtureRequest();
  final unrelated = fixtureFavorite(
    old.withTierSelection('CM'),
    name: 'Another subscription',
  );
  final changes = <String, SmartEventRequest>{
    'pace': old.withGameFilterOverrides(
      GameFilter(timeControl: GameTimeControlFilter.rapid),
    ),
    'opening': old.withGameFilterOverrides(
      GameFilter(eco: GameEcoFilter.forCode('B90')),
    ),
    'tier': old.withTierSelection('GM'),
    'clear opening and pace': old
        .withGameFilterOverrides(GameFilter())
        .withTierSelection('All'),
  };

  Future<void> setup({
    bool starred = true,
    List<FavoriteEvent>? rows,
    List<SpaceShortcut>? cards,
    bool wait = true,
  }) async {
    transport = SavedRowsTransport(
      rows ?? [if (starred) fixtureFavorite(old), unrelated],
    );
    pins = FixturePins(cards ?? [fixturePin(old)]);
    favorites = FixtureFavorites(transport);
    if (!wait) {
      pins.ready = Completer();
      favorites.ready = Completer();
    }
    container = ProviderContainer(
      overrides: [
        favoriteEventsProvider.overrideWith(() => favorites),
        spaceShortcutsProvider.overrideWith(() => pins),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await transport.client.dispose();
    });
    editor = SavedSmartEventEditor(container);
    if (wait) {
      await Future.wait([
        container.read(favoriteEventsProvider.future),
        container.read(spaceShortcutsProvider.future),
      ]);
    }
  }

  for (final entry in changes.entries) {
    for (final starred in [true, false]) {
      test(
        '${entry.key} updates the real saved card, starred=$starred',
        () async {
          await setup(starred: starred);
          await editor.apply(old, entry.value);
          final cards = container.read(spaceShortcutsProvider).requireValue;
          expect(cards, hasLength(1));
          expect(cards.single.targetId, entry.value.criteriaKey);
          expect(
            smartEventRequestFromSpaceShortcut(cards.single)!.criteriaKey,
            entry.value.criteriaKey,
          );
          expect(cards.single.sortIndex, 8);
          expect(cards.single.openCount, 4);
          expect(cards.single.params['customFlag'], 'kept');
          expect(
            matchingSmartEventFavorites(transport.favorites, old.criteriaKey),
            isEmpty,
          );
          final updated = matchingSmartEventFavorites(
            transport.favorites,
            entry.value.criteriaKey,
          );
          expect(updated, hasLength(starred ? 1 : 0));
          if (starred) {
            expect(updated.single.eventId, entry.value.favoriteEventId);
            expect(updated.single.metadata['customFlag'], 'kept');
            expect(
              SmartEventRequest.fromFavoriteEvent(updated.single).criteriaKey,
              cards.single.targetId,
            );
          }
          expect(
            transport.favorites.any((r) => r.eventId == unrelated.eventId),
            isTrue,
          );
        },
      );
    }
  }

  test(
    'clearing a saved opening removes obsolete ECO and opening context metadata',
    () async {
      final opening = SmartEventRequest.forOpening(
        GameEcoFilter.forCode('B90'),
      );
      final updated = opening.withGameFilterOverrides(
        GameFilter(timeControl: GameTimeControlFilter.rapid),
      );
      await setup(
        rows: [fixtureFavorite(opening)],
        cards: [fixturePin(opening)],
      );
      await editor.apply(opening, updated);
      expect(
        transport.favorites.single.metadata.containsKey('ecoCode'),
        isFalse,
      );
      expect(
        transport.favorites.single.metadata.containsKey('openingContext'),
        isFalse,
      );
      expect(
        smartEventRequestFromSpaceShortcut(
          container.read(spaceShortcutsProvider).requireValue.single,
        )!.eco.isAll,
        isTrue,
      );
    },
  );

  test(
    'custom title, metadata, order and history survive a criteria edit',
    () async {
      await setup(
        rows: [
          fixtureFavorite(old, name: 'Club study'),
          unrelated,
        ],
        cards: [
          fixturePin(old).copyWith(title: 'Club study', subtitle: 'My note'),
        ],
      );
      await editor.apply(old, changes['pace']!);
      final card = container.read(spaceShortcutsProvider).requireValue.single;
      expect(card.title, 'Club study');
      expect(card.subtitle, 'My note');
      expect(card.lastOpenedAt, fixtureStamp);
      expect(transport.favorites.first.eventName, 'Club study');
    },
  );

  test(
    'existing target pin and subscription win without duplicate or unrelated deletion',
    () async {
      final target = changes['pace']!;
      final targetFavorite = fixtureFavorite(target, name: 'Keep target title');
      final targetPin = fixturePin(
        target,
      ).copyWith(id: 'local:target', title: 'Keep card', sortIndex: 19);
      await setup(
        rows: [fixtureFavorite(old), targetFavorite, unrelated],
        cards: [fixturePin(old), targetPin],
      );
      await editor.apply(old, target);
      expect(container.read(spaceShortcutsProvider).requireValue, [targetPin]);
      expect(transport.favorites.map((r) => r.eventName), [
        'Keep target title',
        'Another subscription',
      ]);
      expect(transport.writes, ['DELETE:user_favorite_events']);
    },
  );

  test(
    'unstarred source does not unstar an independently starred target',
    () async {
      final target = changes['pace']!;
      await setup(rows: [fixtureFavorite(target), unrelated]);
      await editor.apply(old, target);
      expect(transport.writes, isEmpty);
      expect(
        matchingSmartEventFavorites(transport.favorites, target.criteriaKey),
        hasLength(1),
      );
    },
  );

  test(
    'legacy criteria matches are migrated, including duplicate old aliases only',
    () async {
      await setup(
        rows: [
          fixtureFavorite(old, eventId: 'smart_event:legacy-a'),
          fixtureFavorite(old, eventId: 'smart_event:legacy-b'),
          unrelated,
        ],
      );
      await editor.apply(old, changes['pace']!);
      expect(
        matchingSmartEventFavorites(transport.favorites, old.criteriaKey),
        isEmpty,
      );
      expect(
        matchingSmartEventFavorites(
          transport.favorites,
          changes['pace']!.criteriaKey,
        ),
        hasLength(1),
      );
      expect(transport.favorites, hasLength(2));
    },
  );

  test(
    'absent pin is never recreated while an existing subscription changes',
    () async {
      await setup(cards: []);
      await editor.apply(old, changes['pace']!);
      expect(container.read(spaceShortcutsProvider).requireValue, isEmpty);
      expect(
        matchingSmartEventFavorites(
          transport.favorites,
          changes['pace']!.criteriaKey,
        ),
        hasLength(1),
      );
    },
  );

  test('absent pin and subscription stay absent', () async {
    await setup(starred: false, cards: []);
    await editor.apply(old, changes['pace']!);
    expect(transport.writes, isEmpty);
    expect(container.read(spaceShortcutsProvider).requireValue, isEmpty);
  });

  test(
    'cache loading is awaited before deciding whether the saved event is starred',
    () async {
      await setup(wait: false);
      final pending = editor.apply(old, changes['pace']!);
      await Future<void>.delayed(Duration.zero);
      expect(transport.writes, isEmpty);
      expect(container.read(smartEventMutationBusyProvider), isTrue);
      pins.ready!.complete();
      favorites.ready!.complete();
      await pending;
      expect(
        matchingSmartEventFavorites(
          transport.favorites,
          changes['pace']!.criteriaKey,
        ),
        hasLength(1),
      );
      expect(container.read(smartEventMutationBusyProvider), isFalse);
    },
  );

  test(
    'concurrent edit is rejected instead of applying stale criteria twice',
    () async {
      await setup(wait: false);
      final pending = editor.apply(old, changes['pace']!);
      await expectLater(editor.apply(old, changes['tier']!), throwsStateError);
      pins.ready!.complete();
      favorites.ready!.complete();
      await pending;
      expect(
        matchingSmartEventFavorites(
          transport.favorites,
          changes['tier']!.criteriaKey,
        ),
        isEmpty,
      );
    },
  );

  for (final lostReply in [false, true]) {
    test(
      'favorite write failure (lost reply=$lostReply) compensates and can retry',
      () async {
        await setup();
        var fail = true;
        Future<void> fault(dynamic _) async {
          if (fail) {
            fail = false;
            throw StateError('Fixture offline');
          }
        }

        if (lostReply) {
          transport.afterWrite = fault;
        } else {
          transport.beforeWrite = fault;
        }
        await expectLater(
          editor.apply(old, changes['pace']!),
          throwsA(
            isA<SmartEventSaveFailure>().having(
              (e) => e.recoveryRequired,
              'rollback',
              false,
            ),
          ),
        );
        expect(
          matchingSmartEventFavorites(transport.favorites, old.criteriaKey),
          hasLength(1),
        );
        expect(
          container.read(spaceShortcutsProvider).requireValue.single.targetId,
          old.criteriaKey,
        );
        await editor.apply(old, changes['pace']!);
        expect(
          matchingSmartEventFavorites(transport.favorites, old.criteriaKey),
          isEmpty,
        );
      },
    );
  }

  for (final afterCommit in [false, true]) {
    test(
      'shortcut failure (after local commit=$afterCommit) restores favorite/card and retries',
      () async {
        await setup();
        var fail = true;
        Future<void> fault(SpaceShortcut? _, SpaceShortcut? __) async {
          if (fail) {
            fail = false;
            throw StateError('Fixture card failure');
          }
        }

        if (afterCommit) {
          pins.afterWrite = fault;
        } else {
          pins.beforeWrite = fault;
        }
        await expectLater(
          editor.apply(old, changes['pace']!),
          throwsA(
            isA<SmartEventSaveFailure>().having(
              (e) => e.recoveryRequired,
              'rollback',
              false,
            ),
          ),
        );
        expect(
          container.read(spaceShortcutsProvider).requireValue.single.targetId,
          old.criteriaKey,
        );
        expect(
          matchingSmartEventFavorites(transport.favorites, old.criteriaKey),
          hasLength(1),
        );
        await editor.apply(old, changes['pace']!);
        expect(
          container.read(spaceShortcutsProvider).requireValue.single.targetId,
          changes['pace']!.criteriaKey,
        );
      },
    );
  }

  test(
    'compensation failure is explicit; retry recovers journal before applying',
    () async {
      await setup();
      var failPin = true;
      pins.beforeWrite = (_, _) async {
        if (failPin) {
          failPin = false;
          transport.beforeWrite = (_) async =>
              throw StateError('Fixture rollback offline');
          throw StateError('Fixture card offline');
        }
      };
      await expectLater(
        editor.apply(old, changes['pace']!),
        throwsA(
          isA<SmartEventSaveFailure>().having(
            (e) => e.recoveryRequired,
            'partial state surfaced',
            true,
          ),
        ),
      );
      pins.beforeWrite = null;
      transport.beforeWrite = null;
      await editor.apply(old, changes['pace']!);
      expect(
        matchingSmartEventFavorites(transport.favorites, old.criteriaKey),
        isEmpty,
      );
      expect(
        matchingSmartEventFavorites(
          transport.favorites,
          changes['pace']!.criteriaKey,
        ),
        hasLength(1),
      );
    },
  );

  test(
    'guarded remote write refuses concurrent changes without overwriting them',
    () async {
      await setup();
      final before = {
        'event_id': unrelated.eventId,
        'event_name': 'stale name',
        'metadata': unrelated.metadata,
      };
      await expectLater(
        writeConfirmedSavedRow(
          client: transport.client,
          userId: fixtureOwner,
          table: 'user_favorite_events',
          keyColumns: const ['event_id'],
          before: before,
          after: null,
        ),
        throwsA(isA<SavedRowConflict>()),
      );
      expect(transport.writes, isEmpty);
      expect(
        transport.favorites.any((r) => r.eventId == unrelated.eventId),
        isTrue,
      );
    },
  );

  test(
    'an account switch refuses old-screen saves without writing the other account',
    () async {
      await setup();
      await editor.apply(old, changes['pace']!);
      final count = transport.writes.length;
      favorites.actor = 'different-fixture-owner';
      await expectLater(
        editor.apply(changes['pace']!, changes['tier']!),
        throwsStateError,
      );
      expect(transport.writes.length, count);
      expect(container.read(smartEventMutationBusyProvider), isFalse);
    },
  );

  test(
    'multiple legacy pins of the edited criteria collapse without touching other cards',
    () async {
      final legacy = SpaceShortcut.fromJson({
        ...fixturePin(old).toJson(),
        'id': 'local:legacy-pin',
        'target_id': 'legacy-key',
      })!;
      final other = fixturePin(
        old.withTierSelection('CM'),
      ).copyWith(id: 'local:other');
      await setup(cards: [fixturePin(old), legacy, other]);
      await editor.apply(old, changes['pace']!);
      final cards = container.read(spaceShortcutsProvider).requireValue;
      expect(cards, hasLength(2));
      expect(
        cards.where((s) => s.targetId == changes['pace']!.criteriaKey),
        hasLength(1),
      );
      expect(cards.where((s) => s.key == other.key), hasLength(1));
    },
  );

  test(
    'local removal/reorder while awaiting edit is not resurrected or overwritten',
    () async {
      await setup(starred: false);
      final before = container.read(spaceShortcutsProvider).requireValue.single;
      await pins.remove(before.id);
      await expectLater(
        pins.writeSmartEventEdit(
          before,
          retargetSmartEventShortcut(before, old, changes['pace']!),
        ),
        throwsA(isA<SavedRowConflict>()),
      );
      expect(container.read(spaceShortcutsProvider).requireValue, isEmpty);
    },
  );
}
