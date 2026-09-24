import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart'
    show discoveryTierPreset;
import 'package:chessever2/screens/gamebase/utils/space_position_draft.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart'
    show smartEventSpaceDraft;
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_state.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/navigation/space_shortcut_navigator.dart';
import 'package:chessever2/utils/eco_openings.dart';
import 'package:flutter/foundation.dart';

/// Marks a shortcut My Space put there itself, once per account. Stored in the
/// row's params, where older builds ignore it.
const String kSpaceSeedTag = 'my_space_v1';

/// The params key [kSpaceSeedTag] is stored under.
const String kSpaceSeedParam = 'seed';

/// Whether [s] is one of the defaults My Space seeded.
bool isSpaceSeeded(SpaceShortcut s) =>
    s.params[kSpaceSeedParam] == kSpaceSeedTag;

/// The params key a seeded row carries once the user has chosen to keep it
/// (it was removed and put back with Undo). Stored beside [kSpaceSeedParam],
/// where older builds ignore it.
const String kSpaceKeptParam = 'kept';

/// Whether the user has deliberately kept the seeded row [s].
bool isSpaceKept(SpaceShortcut s) => s.params[kSpaceKeptParam] == true;

/// [s] as Undo puts it back: a seeded row is marked kept, so the one-time
/// trim ([planSpaceDefaultTrim]) never takes back a default the user just
/// restored. Anything else, and a row already marked, comes back unchanged.
SpaceShortcut spaceRestoredShortcut(SpaceShortcut s) {
  if (!isSpaceSeeded(s) || isSpaceKept(s)) return s;
  return s.copyWith(params: {...s.params, kSpaceKeptParam: true});
}

/// One opening line as elite players play it: the code, the short name the
/// tile shows, and the catalogue row it is (name and moves verbatim from
/// `eco_opening_catalog_data.g.dart`).
@immutable
class SpaceEliteOpening {
  const SpaceEliteOpening({
    required this.eco,
    required this.tileName,
    required this.catalogueName,
    required this.moves,
  });

  final String eco;
  final String tileName;
  final String catalogueName;
  final String moves;

  List<String> get sans => EcoOpenings.moveTokens(moves);
}

/// Every account starts with these two in its Openings row: the most played
/// 1.d4 line and the most played 1.e4 line in games between two 2700+
/// players over the last twelve months. Two, not more, so each is easy to
/// keep or remove; the picker offers the rest.
const List<SpaceEliteOpening> kSpaceDefaultOpenings = [
  SpaceEliteOpening(
    eco: 'D37',
    tileName: 'QGD Three Knights',
    catalogueName: "Queen's Gambit Declined, 4.Nf3",
    moves: '1. d4 d5 2. c4 e6 3. Nc3 Nf6 4. Nf3',
  ),
  SpaceEliteOpening(
    eco: 'B30',
    tileName: 'Sicilian Rossolimo',
    catalogueName: 'Sicilian, Nimzovich-Rossolimo attack (without ...d6)',
    moves: '1. e4 c5 2. Nf3 Nc6 3. Bb5',
  ),
];

/// The other ten lines accounts were seeded with before 2026-09-24, in the
/// order they were seeded (right after [kSpaceDefaultOpenings]). No longer
/// seeded; [planSpaceDefaultTrim] takes back the ones a user never touched.
/// Still offered in the picker, right after the defaults.
const List<SpaceEliteOpening> kSpaceRetiredDefaultOpenings = [
  SpaceEliteOpening(
    eco: 'D35',
    tileName: 'QGD Exchange',
    catalogueName: "Queen's Gambit Declined, exchange variation",
    moves: '1. d4 d5 2. c4 e6 3. Nc3 Nf6 4. cxd5',
  ),
  SpaceEliteOpening(
    eco: 'B90',
    tileName: 'Najdorf, English Attack',
    catalogueName: 'Sicilian, Najdorf, Byrne (English) attack',
    moves: '1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6 6. Be3',
  ),
  SpaceEliteOpening(
    eco: 'C50',
    tileName: 'Giuoco Pianissimo',
    catalogueName: 'Giuoco Pianissimo',
    moves: '1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. d3',
  ),
  SpaceEliteOpening(
    eco: 'C65',
    tileName: 'Berlin Defence',
    catalogueName: 'Ruy Lopez, Berlin defence',
    moves: '1. e4 e5 2. Nf3 Nc6 3. Bb5 Nf6',
  ),
  SpaceEliteOpening(
    eco: 'D38',
    tileName: 'Ragozin',
    catalogueName: "Queen's Gambit Declined, Ragozin variation",
    moves: '1. d4 d5 2. c4 e6 3. Nc3 Nf6 4. Nf3 Bb4',
  ),
  SpaceEliteOpening(
    eco: 'C42',
    tileName: 'Petrov Defence',
    catalogueName: "Petrov's defence",
    moves: '1. e4 e5 2. Nf3 Nf6',
  ),
  SpaceEliteOpening(
    eco: 'E05',
    tileName: 'Catalan, Open',
    catalogueName: 'Catalan, open, classical line',
    moves: '1. d4 Nf6 2. c4 e6 3. g3 d5 4. Bg2 dxc4 5. Nf3 Be7',
  ),
  SpaceEliteOpening(
    eco: 'C84',
    tileName: 'Ruy Lopez, Closed',
    catalogueName: 'Ruy Lopez, closed defence',
    moves: '1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7',
  ),
  SpaceEliteOpening(
    eco: 'E11',
    tileName: 'Bogo-Indian',
    catalogueName: 'Bogo-Indian defence',
    moves: '1. d4 Nf6 2. c4 e6 3. Nf3 Bb4+',
  ),
  SpaceEliteOpening(
    eco: 'B12',
    tileName: 'Caro-Kann Advance',
    catalogueName: 'Caro-Kann, advance variation',
    moves: '1. e4 c6 2. d4 d5 3. e5',
  ),
];

