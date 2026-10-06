import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// My Space's home is one movable arrangement: the page's own cards (My Prep,
// Library, My Likes) among the saved pins. The pins keep their order in the
// shortcuts store; this keeps where the page's own cards stand among them.

/// The page's own cards. They move like any card and are never removed.
const String kSpaceHomeMyPrep = 'home:my_prep';
const String kSpaceHomeLibrary = 'home:library';
const String kSpaceHomeLikes = 'home:likes';

/// The page's own cards in the order a new reader meets them.
const List<String> kSpaceHomeFixed = [
  kSpaceHomeMyPrep,
  kSpaceHomeLibrary,
  kSpaceHomeLikes,
];

/// Whether [key] names one of the page's own cards rather than a pin. Pin
/// keys are `<kind>:<target>` and no pin kind is called `home`.
bool spaceHomeIsFixed(String key) => key.startsWith('home:');

/// Where one of the page's own cards stands: after [pinsBefore] pins.
typedef SpaceHomePlace = ({String key, int pinsBefore});

/// Every fixed card at the top, in their default order.
const List<SpaceHomePlace> kSpaceHomeDefaultPlaces = [
  (key: kSpaceHomeMyPrep, pinsBefore: 0),
  (key: kSpaceHomeLibrary, pinsBefore: 0),
  (key: kSpaceHomeLikes, pinsBefore: 0),
];

/// The whole page's order: [pins] in store order, each fixed card of
/// [places] slotted in after its count of pins. A count past the end puts
/// the card last, so removing pins never loses one.
List<String> spaceHomeOrder(List<String> pins, List<SpaceHomePlace> places) {
  final out = <String>[];
  var p = 0;
  for (var i = 0; i <= pins.length; i++) {
    while (p < places.length &&
        math.min(places[p].pinsBefore, pins.length) <= i) {
      out.add(places[p].key);
      p++;
    }
    if (i < pins.length) out.add(pins[i]);
  }
  return out;
}

/// Where [order] puts each fixed card, in [order]'s order.
List<SpaceHomePlace> spaceHomePlaces(List<String> order) {
  final out = <SpaceHomePlace>[];
  var pins = 0;
  for (final key in order) {
    if (spaceHomeIsFixed(key)) {
      out.add((key: key, pinsBefore: pins));
    } else {
      pins++;
    }
  }
  return normalizeSpaceHomePlaces(out);
}

/// [places] with each fixed card exactly once (a missing one at the top, in
/// its default order), unknown keys dropped, in page order.
@visibleForTesting
List<SpaceHomePlace> normalizeSpaceHomePlaces(List<SpaceHomePlace> places) {
  final seen = <String>{};
  final kept = [
    for (final p in places)
      if (kSpaceHomeFixed.contains(p.key) && seen.add(p.key))
        (key: p.key, pinsBefore: math.max(0, p.pinsBefore)),
  ];
  final missing = [
    for (final key in kSpaceHomeFixed)
      if (!seen.contains(key)) (key: key, pinsBefore: 0),
  ];
  // Stable: equal counts keep the order they were given in.
  final all = [...missing, ...kept];
  final indexed = [for (var i = 0; i < all.length; i++) (i, all[i])];
  indexed.sort((a, b) {
    final by = a.$2.pinsBefore.compareTo(b.$2.pinsBefore);
    return by != 0 ? by : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}

/// Device-local: the arrangement is how this reader likes this screen.
const String kSpaceHomeLayoutKey = 'my_space_home_layout_v1';

/// Where My Space's own cards stand among the pins. Read synchronously from
/// the preferences loaded at startup; with none loaded it lives in memory.
class SpaceHomeLayout extends Notifier<List<SpaceHomePlace>> {
  @override
  List<SpaceHomePlace> build() {
    final raw = SharedPreferencesService.instance.prefsOrNull?.getString(
      kSpaceHomeLayoutKey,
    );
    if (raw == null) return kSpaceHomeDefaultPlaces;
    try {
      final list = jsonDecode(raw);
      if (list is! List) return kSpaceHomeDefaultPlaces;
      return normalizeSpaceHomePlaces([
        for (final e in list)
          if (e is Map && e['k'] is String && e['p'] is num)
            (key: e['k'] as String, pinsBefore: (e['p'] as num).toInt()),
      ]);
    } catch (_) {
      return kSpaceHomeDefaultPlaces;
    }
  }

  /// Takes the fixed cards' places from the page's new [order].
  void placeFrom(List<String> order) {
    final next = spaceHomePlaces(order);
    if (listEquals(next, state)) return;
    state = next;
    final prefs = SharedPreferencesService.instance.prefsOrNull;
    if (prefs == null) return;
    unawaited(
      prefs.setString(
        kSpaceHomeLayoutKey,
        jsonEncode([
          for (final p in next) {'k': p.key, 'p': p.pinsBefore},
        ]),
      ),
    );
  }
}

final spaceHomeLayoutProvider =
    NotifierProvider<SpaceHomeLayout, List<SpaceHomePlace>>(
      SpaceHomeLayout.new,
    );
