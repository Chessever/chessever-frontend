import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart'
    show liveGroupBroadcastIdsProvider;
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart'
    show TourEventCategory;
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart'
    show smartEventSpaceDraft;
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_provider.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/filter_popup_state.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/group_event_filter_provider.dart';
import 'package:chessever2/screens/my_space/defaults/space_defaults.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/space_tile_content.dart'
    show spaceText;
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/eco_openings.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/game_filter/rating_tier_filter.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:chessever2/widgets/time_control_glyph.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

// ------------------------------------------------------------------ options

/// Level choices, in the Events filter's order: any rating, then the tier
/// floors GM to CM. Taken from the dialog's own [RatingTierFilter.tiers].
List<int?> get kSmartBuilderLevels => [
  null,
  for (final tier in RatingTierFilter.tiers) tier.minRating,
];

/// Time controls, slow to fast. The same [EventFormat] values the dialog
/// offers; only the order differs.
const List<EventFormat> kSmartBuilderFormats = [
  EventFormat.standard,
  EventFormat.rapid,
  EventFormat.blitz,
];

/// Event status choices: the dialog's [EventStatus] values.
const List<EventStatus> kSmartBuilderStatuses = EventStatus.values;

// ------------------------------------------------------------------ request

/// The Smart Event the builder's filters describe. Its criteria (and so its
/// My Space key, saved identity and every query it runs) are exactly what
/// the Events filter dialog builds from the same state. Two friendlier faces
/// of the same criteria are used where they exist:
///
/// - an opening alone is the opening Smart Event search makes, carrying the
///   picked line so the event can explain it;
/// - a lone level or time control is the preset My Space seeds and offers,
///   so "GM" here and the seeded "GM Games" are one Smart Event.
SmartEventRequest? smartEventBuilderRequest(
  FilterPopupState filter, {
  OpeningSearchSelection? opening,
}) {
  final base = smartEventRequestFromFilterState(filter);
  if (base == null) return null;
  final picked = opening != null && opening.filter == filter.eco;
  if (!filter.eco.isAll && picked) {
    if (filter.formatsAndStates.isEmpty && !filter.hasEloFilter) {
      return SmartEventRequest.forOpeningSelection(opening);
    }
    return base.withOpeningContext(
      SmartEventOpeningContext.fromSelection(opening),
    );
  }
  for (final preset in [
    ...kSpaceSmartLevelPresets,
    ...kSpaceSmartFormatPresets,
  ]) {
    if (preset.criteriaKey == base.criteriaKey) return preset;
  }
  return base;
}

/// One line saying exactly what the Smart Event holds. Names collapse
/// several picks ("Filtered", or a level alone next to live games); this
/// line never does. Null when nothing is picked.
String? smartEventBuilderSummary(FilterPopupState filter) {
  final parts = <String>[
    if (filter.minElo case final min?) 'Game average $min+',
    if (_orList([
          for (final f in kSmartBuilderFormats)
            if (filter.formatsAndStates.contains(f.name)) f.caption,
        ])
        case final formats?)
      formats,
    if (_orList([
          for (final s in kSmartBuilderStatuses)
            if (filter.formatsAndStates.contains(s.name)) s.caption,
        ])
        case final statuses?)
      '$statuses events',
  ];
  // Read as one sentence joined by commas, so a wrapped line never strands
  // a separator at its end. Words after the first drop their capital; the
  // ECO code, always last, keeps its own.
  for (var i = 1; i < parts.length; i++) {
    parts[i] = parts[i][0].toLowerCase() + parts[i].substring(1);
  }
  if (!filter.eco.isAll) parts.add(_ecoCode(filter.eco));
  return parts.isEmpty ? null : parts.join(', ');
}

/// [smartEventBuilderSummary] for a saved Smart Event: the line its card
/// carries under the counts, in the builder's own words.
String? smartEventCardSummary(SmartEventRequest request) =>
    smartEventBuilderSummary(request.criteria.toPopupState());

/// Whether any event [request] gathers is live now, by the category each
/// member carried when it was gathered.
bool smartEventHasLive(SmartEventRequest request) => request.events.any(
  (e) => e.tourEventCategory == TourEventCategory.live,
);

/// Whether any event [request] gathers is live now, the way an event card
/// decides its LIVE: the member's category, or the strict live-ids stream,
/// which is the authority while a category lags a round that just started.
/// Rebuilds the caller only when that answer changes.
bool watchSmartEventLive(WidgetRef ref, SmartEventRequest request) {
  if (smartEventHasLive(request)) return true;
  final ids = {for (final e in request.events) e.id};
  if (ids.isEmpty) return false;
  return ref.watch(
    liveGroupBroadcastIdsProvider.select(
      (live) => live.valueOrNull?.any(ids.contains) ?? false,
    ),
  );
}

String? _orList(List<String> items) {
  if (items.isEmpty) return null;
  final rest = [for (final s in items.skip(1)) s.toLowerCase()];
  if (rest.isEmpty) return items.first;
  final head = [items.first, ...rest.take(rest.length - 1)].join(', ');
  return '$head or ${rest.last}';
}

/// An ECO code or range as text, the range with a real en dash.
String _ecoCode(GameEcoFilter eco) {
  final family = EcoOpenings.getFamily(eco.code);
  final label = family?.rangeLabel ?? eco.displayText;
  return label.replaceAll('-', '–');
}