/// The elite lines the Openings picker offers beside the defaults, most
/// played first. The picker lists [kSpaceDefaultOpenings] ahead of them and
/// puts whatever is not in My Space yet first, so a removed default comes
/// back as a new option ([spacePickerOpenings]).
const List<SpaceEliteOpening> kSpacePopularOpenings = [
  ...kSpaceRetiredDefaultOpenings,
  SpaceEliteOpening(
    eco: 'B33',
    tileName: 'Sveshnikov',
    catalogueName: 'Sicilian, Pelikan (Lasker/Sveshnikov) variation',
    moves: '1. e4 c5 2. Nf3 Nc6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 e5',
  ),
  SpaceEliteOpening(
    eco: 'D02',
    tileName: 'London System',
    catalogueName: 'London System',
    moves: '1. d4 d5 2. Nf3 Nf6 3. Bf4',
  ),
  SpaceEliteOpening(
    eco: 'C54',
    tileName: 'Giuoco Piano',
    catalogueName: 'Giuoco Piano',
    moves: '1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. c3 Nf6 5. d4 exd4 6. cxd4',
  ),
  SpaceEliteOpening(
    eco: 'C67',
    tileName: 'Berlin, Open',
    catalogueName: 'Ruy Lopez, Berlin defence, open variation',
    moves: '1. e4 e5 2. Nf3 Nc6 3. Bb5 Nf6 4. O-O Nxe4',
  ),
  SpaceEliteOpening(
    eco: 'C88',
    tileName: 'Ruy Lopez, Closed 7.Bb3',
    catalogueName: 'Ruy Lopez, closed',
    moves:
        '1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 6. Re1 b5 7. Bb3',
  ),
];

/// [o] as a My Space position: keyed by the FEN its line reaches, exactly
/// like pinning the same catalogue line from search or the explorer, so
/// "already in My Space" and dedupe hold everywhere. The tile shows the short
/// name; the catalogue name and code ride along. Null only if the line stops
/// replaying, which the defaults test rules out.
SpaceShortcut? spaceEliteOpeningDraft(SpaceEliteOpening o) {
  final line = resolveSpaceLine(moves: o.sans);
  if (line == null || line.ucis.length != o.sans.length) return null;
  final draft = spacePositionDraft(fen: line.fen, ucis: line.ucis);
  if (draft == null) return null;
  return draft.copyWith(
    title: o.tileName,
    subtitle: o.eco,
    params: {
      ...draft.params,
      'eco': o.eco,
      'openingName': o.tileName,
      'catalogueName': o.catalogueName,
    },
  );
}

/// One elite line the Openings picker offers, with the pin it makes.
typedef SpacePickerOpening = ({SpaceEliteOpening opening, SpaceShortcut draft});

/// The Openings picker's elite lines, most played first (the defaults, then
/// [kSpacePopularOpenings]), each once, split by whether [pinned] (the keys
/// My Space holds) has it yet. The picker lists [fresh] first, so what the
/// user can still add leads, and [added] after it. A default the user
/// removed is simply fresh again, ready to be re-added.
({List<SpacePickerOpening> fresh, List<SpacePickerOpening> added})
spacePickerOpenings(Set<String> pinned) {
  final seen = <String>{};
  final fresh = <SpacePickerOpening>[];
  final added = <SpacePickerOpening>[];
  for (final o in [...kSpaceDefaultOpenings, ...kSpacePopularOpenings]) {
    final draft = spaceEliteOpeningDraft(o);
    if (draft == null || !seen.add(draft.key)) continue;
    (pinned.contains(draft.key) ? added : fresh).add((
      opening: o,
      draft: draft,
    ));
  }
  return (fresh: fresh, added: added);
}

/// A Smart Event of every game in one time control, shaped like the rating
/// presets Discovery shows. Its criteria are exactly what the Events filter
/// builds for that time control alone, so a pin made here and one saved from
/// the filter are the same Smart Event.
SmartEventRequest spaceFormatPreset({
  required String label,
  required String wire,
}) {
  return SmartEventRequest(
    source: SmartEventSource.forYou,
    tierLabel: label,
    titleSuffix: 'Games',
    minElo: kFilterMinElo.round(),
    maxElo: kFilterMaxElo.round(),
    caption: 'Every ${label.toLowerCase()} game',
    countSingular: 'event',
    countPlural: 'events',
    events: const [],
    formatsAndStates: {wire},
  );
}

