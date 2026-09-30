import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_builder_sheet.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart'
    show smartEventSpaceDraft;
import 'package:chessever2/screens/group_event/widget/filter_popup/event_filter_matching.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_state.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/group_event_filter_provider.dart';
import 'package:chessever2/screens/my_space/defaults/space_defaults.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/game_filter/rating_tier_filter.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:flutter/material.dart' show RangeValues;
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Every subset of [values], the empty one included.
List<Set<String>> _subsets(List<String> values) => [
  for (var mask = 0; mask < 1 << values.length; mask++)
    {
      for (var i = 0; i < values.length; i++)
        if (mask & (1 << i) != 0) values[i],
    },
];

/// The dialog's taps, in the dialog's own terms, on one filter provider.
FilterPopupState _apply(
  ProviderContainer container, {
  required bool builder,
  required Set<String> picks,
  required int? level,
  required GameEcoFilter eco,
}) {
  if (!builder) {
    final dialog = container.read(filterPopupProvider.notifier)
      ..setState(defaultFilterPopupState);
    for (final raw in picks) {
      dialog.toggleFormatOrState(raw);
    }
    dialog
      ..setMinimumElo(level)
      ..setEco(eco);
    return container.read(filterPopupProvider);
  }
  final notifier = container.read(smartEventBuilderFilterProvider.notifier);
  for (final raw in picks) {
    notifier.toggleFormatOrState(raw);
  }
  notifier
    ..setMinimumElo(level)
    ..setEco(eco);
  return container.read(smartEventBuilderFilterProvider);
}

GroupBroadcast _broadcast(String id, String? timeControl, int? elo) =>
    GroupBroadcast(
      id: id,
      createdAt: DateTime.utc(2026, 9, 1),
      name: id,
      search: const [],
      timeControl: timeControl,
      maxAvgElo: elo,
    );

