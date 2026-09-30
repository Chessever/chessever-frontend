import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

/// Where a tile My Space shows without it being pinned comes from.
enum SpaceAutoOrigin {
  /// A Library destination, mirrored live from the Library tab.
  library,

  /// A liked game, mirrored live from My Likes.
  liked,

  /// Something My Space suggests for the row (a followed player, a live
  /// event, a hot streak). It can be pinned or hidden.
  suggested,
}

/// One tile a row shows on its own: a [shortcut] face (never stored) plus the
/// Library destination or liked game it stands for.
@immutable
class SpaceAutoItem {
  const SpaceAutoItem({
    required this.shortcut,
    required this.origin,
    this.folder,
    this.analysis,
  });

  final SpaceShortcut shortcut;
  final SpaceAutoOrigin origin;
  final LibraryFolder? folder;
  final SavedAnalysis? analysis;

  /// The pin this tile would be; also its identity on the row.
  String get key => shortcut.key;

  @override
  bool operator ==(Object other) =>
      other is SpaceAutoItem &&
      other.origin == origin &&
      other.shortcut.key == shortcut.key &&
      other.shortcut.title == shortcut.title &&
      other.shortcut.subtitle == shortcut.subtitle &&
      const DeepCollectionEquality().equals(
        other.shortcut.params,
        shortcut.params,
      ) &&
      other.folder == folder &&
      other.analysis?.id == analysis?.id &&
      other.analysis?.updatedAt == analysis?.updatedAt &&
      const ListEquality<String>().equals(other.analysis?.tags, analysis?.tags);

  @override
  int get hashCode => Object.hash(origin, shortcut.key, shortcut.title);
}

/// What a row shows besides its pins: [leading] tiles drawn before them (a
/// live mirror), [trailing] ones after (suggestions), and the pins the row
/// leaves out because a mirrored tile already stands for them.
@immutable
class SpaceAutoRow {
  const SpaceAutoRow({
    this.leading = const [],
    this.trailing = const [],
    this.hiddenPinKeys = const {},
    this.total,
    this.settled = true,
  });

  final List<SpaceAutoItem> leading;
  final List<SpaceAutoItem> trailing;
  final Set<String> hiddenPinKeys;

  /// What the row header counts, when that is more than the tiles shown (all
  /// of My Likes while the row shows the latest).
  final int? total;

  /// False while the sources are still loading. Tiles that arrive before a
  /// row has settled join it quietly; only later arrivals pop in.
  final bool settled;

  static const empty = SpaceAutoRow();

  bool get isEmpty => leading.isEmpty && trailing.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is SpaceAutoRow &&
      other.total == total &&
      other.settled == settled &&
      const ListEquality<SpaceAutoItem>().equals(other.leading, leading) &&
      const ListEquality<SpaceAutoItem>().equals(other.trailing, trailing) &&
      const SetEquality<String>().equals(other.hiddenPinKeys, hiddenPinKeys);

  @override
  int get hashCode =>
      Object.hash(total, settled, leading.length, trailing.length);
}

/// Puts a row together from its sources: the mirror first, as it is (a pin of
/// the same thing steps aside for it); then suggestions that are not already
/// pinned, mirrored, hidden or repeated, at most [trailingCap].
SpaceAutoRow composeSpaceAutoRow({
  List<SpaceAutoItem> leading = const [],
  List<SpaceAutoItem> trailing = const [],
  Set<String> pinned = const {},
  Set<String> hidden = const {},
  Set<String> hiddenPinKeys = const {},
  int trailingCap = 12,
  int? total,
  bool settled = true,
}) {
  final seen = <String>{};
  final lead = <SpaceAutoItem>[
    for (final item in leading)
      if (seen.add(item.key)) item,
  ];
  final trail = <SpaceAutoItem>[];
  for (final item in trailing) {
    if (trail.length >= trailingCap) break;
    if (pinned.contains(item.key) || hidden.contains(item.key)) continue;
    if (!seen.add(item.key)) continue;
    trail.add(item);
  }
  return SpaceAutoRow(
    leading: lead,
    trailing: trail,
    hiddenPinKeys: {...hiddenPinKeys, for (final item in lead) item.key},
    total: total,
    settled: settled,
  );
}