/// Rating levels offered in the Smart Events picker; the same floors the
/// in-event tier dropdown uses.
final List<SmartEventRequest> kSpaceSmartLevelPresets = [
  discoveryTierPreset(tier: 'GM', minElo: 2500),
  discoveryTierPreset(tier: 'IM', minElo: 2400),
  discoveryTierPreset(tier: 'FM', minElo: 2300),
  discoveryTierPreset(tier: 'CM', minElo: 2200),
];

/// Time controls offered in the Smart Events picker.
final List<SmartEventRequest> kSpaceSmartFormatPresets = [
  spaceFormatPreset(label: 'Classical', wire: 'standard'),
  spaceFormatPreset(label: 'Rapid', wire: 'rapid'),
  spaceFormatPreset(label: 'Blitz', wire: 'blitz'),
];

/// The Smart Events every account starts with: GM games and classical games.
final List<SmartEventRequest> kSpaceDefaultSmartEvents = [
  kSpaceSmartLevelPresets.first,
  kSpaceSmartFormatPresets.first,
];

/// Everything seeded into a new My Space, in row order: the two elite
/// openings, then the GM and Classical Smart Events. Each is a real shortcut, tagged
/// with [kSpaceSeedTag], so remove, reorder and Undo treat it like any pin.
List<SpaceShortcut> spaceSeedDrafts() {
  SpaceShortcut tag(SpaceShortcut s) =>
      s.copyWith(params: {...s.params, kSpaceSeedParam: kSpaceSeedTag});
  return [
    for (final o in kSpaceDefaultOpenings)
      if (spaceEliteOpeningDraft(o) case final draft?) tag(draft),
    for (final request in kSpaceDefaultSmartEvents)
      tag(smartEventSpaceDraft(request)),
  ];
}

/// The retired default openings ([kSpaceRetiredDefaultOpenings]) this My
/// Space still holds exactly as it was seeded with them, to be taken back
/// once through the normal remove path.
///
/// Before 2026-09-24 the seed laid its fourteen defaults (twelve openings,
/// then GM and Classical) out as one run, `floor - 1 - i` in that order, so
/// every row still where the seed put it shares one anchor: its sort value
/// plus its place in that run. A row the user moved (a midpoint, a top + 1,
/// a last - 1) leaves the run. A retired row is taken back only when it is
/// seeded, on the run's anchor, never opened and never put back by Undo
/// ([isSpaceKept]); anything the user touched, or pinned themselves, stays.
/// When no anchor is shared by at least two seeded rows, or two anchors tie,
/// nothing is taken on a guess.
List<SpaceShortcut> planSpaceDefaultTrim(List<SpaceShortcut> current) {
  // The old seed skipped a line that no longer replayed, so places count
  // only the drafts it could build, exactly as it did.
  final run = <String>[
    for (final o in [...kSpaceDefaultOpenings, ...kSpaceRetiredDefaultOpenings])
      if (spaceEliteOpeningDraft(o) case final draft?) draft.key,
    for (final request in kSpaceDefaultSmartEvents)
      smartEventSpaceDraft(request).key,
  ];
  final place = {for (var i = 0; i < run.length; i++) run[i]: i};
  final retired = {
    for (final o in kSpaceRetiredDefaultOpenings)
      if (spaceEliteOpeningDraft(o) case final draft?) draft.key,
  };

  double? anchorOf(SpaceShortcut s) {
    if (!isSpaceSeeded(s)) return null;
    final at = place[s.key];
    return at == null ? null : s.sortIndex + at;
  }

  const epsilon = 1e-9;
  final clusters = <({double anchor, int count})>[];
  for (final s in current) {
    final anchor = anchorOf(s);
    if (anchor == null) continue;
    final i = clusters.indexWhere((c) => (c.anchor - anchor).abs() < epsilon);
    if (i < 0) {
      clusters.add((anchor: anchor, count: 1));
    } else {
      clusters[i] = (anchor: clusters[i].anchor, count: clusters[i].count + 1);
    }
  }
  if (clusters.isEmpty) return const [];
  clusters.sort((a, b) => b.count.compareTo(a.count));
  final top = clusters.first;
  if (top.count < 2) return const [];
  if (clusters.length > 1 && clusters[1].count == top.count) return const [];

  bool untouched(SpaceShortcut s) {
    if (!retired.contains(s.key) || s.openCount != 0) return false;
    if (s.lastOpenedAt != null || isSpaceKept(s)) return false;
    final anchor = anchorOf(s);
    return anchor != null && (anchor - top.anchor).abs() < epsilon;
  }

  return [
    for (final s in current)
      if (untouched(s)) s,
  ];
}
