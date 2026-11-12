import 'dart:async';

import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event_id.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_category_ordering.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_repo_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_ads.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The synthetic "Combined" category of the tournament-detail picker.
///
/// An event with several categories (Group A-D, Open/Women, Masters/
/// Challengers) makes a viewer switch back and forth to follow all of them.
/// Combined is a client-side category that lists every real category's games
/// in one Games tab. It never exists in the database: it reuses each
/// category's own games provider, so nothing is fetched twice. An organizer's
/// own Combined section is never merged in, so no board is listed twice.
///
/// Premium only. The choice is remembered per event.

/// Label shown for the synthetic category in the picker and on the chip.
const String kCombinedCategoryLabel = 'Combined';

/// Analytics/paywall identifier for the feature.
const String kCombinedCategoryFeatureId = 'combined_category';

final RegExp _combinedLabel = RegExp(r'(^|[^a-z0-9])combined([^a-z0-9]|$)');

/// Whether a tour is an organizer-published "Combined" section, which repeats
/// the boards of the real sections beside it (Total Chess "Group Stage
/// Combined"). Same rule as the server's `tour_label_is_combined`.
bool isCombinedSectionLabel({String? name, String? slug}) =>
    _combinedLabel.hasMatch('${name ?? ''} ${slug ?? ''}'.toLowerCase());

/// One real category merged into Combined.
@immutable
class CombinedCategory {
  const CombinedCategory({
    required this.tourId,
    required this.label,
    required this.avgElo,
    required this.order,
    this.startsAt,
  });

  final String tourId;

  /// The category as the picker names it ("Group A").
  final String label;
  final int? avgElo;

  /// Position in the picker, used as the last ordering tie-break.
  final int order;

  /// When the category begins. Between two equally rated categories the one
  /// that starts later reads first.
  final DateTime? startsAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CombinedCategory &&
          other.tourId == tourId &&
          other.label == label &&
          other.avgElo == avgElo &&
          other.order == order &&
          other.startsAt == startsAt;

  @override
  int get hashCode => Object.hash(tourId, label, avgElo, order, startsAt);
}

/// The categories Combined merges for one event. Value-equal, so a metadata
/// refresh that changes nothing here does not rebuild the combined list.
@immutable
class CombinedCategories {
  const CombinedCategories(this.items);

  static const none = CombinedCategories(<CombinedCategory>[]);

  /// Picks the real categories out of [tours].
  ///
  /// An organizer's own Combined section is left out: it mirrors the others,
  /// so merging it would list every board twice. It is recognised by the
  /// database's mirror flag or by its name. With no real section beside it, a
  /// tour that merely has "combined" in its name is an ordinary category and
  /// stays. A mirror nobody flagged or named is still caught later, from its
  /// boards (see `findMirrorTourIds`).
  factory CombinedCategories.fromTours(
    List<TourModel> tours, {
    String? groupName,
  }) {
    final real = [
      for (final model in tours)
        if (!model.tour.isMirror &&
            !isCombinedSectionLabel(
              name: model.tour.name,
              slug: model.tour.slug,
            ))
          model,
    ];
    final source = real.isEmpty ? tours : real;
    return CombinedCategories(
      List<CombinedCategory>.unmodifiable([
        for (var i = 0; i < source.length; i++)
          CombinedCategory(
            tourId: source[i].tour.id,
            label: tourCategoryLabel(source[i].tour.name, groupName: groupName),
            avgElo: source[i].tour.avgElo,
            order: i,
            startsAt: source[i].tour.dates.isEmpty
                ? null
                : source[i].tour.dates.first,
          ),
      ]),
    );
  }

  final List<CombinedCategory> items;

  /// Combined only means something with at least two categories to merge.
  bool get canCombine => items.length >= 2;

  List<String> get tourIds => [for (final item in items) item.tourId];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CombinedCategories && listEquals(other.items, items);

  @override
  int get hashCode => Object.hashAll(items);
}

/// What the user decided about Combined, per event.
@immutable
class CombinedCategoryPrefs {
  const CombinedCategoryPrefs({
    this.selected = const <String>{},
    this.answered = const <String>{},
    this.loaded = const <String>{},
    this.neverAsk = false,
  });