void main() {
  test('the builder offers exactly the dialog\'s options', () {
    expect(
      kSmartBuilderStatuses.map((s) => s.name).toSet(),
      EventStatus.values.map((s) => s.name).toSet(),
    );
    expect(
      kSmartBuilderFormats.map((f) => f.name).toSet(),
      EventFormat.values.map((f) => f.name).toSet(),
    );
    expect(kSmartBuilderFormats, hasLength(EventFormat.values.length));
    expect(kSmartBuilderLevels, [
      null,
      for (final tier in RatingTierFilter.tiers) tier.minRating,
    ]);
  });

  test('every opening the dialog can pick is in the builder\'s browser', () {
    final dialog = browseOpeningSuggestions();
    final nodes = <SmartBuilderOpeningNode>[];
    void walk(List<SmartBuilderOpeningNode> level) {
      for (final n in level) {
        nodes.add(n);
        walk(n.children);
      }
    }

    smartBuilderOpeningTree.values.forEach(walk);
    expect(nodes, hasLength(dialog.length));
    expect(
      nodes.map((n) => n.suggestion.filter).toSet(),
      dialog.map((s) => s.filter).toSet(),
    );
    // Five ECO groups, each nested under the smallest family holding it.
    expect(smartBuilderOpeningTree.keys.toSet(), {'A', 'B', 'C', 'D', 'E'});
    final najdorf = nodes.firstWhere((n) => n.id == 'B9');
    expect(najdorf.parent?.id, 'B20-B99');
    expect(najdorf.children.map((n) => n.id), [
      for (var i = 0; i < 10; i++) 'B9$i',
    ]);

    // Search is the dialog's search, so it can only reach the same options.
    final browsable = dialog.map((s) => s.filter).toSet();
    for (final query in ['najdorf', 'kings indian', 'B97', 'C42', 'ruy']) {
      for (final s in searchOpeningSuggestions(query, limit: 80)) {
        expect(browsable, contains(s.filter), reason: '$query ${s.id}');
      }
    }
  });

  test('every combination builds the same Smart Event as the dialog', () {
    final statuses = [for (final s in EventStatus.values) s.name];
    final formats = [for (final f in EventFormat.values) f.name];
    final ecos = [
      GameEcoFilter.all,
      GameEcoFilter.forFamily('B9'),
      GameEcoFilter.forCode('B97'),
      GameEcoFilter.forFamily('E6+E7+E8+E9'),
      GameEcoFilter.forCode('C42'),
    ];
    final broadcasts = [
      _broadcast('live-classical', 'standard', 2710),
      _broadcast('live-rapid', 'rapid 15+10', 2450),
      _broadcast('done-blitz', 'Blitz', 2320),
      _broadcast('done-unrated', 'classical', null),
      _broadcast('done-bullet', 'bullet', 2100),
      _broadcast('live-unknown', null, 2550),
    ];
    const liveIds = ['live-classical', 'live-rapid', 'live-unknown'];

    var combos = 0;
    for (final status in _subsets(statuses)) {
      for (final format in _subsets(formats)) {
        for (final level in kSmartBuilderLevels) {
          for (final eco in ecos) {
            combos++;
            final picks = {...status, ...format};
            final container = ProviderContainer();
            addTearDown(container.dispose);
            final fromDialog = _apply(
              container,
              builder: false,
              picks: picks,
              level: level,
              eco: eco,
            );
            final fromBuilder = _apply(
              container,
              builder: true,
              picks: picks,
              level: level,
              eco: eco,
            );
            final why = '$picks level=$level eco=${eco.code}';
            expect(fromBuilder, fromDialog, reason: why);

            // The builder remembers the picked line; the dialog does not.
            final opening = eco.isAll
                ? null
                : OpeningSearchSelection.forFilter(eco);
            final built = smartEventBuilderRequest(
              fromBuilder,
              opening: opening,
            );
            final dialog = smartEventRequestFromFilterState(fromDialog);
            expect(built == null, dialog == null, reason: why);
            if (built == null || dialog == null) continue;

            expect(built.criteriaKey, dialog.criteriaKey, reason: why);
            expect(built.criteria, dialog.criteria, reason: why);
            expect(built.displayName, dialog.displayName, reason: why);
            expect(built.favoriteEventId, dialog.favoriteEventId, reason: why);
            expect(
              smartEventSpaceDraft(built).key,
              smartEventSpaceDraft(dialog).key,
              reason: why,
            );
            expect(
              built.criteria.toPopupState(),
              dialog.criteria.toPopupState(),
              reason: why,
            );

            final a = smartEventFetchScopeFor(
              SmartEventGamesQuery(request: built),
            );
            final b = smartEventFetchScopeFor(
              SmartEventGamesQuery(request: dialog),
            );
            expect(a.liveOnly, b.liveOnly, reason: why);
            expect(a.completedOnly, b.completedOnly, reason: why);
            expect(a.minGameAverageElo, b.minGameAverageElo, reason: why);
            expect(a.maxGameAverageElo, b.maxGameAverageElo, reason: why);
            expect(a.eventTimeControls, b.eventTimeControls, reason: why);

            List<String> members(SmartEventRequest r) =>
                filterBroadcastsByPopupState(
                  broadcasts,
                  r.criteria.toPopupState(),
                  liveIds: liveIds,
                ).map((g) => g.id).toList();
            expect(members(built), members(dialog), reason: why);
          }
        }
      }
    }
    expect(combos, 4 * 8 * 5 * 5);
  });

  test('a lone level or time control is the seeded preset itself', () {
    final gm = smartEventBuilderRequest(
      defaultFilterPopupState.copyWith(
        eloRange: const RangeValues(2500, kFilterMaxElo),
      ),
    );
    expect(identical(gm, kSpaceSmartLevelPresets.first), isTrue);
    final classical = smartEventBuilderRequest(
      defaultFilterPopupState.copyWith(formatsAndStates: {'standard'}),
    );
    expect(identical(classical, kSpaceSmartFormatPresets.first), isTrue);
    expect(smartEventBuilderRequest(defaultFilterPopupState), isNull);
  });

  test('an opening keeps the picked line so the event can explain it', () {
    final najdorf = searchOpeningSuggestions(
      'najdorf',
      limit: 10,
    ).firstWhere((s) => s.isFamily);
    final alone = smartEventBuilderRequest(
      defaultFilterPopupState.copyWith(eco: najdorf.filter),
      opening: najdorf.selection,
    )!;
    final search = SmartEventRequest.forOpeningSelection(najdorf.selection);
    expect(alone.criteriaKey, search.criteriaKey);
    expect(alone.caption, search.caption);
    expect(alone.openingContext, search.openingContext);

    final combined = smartEventBuilderRequest(
      defaultFilterPopupState.copyWith(
        formatsAndStates: {'blitz'},
        eloRange: const RangeValues(2500, kFilterMaxElo),
        eco: najdorf.filter,
      ),
      opening: najdorf.selection,
    )!;
    expect(combined.criteriaKey, '2500-3200:blitz:eco=B9');
    expect(combined.openingContext, isNotNull);
  });

  test('the summary names every pick, and names never have to', () {
    final state = defaultFilterPopupState.copyWith(
      formatsAndStates: {'live', 'blitz'},
      eloRange: const RangeValues(2500, kFilterMaxElo),
      eco: GameEcoFilter.forFamily('B9'),
    );
    // The shared naming drops "Live" next to a level; the line keeps it.
    expect(
      smartEventBuilderRequest(state)!.displayName,
      'GM Sicilian: Najdorf',
    );
    expect(
      smartEventBuilderSummary(state),
      'Game average 2500+, blitz, live events, B90–B99',
    );
    expect(
      smartEventBuilderSummary(
        defaultFilterPopupState.copyWith(
          formatsAndStates: {'standard', 'rapid', 'blitz', 'live', 'completed'},
        ),
      ),
      'Classical, rapid or blitz, live or completed events',
    );
    expect(smartEventBuilderSummary(defaultFilterPopupState), isNull);
  });
}