/// A move line that only wraps between full moves ("1. e4 c5" stays whole).
String _unbrokenMoves(String moves) {
  final tokens = moves.trim().split(RegExp(r'\s+'));
  final out = StringBuffer();
  for (var i = 0; i < tokens.length; i++) {
    if (i > 0) {
      out.write(RegExp(r'^\d+\.').hasMatch(tokens[i]) ? ' ' : '\u00A0');
    }
    out.write(tokens[i]);
  }
  return out.toString();
}

String _ecoName(GameEcoFilter eco) =>
    EcoOpenings.getFilterName(eco.code) ?? eco.displayText;

// ------------------------------------------------------------ opening tree

/// One selectable opening in the builder's browser: a family range or an
/// exact code, nested under the smallest family that holds it.
@visibleForTesting
class SmartBuilderOpeningNode {
  SmartBuilderOpeningNode(this.suggestion, this.parent);

  final OpeningSearchSuggestion suggestion;
  final SmartBuilderOpeningNode? parent;
  final List<SmartBuilderOpeningNode> children = [];

  int get depth => parent == null ? 0 : parent!.depth + 1;

  String get id => suggestion.id;
}

/// Every option of the Events dialog's opening browser (families and exact
/// codes), grouped by ECO category letter as a tree. Built once.
@visibleForTesting
Map<String, List<SmartBuilderOpeningNode>> get smartBuilderOpeningTree =>
    _openingTree ??= _buildOpeningTree();

Map<String, List<SmartBuilderOpeningNode>>? _openingTree;

Map<String, List<SmartBuilderOpeningNode>> _buildOpeningTree() {
  final all = browseOpeningSuggestions();
  final codes = {for (final s in all) s.id: s.filter.exactEcoCodes.toSet()};
  final families = [
    for (final s in all)
      if (s.isFamily) s,
  ];

  OpeningSearchSuggestion? parentOf(OpeningSearchSuggestion s) {
    final mine = codes[s.id]!;
    OpeningSearchSuggestion? best;
    for (final f in families) {
      if (f.id == s.id) continue;
      final theirs = codes[f.id]!;
      if (theirs.length <= mine.length || !theirs.containsAll(mine)) continue;
      if (best == null || theirs.length < codes[best.id]!.length) best = f;
    }
    return best;
  }

  final parents = {for (final s in all) s.id: parentOf(s)};
  final nodes = <String, SmartBuilderOpeningNode>{};
  SmartBuilderOpeningNode nodeFor(OpeningSearchSuggestion s) {
    final existing = nodes[s.id];
    if (existing != null) return existing;
    final parent = parents[s.id];
    return nodes[s.id] = SmartBuilderOpeningNode(
      s,
      parent == null ? null : nodeFor(parent),
    );
  }

  final roots = <String, List<SmartBuilderOpeningNode>>{};
  // Browse order is already category, range start, family first, widest
  // first, so appending keeps every level sorted.
  for (final s in all) {
    final node = nodeFor(s);
    final parent = node.parent;
    if (parent == null) {
      final letter = s.filter.categoryLetter;
      if (letter == null) continue;
      roots.putIfAbsent(letter, () => []).add(node);
    } else {
      parent.children.add(node);
    }
  }
  return roots;
}

/// The node for [eco] in its category, or null.
SmartBuilderOpeningNode? _findNode(GameEcoFilter eco) {
  final letter = eco.categoryLetter;
  if (eco.isAll || letter == null) return null;
  SmartBuilderOpeningNode? search(List<SmartBuilderOpeningNode> nodes) {
    for (final n in nodes) {
      if (n.suggestion.filter == eco) return n;
      final hit = search(n.children);
      if (hit != null) return hit;
    }
    return null;
  }

  return search(smartBuilderOpeningTree[letter] ?? const []);
}

// ------------------------------------------------------------------ builder

/// Build a Smart Event in place: every filter the Events dialog has (level,
/// time control, event status, opening) on one screen, the resulting event
/// named live underneath, and one tap to add it to My Space. Hosted by the
/// My Space add sheet, which owns adding, the closing snack and Undo.
class SmartEventBuilder extends ConsumerStatefulWidget {
  const SmartEventBuilder({
    super.key,
    required this.onToggle,
    required this.onDone,
  });

  /// Adds the draft to My Space, or takes it back out when it is there.
  final Future<void> Function(SpaceShortcut draft) onToggle;

  /// Closes the sheet.
  final VoidCallback onDone;

  @override
  ConsumerState<SmartEventBuilder> createState() => _SmartEventBuilderState();
}

class _SmartEventBuilderState extends ConsumerState<SmartEventBuilder> {
  /// The opening line last picked from the browser, kept so the event can
  /// explain it. Only used while it still matches the filter's opening.
  OpeningSearchSelection? _opening;

  /// The opening browser is showing in place of the controls.
  bool _picking = false;

  void _pickLevel(int? minElo) {
    final current = ref.read(smartEventBuilderFilterProvider).minElo;
    HapticFeedbackService.selection();
    // Tapping the chosen tier again clears it, as in the dialog.
    ref
        .read(smartEventBuilderFilterProvider.notifier)
        .setMinimumElo(current == minElo ? null : minElo);
  }

  void _toggle(String raw) {
    HapticFeedbackService.selection();
    ref.read(smartEventBuilderFilterProvider.notifier).toggleFormatOrState(raw);
  }