  /// Events (group broadcast ids) opened in Combined.
  final Set<String> selected;

  /// Events whose "combine?" question was already answered.
  final Set<String> answered;

  /// Events whose stored answers have been read.
  final Set<String> loaded;

  /// "Never ask" from the question: no event asks again.
  final bool neverAsk;

  bool isSelected(String groupId) => selected.contains(groupId);

  /// Whether opening [groupId] should ask "combine?". False until the stored
  /// answers are read, so the question never flashes before a saved "no".
  bool shouldAsk(String groupId) =>
      loaded.contains(groupId) &&
      !neverAsk &&
      !answered.contains(groupId) &&
      !selected.contains(groupId);

  CombinedCategoryPrefs copyWith({
    Set<String>? selected,
    Set<String>? answered,
    Set<String>? loaded,
    bool? neverAsk,
  }) => CombinedCategoryPrefs(
    selected: selected ?? this.selected,
    answered: answered ?? this.answered,
    loaded: loaded ?? this.loaded,
    neverAsk: neverAsk ?? this.neverAsk,
  );
}

class CombinedCategoryPrefsNotifier
    extends StateNotifier<CombinedCategoryPrefs> {
  CombinedCategoryPrefsNotifier(this._store)
    : super(const CombinedCategoryPrefs());

  static const neverAskKey = 'combined_category_never_ask';
  static String selectedKey(String groupId) => 'combined_category_$groupId';
  static String answeredKey(String groupId) =>
      'combined_category_asked_$groupId';

  final TourSelectionStore _store;
  final Map<String, Future<void>> _loads = <String, Future<void>>{};

  // A choice made while the stored value is still being read wins over it.
  final Set<String> _selectionTouched = <String>{};

  /// Reads the stored answers for [groupId] once per app session.
  Future<void> ensureLoaded(String groupId) {
    if (groupId.isEmpty) return Future<void>.value();
    return _loads.putIfAbsent(groupId, () => _load(groupId));
  }

  Future<void> _load(String groupId) async {
    String? selected;
    String? answered;
    String? never;
    try {
      final values = await Future.wait<String?>([
        _store.getString(selectedKey(groupId)),
        _store.getString(answeredKey(groupId)),
        _store.getString(neverAskKey),
      ]);
      selected = values[0];
      answered = values[1];
      never = values[2];
    } catch (_) {
      // Unreadable storage means "nothing saved": the event opens normally.
    }
    if (!mounted) return;
    final touched = _selectionTouched.contains(groupId);
    state = state.copyWith(
      selected: !touched && selected == '1'
          ? {...state.selected, groupId}
          : state.selected,
      answered: answered == '1' ? {...state.answered, groupId} : state.answered,
      loaded: {...state.loaded, groupId},
      neverAsk: state.neverAsk || never == '1',
    );
  }

  /// Opens (or leaves) Combined for [groupId]. Choosing it also answers the
  /// question for that event.
  Future<void> setSelected(String groupId, bool selected) async {
    if (groupId.isEmpty) return;
    _selectionTouched.add(groupId);
    if (selected == state.isSelected(groupId) &&
        (!selected || state.answered.contains(groupId))) {
      return;
    }
    state = state.copyWith(
      selected: selected
          ? {...state.selected, groupId}
          : ({...state.selected}..remove(groupId)),
      answered: selected ? {...state.answered, groupId} : state.answered,
    );
    try {
      if (selected) {
        await Future.wait([
          _store.setString(selectedKey(groupId), '1'),
          _store.setString(answeredKey(groupId), '1'),
        ]);
      } else {
        await _store.remove(selectedKey(groupId));
      }
    } catch (_) {
      // The session keeps the choice; only persistence was lost.
    }
  }

  /// The question was answered for [groupId]; it is not asked there again.
  Future<void> markAnswered(String groupId) async {
    if (groupId.isEmpty || state.answered.contains(groupId)) return;
    state = state.copyWith(answered: {...state.answered, groupId});
    try {
      await _store.setString(answeredKey(groupId), '1');
    } catch (_) {}
  }

  /// "Never ask": no event asks again. Combined stays in the picker.
  Future<void> setNeverAsk() async {
    if (state.neverAsk) return;
    state = state.copyWith(neverAsk: true);
    try {
      await _store.setString(neverAskKey, '1');
    } catch (_) {}
  }
}