  void _setOpening(OpeningSearchSuggestion? s) {
    HapticFeedbackService.selection();
    ref
        .read(smartEventBuilderFilterProvider.notifier)
        .setEco(s?.filter ?? GameEcoFilter.all);
    setState(() {
      _opening = s?.selection;
      _picking = false;
    });
  }

  void _openPicker() {
    HapticFeedbackService.buttonPress();
    setState(() => _picking = true);
  }

  void _closePicker() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _picking = false);
  }

  /// Done closes the sheet from anywhere. The browser's back guard only
  /// stands in for the system back gesture, so it steps aside first.
  void _done() {
    if (!_picking) {
      widget.onDone();
      return;
    }
    _closePicker();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onDone();
    });
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(smartEventBuilderFilterProvider);
    final opening = _opening?.filter == filter.eco ? _opening : null;
    final request = smartEventBuilderRequest(filter, opening: opening);
    final draft = request == null ? null : smartEventSpaceDraft(request);
    final added =
        draft != null && ref.watch(spaceShortcutExistsProvider(draft.key));

    return PopScope(
      canPop: !_picking,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _picking) _closePicker();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(onDone: _done),
          Flexible(
            child: Stack(
              children: [
                // Kept laid out under the browser, so the sheet holds its
                // height when the browser opens and closes.
                Visibility(
                  visible: !_picking,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Flexible(
                        child: SingleChildScrollView(
                          key: const ValueKey('smart-builder-controls'),
                          padding: EdgeInsets.fromLTRB(
                            SmartBuilderMetrics.gutter,
                            4.w,
                            SmartBuilderMetrics.gutter,
                            0,
                          ),
                          child: _Controls(
                            filter: filter,
                            onLevel: _pickLevel,
                            onToggle: _toggle,
                            onOpenOpening: _openPicker,
                            onClearOpening: () => _setOpening(null),
                          ),
                        ),
                      ),
                      _Footer(
                        filter: filter,
                        request: request,
                        added: added,
                        onTap: draft == null
                            ? null
                            : () => widget.onToggle(draft),
                      ),
                    ],
                  ),
                ),
                if (_picking)
                  Positioned.fill(
                    child: _OpeningBrowser(
                      selected: filter.eco,
                      selection: opening,
                      onPick: _setOpening,
                      onBack: _closePicker,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Layout numbers shared by the builder's parts.
abstract final class SmartBuilderMetrics {
  static double get gutter => 16.w;

  /// Space between two groups of controls.
  static double get groupGap => 16.w;

  /// Inset of the sliding level thumb inside its track.
  static const double thumbInset = 3;

  /// Every control is at least this tall: a full touch target.
  static const double target = 44;

  /// The level track: two lines of text need a little more.
  static const double track = 52;

  static double get radius => 12.w;
}

// ------------------------------------------------------------------- header

class _Header extends StatelessWidget {
  const _Header({required this.onDone});

  final VoidCallback onDone;

  void handleDone() {
    HapticFeedbackService.buttonPress();
    onDone();
  }

  @override
  Widget build(BuildContext context) {
    final gutter = SmartBuilderMetrics.gutter;
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 4.w),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                'Build a Smart Event',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: spaceText(
                  context,
                  size: 18,
                  line: 24,
                  weight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Semantics(
            container: true,
            button: true,
            label: 'Done',
            onTap: handleDone,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: handleDone,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: 56,
                  minHeight: SmartBuilderMetrics.target,
                ),
                // Flush right on the gutter, like every sheet's Done.
                child: Align(
                  alignment: Alignment.centerRight,
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Text(
                    'Done',
                    style: spaceText(
                      context,
                      size: 15,
                      line: 20,
                      weight: FontWeight.w600,
                      color: context.colors.accentText,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- controls

class _Controls extends StatelessWidget {
  const _Controls({
    required this.filter,
    required this.onLevel,
    required this.onToggle,
    required this.onOpenOpening,
    required this.onClearOpening,
  });

  final FilterPopupState filter;
  final ValueChanged<int?> onLevel;
  final ValueChanged<String> onToggle;
  final VoidCallback onOpenOpening;
  final VoidCallback onClearOpening;

  @override
  Widget build(BuildContext context) {
    final gap = SizedBox(height: SmartBuilderMetrics.groupGap);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Group(
          label: 'Level',
          child: _LevelTrack(
            selected: RatingTierFilter.normalizeMinRating(filter.minElo),
            onPick: onLevel,
          ),
        ),
        gap,
        _Group(
          label: 'Time control',
          child: _ToggleRow(
            items: [
              for (final f in kSmartBuilderFormats)
                _ToggleItem(
                  raw: f.name,
                  label: f.caption,
                  glyph: TimeControlGlyph.assetForLabel(f.name),
                ),
            ],
            selected: filter.formatsAndStates,
            onToggle: onToggle,
          ),
        ),
        gap,
        _Group(
          label: 'Event status',
          child: _ToggleRow(
            items: [
              for (final s in kSmartBuilderStatuses)
                _ToggleItem(raw: s.name, label: s.caption),
            ],
            selected: filter.formatsAndStates,
            onToggle: onToggle,
          ),
        ),
        gap,
        _Group(
          label: 'Opening',
          child: _OpeningField(
            eco: filter.eco,
            onOpen: onOpenOpening,
            onClear: onClearOpening,
          ),
        ),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: spaceText(
              context,
              size: 13,
              line: 18,
              weight: FontWeight.w600,
              color: context.colors.textSecondary,
            ),
          ),
        ),
        SizedBox(height: 8.w),
        child,
      ],
    );
  }
}

// -------------------------------------------------------------------- level

/// Any rating, GM, IM, FM, CM on one track. A thumb slides to the pick;
/// the labels over it are a second, clipped copy in the thumb's ink, so
/// every letter reads correctly on every frame of the slide.
class _LevelTrack extends StatelessWidget {
  const _LevelTrack({required this.selected, required this.onPick});

  final int? selected;
  final ValueChanged<int?> onPick;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final levels = kSmartBuilderLevels;
    final index = math.max(0, levels.indexOf(selected));
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    const inset = SmartBuilderMetrics.thumbInset;
    final radius = SmartBuilderMetrics.radius;

    Widget labels({required bool onThumb}) => Row(
      children: [
        for (final level in levels)
          Expanded(
            child: _LevelLabel(level: level, onThumb: onThumb),
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, box) {
        final segment = (box.maxWidth - inset * 2) / levels.length;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(radius),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: SmartBuilderMetrics.track,
            ),
            child: SingleMotionBuilder(
              motion: still
                  ? const Motion.none()
                  : const CupertinoMotion.smooth(
                      duration: Duration(milliseconds: 300),
                    ),
              value: index.toDouble(),
              child: ExcludeSemantics(child: labels(onThumb: false)),
              builder: (context, t, base) {
                final left = inset + t * segment;
                return Stack(
                  children: [
                    Positioned(
                      left: left,
                      top: inset,
                      bottom: inset,
                      width: segment,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.textPrimary,
                          borderRadius: BorderRadius.circular(radius - inset),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(inset),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: SmartBuilderMetrics.track - inset * 2,
                        ),
                        child: base,
                      ),
                    ),
                    Positioned.fill(
                      child: ClipRect(
                        clipper: _ThumbClip(left: left, width: segment),
                        child: Padding(
                          padding: const EdgeInsets.all(inset),
                          child: ExcludeSemantics(child: labels(onThumb: true)),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Row(
                        children: [
                          for (var i = 0; i < levels.length; i++)
                            Expanded(
                              child: _LevelTarget(
                                level: levels[i],
                                selected: i == index,
                                onTap: () => onPick(levels[i]),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _ThumbClip extends CustomClipper<Rect> {
  const _ThumbClip({required this.left, required this.width});

  final double left;
  final double width;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(left, 0, width, size.height);

  @override
  bool shouldReclip(_ThumbClip old) => old.left != left || old.width != width;
}

String _levelCode(int? level) {
  if (level == null) return 'Any';
  return RatingTierFilter.tiers.firstWhere((t) => t.minRating == level).label;
}

String _levelFloor(int? level) => level == null ? 'rating' : '$level+';

class _LevelLabel extends StatelessWidget {
  const _LevelLabel({required this.level, required this.onThumb});

  final int? level;
  final bool onThumb;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ink = onThumb ? colors.textInverse : colors.textPrimary;
    final quiet = onThumb
        ? colors.textInverse.withValues(alpha: 0.72)
        : colors.textSecondary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _levelCode(level),
          maxLines: 1,
          textAlign: TextAlign.center,
          style: spaceText(
            context,
            size: 15,
            line: 20,
            weight: FontWeight.w700,
            color: ink,
          ),
        ),
        Text(
          _levelFloor(level),
          maxLines: 1,
          textAlign: TextAlign.center,
          style: spaceText(
            context,
            size: 12,
            line: 16,
            color: quiet,
            tabular: true,
          ),
        ),
      ],
    );
  }
}

class _LevelTarget extends StatelessWidget {
  const _LevelTarget({
    required this.level,
    required this.selected,
    required this.onTap,
  });

  final int? level;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final code = _levelCode(level);
    return Semantics(
      key: ValueKey('smart-builder-level-${level ?? 'any'}'),
      container: true,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: level == null ? 'Any rating' : '$code, game average $level+',
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: const SizedBox.expand(),
      ),
    );
  }
}

// ------------------------------------------------------------------ toggles

class _ToggleItem {
  const _ToggleItem({required this.raw, required this.label, this.glyph});

  final String raw;
  final String label;
  final String? glyph;
}

/// Equal toggles in a row, any number on at once. A time control's glyph
/// shows beside its name while every name still fits beside its glyph; when
/// one would not (a narrow phone at large text), all the glyphs step aside
/// together and the names stay whole.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.items,
    required this.selected,
    required this.onToggle,
  });

  final List<_ToggleItem> items;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  static double get _gap => 8.w;
  static double get _pad => 10.w;
  static double get _glyph => 18.w;
  static double get _glyphGap => 6.w;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final style = _Toggle.labelStyle(context);
    return LayoutBuilder(
      builder: (context, box) {
        final width = (box.maxWidth - _gap * (items.length - 1)) / items.length;
        final room = width - _pad * 2;
        final glyphs =
            items.any((i) => i.glyph != null) &&
            items.every((i) {
              final label = _measure(i.label, style, scaler);
              return label + (i.glyph == null ? 0 : _glyph + _glyphGap) <= room;
            });
        // Equal heights whatever each label needs.
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) SizedBox(width: _gap),
                Expanded(
                  child: _Toggle(
                    key: ValueKey('smart-builder-toggle-${items[i].raw}'),
                    item: items[i],
                    on: selected.contains(items[i].raw),
                    showGlyph: glyphs,
                    onTap: () => onToggle(items[i].raw),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

double _measure(String text, TextStyle style, TextScaler scaler) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    super.key,
    required this.item,
    required this.on,
    required this.showGlyph,
    required this.onTap,
  });

  final _ToggleItem item;
  final bool on;
  final bool showGlyph;
  final VoidCallback onTap;

  static TextStyle labelStyle(BuildContext context) =>
      spaceText(context, size: 14, line: 18, weight: FontWeight.w600);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final glyph = item.glyph;
    return Semantics(
      container: true,
      button: true,
      toggled: on,
      label: item.label,
      onTap: onTap,
      excludeSemantics: true,
      child: _Pressable(
        onTap: onTap,
        child: SingleMotionBuilder(
          motion: still
              ? const Motion.none()
              : const CupertinoMotion.smooth(
                  duration: Duration(milliseconds: 200),
                ),
          value: on ? 1.0 : 0.0,
          builder: (context, t, _) {
            final p = t.clamp(0.0, 1.0);
            final ink = Color.lerp(colors.textPrimary, colors.textInverse, p)!;
            return DecoratedBox(
              decoration: BoxDecoration(
                color: Color.lerp(colors.background, colors.textPrimary, p),
                borderRadius: BorderRadius.circular(SmartBuilderMetrics.radius),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: SmartBuilderMetrics.target,
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: _ToggleRow._pad,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (showGlyph && glyph != null) ...[
                        TimeControlGlyph(
                          glyph,
                          size: _ToggleRow._glyph,
                          // On the ink fill the ground flips: the paper
                          // twins on dark's white, the originals on
                          // paper's ink.
                          onDark: on ? context.isLightTheme : null,
                        ),
                        SizedBox(width: _ToggleRow._glyphGap),
                      ],
                      Flexible(
                        child: Text(
                          item.label,
                          maxLines: 1,
                          softWrap: false,
                          style: labelStyle(context).copyWith(color: ink),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ opening field

class _OpeningField extends StatelessWidget {
  const _OpeningField({
    required this.eco,
    required this.onOpen,
    required this.onClear,
  });

  final GameEcoFilter eco;
  final VoidCallback onOpen;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final any = eco.isAll;
    final nameStyle = spaceText(
      context,
      size: 15,
      line: 20,
      weight: any ? FontWeight.w500 : FontWeight.w600,
    );
    return Semantics(
      container: true,
      button: true,
      label: any
          ? 'Opening, any opening'
          : 'Opening, ${_ecoCode(eco)} ${_ecoName(eco)}',
      hint: 'Choose an opening',
      child: _Pressable(
        key: const ValueKey('smart-builder-opening-field'),
        onTap: onOpen,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(SmartBuilderMetrics.radius),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: SmartBuilderMetrics.track,
            ),
            child: Row(
              children: [
                SizedBox(width: 14.w),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: ExcludeSemantics(
                      child: Text.rich(
                        any
                            ? TextSpan(text: 'Any opening', style: nameStyle)
                            : TextSpan(
                                children: [
                                  TextSpan(
                                    text: _ecoCode(eco),
                                    style: nameStyle.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: colors.titleAccent,
                                    ),
                                  ),
                                  const TextSpan(text: ' '),
                                  TextSpan(text: _ecoName(eco)),
                                ],
                                style: nameStyle,
                              ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                if (any)
                  SizedBox.square(
                    dimension: SmartBuilderMetrics.target,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 22.w,
                      color: colors.textSecondary,
                    ),
                  )
                else
                  _IconTap(
                    key: const ValueKey('smart-builder-opening-clear'),
                    icon: Icons.close_rounded,
                    label: 'Clear opening',
                    onTap: onClear,
                  ),
                SizedBox(width: 2.w),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- footer

/// The event being built, named as it will be named everywhere, one exact
/// line under it, and the add control. Its text block reserves the room the
/// longest name and line could take for the current opening, so toggling a
/// filter never moves the sheet under the thumb.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.filter,
    required this.request,
    required this.added,
    required this.onTap,
  });

  final FilterPopupState filter;
  final SmartEventRequest? request;
  final bool added;
  final VoidCallback? onTap;

  static TextStyle nameStyle(BuildContext context) =>
      spaceText(context, size: 17, line: 22, weight: FontWeight.w700);

  static TextStyle lineStyle(BuildContext context) => spaceText(
    context,
    size: 13,
    line: 18,
    color: context.colors.textSecondary,
  );

  static final Map<String, (double, double)> _reserved = {};

  /// The tallest name and summary this opening can produce at [width].
  (double, double) _reserve(BuildContext context, double width) {
    final scaler = MediaQuery.textScalerOf(context);
    final key =
        '${filter.eco.code}|${width.toStringAsFixed(1)}|${scaler.scale(100)}'
        '|${nameStyle(context).fontSize}|${lineStyle(context).fontSize}';
    if (_reserved[key] case final hit?) return hit;
    if (_reserved.length > 64) _reserved.clear();
    return _reserved[key] = _measureReserve(context, width, scaler);
  }

  (double, double) _measureReserve(
    BuildContext context,
    double width,
    TextScaler scaler,
  ) {
    double height(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 2,
      )..layout(maxWidth: width);
      final h = painter.height;
      painter.dispose();
      return h;
    }

    final names = <String>{
      'New Smart Event',
      for (final level in kSmartBuilderLevels)
        for (final raw in [
          null,
          ...kSmartBuilderFormats.map((f) => f.name),
          ...kSmartBuilderStatuses.map((s) => s.name),
        ])
          if (smartEventRequestFromFilterState(
                FilterPopupState(
                  formatsAndStates: {?raw},
                  eloRange: RangeValues(
                    level?.toDouble() ?? kFilterMinElo,
                    kFilterMaxElo,
                  ),
                  eco: filter.eco,
                ),
              )
              case final r?)
            r.displayName,
    };
    final widest = FilterPopupState(
      formatsAndStates: {
        for (final f in kSmartBuilderFormats) f.name,
        for (final s in kSmartBuilderStatuses) s.name,
      },
      eloRange: RangeValues(
        RatingTierFilter.tiers.first.minRating.toDouble(),
        kFilterMaxElo,
      ),
      eco: filter.eco,
    );
    final lines = [smartEventBuilderSummary(widest)!, _prompt];
    return (
      names.map((n) => height(n, nameStyle(context))).reduce(math.max),
      lines.map((l) => height(l, lineStyle(context))).reduce(math.max),
    );
  }

  static const _prompt = 'Pick a level, time control, status or opening';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final gutter = SmartBuilderMetrics.gutter;
    final request = this.request;
    final summary = smartEventBuilderSummary(filter);
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 20.w, gutter, 16.w),
      child: LayoutBuilder(
        builder: (context, box) {
          final (nameRoom, lineRoom) = _reserve(context, box.maxWidth);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: nameRoom + 2 + lineRoom),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        request?.displayName ?? 'New Smart Event',
                        key: const ValueKey('smart-builder-name'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: nameStyle(context).copyWith(
                          color: request == null ? colors.textSecondary : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary ?? _prompt,
                      key: const ValueKey('smart-builder-summary'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: lineStyle(context),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12.w),
              _AddButton(
                name: request?.displayName,
                added: added,
                onTap: onTap,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The one action: add the event to My Space. Brand fill while it can be
/// added; once it is in, it settles into the track tone with the "+" turned
/// into a check, and a second tap takes it back out, like every add control
/// in My Space.
class _AddButton extends StatelessWidget {
  const _AddButton({
    required this.name,
    required this.added,
    required this.onTap,
  });

  final String? name;
  final bool added;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final enabled = onTap != null;
    final label = added ? 'Added to My Space' : 'Add to My Space';
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: !enabled
          ? 'Add to My Space'
          : added
          ? 'Remove $name from My Space'
          : 'Add $name to My Space',
      onTap: onTap,
      excludeSemantics: true,
      child: _Pressable(
        key: const ValueKey('smart-builder-cta'),
        onTap: onTap,
        child: SingleMotionBuilder(
          motion: still
              ? const Motion.none()
              : const CupertinoMotion.smooth(
                  duration: Duration(milliseconds: 250),
                ),
          value: enabled && !added ? 0.0 : 1.0,
          builder: (context, t, _) {
            final p = t.clamp(0.0, 1.0);
            final fill = Color.lerp(colors.brand, colors.background, p)!;
            final ink = Color.lerp(
              colors.inkOnAccent,
              enabled ? colors.textPrimary : colors.textSecondary,
              p,
            )!;
            return DecoratedBox(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(14.w),
              ),
              child: SizedBox(
                height: SmartBuilderMetrics.track,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SingleMotionBuilder(
                      motion: still
                          ? const Motion.none()
                          : const CupertinoMotion.snappy(),
                      value: added ? 1.0 : 0.0,
                      builder: (context, morph, _) => CustomPaint(
                        size: Size.square(20.w),
                        painter: _PlusCheckMark(
                          t: morph,
                          plus: ink,
                          check: colors.accentText,
                        ),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: spaceText(
                          context,
                          size: 16,
                          line: 20,
                          weight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The My Space add mark: a "+" whose two bars travel into a check.
class _PlusCheckMark extends CustomPainter {
  const _PlusCheckMark({
    required this.t,
    required this.plus,
    required this.check,
  });

  final double t;
  final Color plus;
  final Color check;

  @override
  void paint(Canvas canvas, Size size) {
    const unit = 20.0;
    final k = size.shortestSide / unit;
    final origin = Offset(
      (size.width - unit * k) / 2,
      (size.height - unit * k) / 2,
    );
    final p = t.clamp(0.0, 1.0);
    Offset at(Offset a, Offset b) => origin + Offset.lerp(a, b, p)! * k;
    final paint = Paint()
      ..color = Color.lerp(plus, check, p)!
      ..strokeWidth = 2.4 * k
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      at(const Offset(10, 3), const Offset(4, 10.5)),
      at(const Offset(10, 17), const Offset(8.2, 14.6)),
      paint,
    );
    canvas.drawLine(
      at(const Offset(3, 10), const Offset(8.2, 14.6)),
      at(const Offset(17, 10), const Offset(16.2, 5.6)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_PlusCheckMark old) =>
      old.t != t || old.plus != plus || old.check != check;
}

// ---------------------------------------------------------- opening browser

/// Every opening the Events dialog offers, in place of the controls: search
/// on top, then Any opening and the five ECO groups; a group lists its
/// families and codes as the dialog's tree does, a family opening to show
/// what it holds. A pick returns straight to the controls.
class _OpeningBrowser extends StatefulWidget {
  const _OpeningBrowser({
    required this.selected,
    required this.selection,
    required this.onPick,
    required this.onBack,
  });

  final GameEcoFilter selected;
  final OpeningSearchSelection? selection;
  final ValueChanged<OpeningSearchSuggestion?> onPick;
  final VoidCallback onBack;

  @override
  State<_OpeningBrowser> createState() => _OpeningBrowserState();
}

class _OpeningBrowserState extends State<_OpeningBrowser> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _selectedKey = GlobalKey();
  Timer? _debounce;
  String _query = '';
  List<OpeningSearchSuggestion> _found = const [];
  String? _category;
  final Set<String> _open = {};

  @override
  void initState() {
    super.initState();
    // Reopen where the current pick lives, its family unfolded.
    final node = _findNode(widget.selected);
    if (node != null) {
      _category = widget.selected.categoryLetter;
      for (var p = node.parent; p != null; p = p.parent) {
        _open.add(p.id);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _selectedKey.currentContext;
        if (target != null && target.mounted) {
          Scrollable.ensureVisible(target, alignment: 0.3);
        }
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      final query = value.trim();
      setState(() {
        _query = query;
        _found = query.isEmpty
            ? const []
            : searchOpeningSuggestions(query, limit: 80);
      });
    });
  }

  void _back() {
    HapticFeedbackService.buttonPress();
    if (_query.isNotEmpty || _controller.text.isNotEmpty) {
      _clearQuery();
      return;
    }
    if (_category != null) {
      setState(() => _category = null);
      return;
    }
    widget.onBack();
  }

  void _clearQuery() {
    _debounce?.cancel();
    _controller.clear();
    setState(() {
      _query = '';
      _found = const [];
    });
  }

  bool _isPicked(OpeningSearchSuggestion s) {
    if (s.filter != widget.selected) return false;
    final picked = widget.selection;
    // Several named lines share one code: mark the one that was tapped.
    if (picked == null || s.isAggregate) return true;
    return picked.hierarchyLabel == s.hierarchyLabel;
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final gutter = SmartBuilderMetrics.gutter;
    final title = _query.isNotEmpty
        ? 'Opening'
        : _category == null
        ? 'Opening'
        : EcoOpenings.categories[_category]?.name ?? _category!;
    return SingleMotionBuilder(
      motion: still
          ? const Motion.none()
          : const CupertinoMotion.smooth(duration: Duration(milliseconds: 250)),
      from: 24.w,
      value: 0,
      builder: (context, dx, child) =>
          Transform.translate(offset: Offset(dx, 0), child: child),
      child: ColoredBox(
        color: context.colors.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.only(left: gutter - 12, right: gutter),
              child: Row(
                children: [
                  _IconTap(
                    key: const ValueKey('smart-builder-opening-back'),
                    icon: Icons.chevron_left_rounded,
                    label: 'Back',
                    onTap: _back,
                    size: 26,
                  ),
                  SizedBox(width: 2.w),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: spaceText(
                          context,
                          size: 15,
                          line: 20,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(gutter, 4.w, gutter, 4.w),
              child: _SearchField(
                controller: _controller,
                focusNode: _focus,
                onChanged: _onChanged,
                onClear: _clearQuery,
              ),
            ),
            Expanded(child: _list(context)),
          ],
        ),
      ),
    );
  }

  Widget _list(BuildContext context) {
    if (_query.isNotEmpty) {
      final found = _found;
      if (found.isEmpty) {
        return _Note(
          text: _query.length < minimumOpeningSearchCharacters
              ? 'Type at least $minimumOpeningSearchCharacters letters'
              : 'No opening matches',
        );
      }
      return ListView.builder(
        key: const ValueKey('smart-builder-opening-results'),
        padding: EdgeInsets.only(bottom: 12.w),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: found.length,
        itemBuilder: (context, i) {
          final s = found[i];
          final moves = _unbrokenMoves(formatOpeningMovePath(s.movePath));
          return _OpeningRow(
            key: ValueKey('result:${s.id}'),
            code: _ecoCode(s.filter),
            title: s.fullTitle,
            meta: moves.isEmpty ? s.subtitle : moves,
            picked: _isPicked(s),
            onTap: () => widget.onPick(s),
          );
        },
      );
    }

    final category = _category;
    if (category == null) {
      return ListView(
        key: const ValueKey('smart-builder-opening-root'),
        padding: EdgeInsets.only(bottom: 12.w),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          _OpeningRow(
            key: const ValueKey('smart-builder-opening-any'),
            title: 'Any opening',
            picked: widget.selected.isAll,
            onTap: () => widget.onPick(null),
          ),
          for (final entry in EcoOpenings.categories.entries)
            _OpeningRow(
              key: ValueKey('smart-builder-category-${entry.key}'),
              code: entry.key,
              title: entry.value.name,
              meta: entry.value.keyOpenings
                  .take(3)
                  .map((o) => o.replaceAll(RegExp(r'\s*\(.*?\)'), ''))
                  .join(', '),
              trailing: _TrailingIcon(Icons.chevron_right_rounded),
              onTap: () {
                HapticFeedbackService.selection();
                setState(() => _category = entry.key);
              },
            ),
        ],
      );
    }

    final rows = <Widget>[];
    void add(List<SmartBuilderOpeningNode> nodes) {
      for (final node in nodes) {
        final s = node.suggestion;
        final open = _open.contains(node.id);
        final picked = _isPicked(s);
        rows.add(
          _OpeningRow(
            key: picked ? _selectedKey : ValueKey('node:${node.id}'),
            code: _ecoCode(s.filter),
            title: s.fullTitle,
            meta: s.isFamily ? '${s.filter.exactEcoCodes.length} codes' : null,
            depth: node.depth,
            picked: picked,
            onTap: () => widget.onPick(s),
            trailing: node.children.isEmpty
                ? null
                : _IconTap(
                    key: ValueKey('smart-builder-unfold-${node.id}'),
                    icon: open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    label: open
                        ? 'Fold ${s.fullTitle}'
                        : 'Show what ${s.fullTitle} holds',
                    onTap: () {
                      HapticFeedbackService.selection();
                      setState(() {
                        if (!_open.remove(node.id)) _open.add(node.id);
                      });
                    },
                  ),
          ),
        );
        if (open) add(node.children);
      }
    }

    add(smartBuilderOpeningTree[category] ?? const []);
    return SingleChildScrollView(
      key: ValueKey('smart-builder-category-list-$category'),
      padding: EdgeInsets.only(bottom: 12.w),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }
}

class _OpeningRow extends StatelessWidget {
  const _OpeningRow({
    super.key,
    required this.title,
    required this.onTap,
    this.code,
    this.meta,
    this.depth = 0,
    this.picked = false,
    this.trailing,
  });

  final String? code;
  final String title;
  final String? meta;
  final int depth;
  final bool picked;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final gutter = SmartBuilderMetrics.gutter;
    final titleStyle = spaceText(
      context,
      size: 15,
      line: 20,
      weight: FontWeight.w600,
    );
    final meta = this.meta?.trim();
    final hasTrailing = trailing != null || picked;
    return Semantics(
      container: true,
      button: true,
      selected: picked,
      label: [?code, title].join(' '),
      // Excluded children take the tap action with them; put it back here.
      onTap: trailing == null ? onTap : null,
      excludeSemantics: trailing == null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              gutter + depth * 16.w,
              6,
              hasTrailing ? gutter - 10 : gutter,
              6,
            ),
            child: Row(
              children: [
                Expanded(
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              if (code != null) ...[
                                TextSpan(
                                  text: code,
                                  style: titleStyle.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: colors.titleAccent,
                                  ),
                                ),
                                const TextSpan(text: ' '),
                              ],
                              TextSpan(text: title),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                        if (meta != null && meta.isNotEmpty)
                          Text(
                            meta,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: spaceText(
                              context,
                              size: 13,
                              line: 18,
                              color: colors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (picked)
                  SizedBox(
                    width: trailing == null ? SmartBuilderMetrics.target : 28,
                    height: SmartBuilderMetrics.target,
                    child: Icon(
                      Icons.check_rounded,
                      size: 20.w,
                      color: colors.accentText,
                    ),
                  ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrailingIcon extends StatelessWidget {
  const _TrailingIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: SmartBuilderMetrics.target,
      child: Icon(icon, size: 22.w, color: context.colors.textSecondary),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final gutter = SmartBuilderMetrics.gutter;
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 12.w, gutter, 12.w),
      child: Text(
        text,
        style: spaceText(
          context,
          size: 14,
          line: 20,
          color: context.colors.textSecondary,
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = spaceText(context, size: 15, line: 20);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: SmartBuilderMetrics.target),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(10.w),
        ),
        child: Row(
          children: [
            SizedBox(width: 12.w),
            Icon(Icons.search_rounded, size: 20.w, color: colors.textSecondary),
            SizedBox(width: 8.w),
            Expanded(
              child: TextField(
                key: const ValueKey('smart-builder-opening-search'),
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                cursorColor: colors.accentText,
                style: style,
                inputFormatters: [LengthLimitingTextInputFormatter(80)],
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Search openings or ECO',
                  hintStyle: style.copyWith(color: colors.textSecondary),
                  contentPadding: EdgeInsets.symmetric(vertical: 12.w),
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                if (value.text.isEmpty) return SizedBox(width: 12.w);
                return _IconTap(
                  icon: Icons.close_rounded,
                  label: 'Clear search',
                  onTap: onClear,
                  size: 18,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- common

/// A bare icon on a 44dp target.
class _IconTap extends StatelessWidget {
  const _IconTap({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.size = 20,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: SmartBuilderMetrics.target,
          child: Icon(icon, size: size.w, color: context.colors.textSecondary),
        ),
      ),
    );
  }
}

/// Presses to 0.97 on a spring and back: the control heard the tap.
class _Pressable extends StatefulWidget {
  const _Pressable({super.key, required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _pressed = false;

  void _press(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: enabled ? (_) => _press(true) : null,
      onTapUp: enabled ? (_) => _press(false) : null,
      onTapCancel: enabled ? () => _press(false) : null,
      child: SingleMotionBuilder(
        motion: still ? const Motion.none() : const CupertinoMotion.bouncy(),
        value: _pressed ? 0.97 : 1.0,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: widget.child,
      ),
    );
  }
}