/// App-scoped, so an answer survives leaving and re-entering an event.
final combinedCategoryPrefsProvider =
    StateNotifierProvider<CombinedCategoryPrefsNotifier, CombinedCategoryPrefs>(
      (ref) =>
          CombinedCategoryPrefsNotifier(ref.watch(tourSelectionStoreProvider)),
    );

/// The open event's id, as Combined keys its stored answers.
final combinedCategoryGroupIdProvider = Provider<String?>((ref) {
  final groupId = ref.watch(
    selectedBroadcastModelProvider.select((b) => b?.id),
  );
  if (groupId == null || groupId.isEmpty || isVirtualGamebaseId(groupId)) {
    return null;
  }
  return groupId;
});

/// The real categories of the open event. `canCombine` decides whether the
/// picker offers Combined at all.
final combinedCategoriesProvider = Provider<CombinedCategories>((ref) {
  if (ref.watch(combinedCategoryGroupIdProvider) == null) {
    return CombinedCategories.none;
  }
  final groupName = ref.watch(
    selectedBroadcastModelProvider.select((b) => b?.name),
  );
  final tours = ref.watch(
    tourDetailScreenProvider.select((state) => state.valueOrNull?.tours),
  );
  if (tours == null || tours.length < 2) return CombinedCategories.none;
  return CombinedCategories.fromTours(tours, groupName: groupName);
});

/// Whether the viewer may use Combined. Debug builds without rewarded ads
/// pass, matching `requirePremiumGuard`, so the feature is reachable while
/// developing.
final combinedCategoryEntitledProvider = Provider<bool>(
  (ref) =>
      (kDebugMode && !RewardedAdsConfig.available) ||
      ref.watch(premiumAccessProvider),
);

/// True while the open event is shown in Combined: the user chose it, the
/// event still has categories to merge, and Premium is active. A lapsed
/// subscription quietly falls back to the real category underneath.
final combinedCategorySelectedProvider = Provider<bool>((ref) {
  final groupId = ref.watch(combinedCategoryGroupIdProvider);
  if (groupId == null) return false;
  if (!ref.watch(combinedCategoriesProvider).canCombine) return false;
  if (!ref.watch(combinedCategoryEntitledProvider)) return false;
  return ref.watch(
    combinedCategoryPrefsProvider.select((prefs) => prefs.isSelected(groupId)),
  );
});

/// Whether [tourId] is a category the Combined list shows other than the one
/// selected underneath.
///
/// Everything outside the Games list still describes the selected category:
/// its games provider, its standings. A surface opened from a Combined game
/// (a player's score card above all) must ask for that game's own category
/// instead, or it comes up empty for every category but one.
final combinedOtherCategoryProvider = Provider.autoDispose.family<bool, String>(
  (ref, tourId) {
    if (tourId.isEmpty || !ref.watch(combinedCategorySelectedProvider)) {
      return false;
    }
    final selectedTourId = ref.watch(
      tourDetailScreenProvider.select(
        (state) => state.valueOrNull?.aboutTourModel.id,
      ),
    );
    return tourId != selectedTourId &&
        ref.watch(combinedCategoriesProvider).tourIds.contains(tourId);
  },
);

/// Tours whose games the Combined list is showing right now. Their games
/// providers poll at the combined cadence instead of the slow sibling one, so
/// a new round in any category appears promptly. Empty off the Games tab.
final combinedLiveTourIdsProvider = Provider<Set<String>>((ref) {
  if (!ref.watch(combinedCategorySelectedProvider)) return const <String>{};
  if (ref.watch(selectedTourModeProvider) != TournamentDetailScreenMode.games) {
    return const <String>{};
  }
  return ref.watch(combinedCategoriesProvider).tourIds.toSet();
});

/// Bumped whenever Combined is opened. The event screen answers by showing
/// the Games tab, the only tab Combined changes; a request made while Games
/// is already showing is a no-op.
final combinedGamesTabRequestProvider = StateProvider<int>((ref) => 0);
