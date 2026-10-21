import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/screens/chessboard/widgets/rest_aware_opacity.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_account_switch.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_filters.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_rating_history.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:motor/motor.dart';

/// The player profile's quiet summary, with secondary analysis on demand.
///
/// One list through every state About has, so its identity and heading keep
/// their place while statistics are read, missing or replaced.
///
/// Most of what it shows is also a choice: a result, a colour, an opening, a
/// clock, an opponent, a year, a length. A tap narrows About to it where it
/// stands, as a player's profile does, and a second tap gives it up.
class PrepOverviewTab extends StatefulWidget {
  const PrepOverviewTab({
    super.key,
    required this.profile,
    required this.stats,
    required this.filter,
    this.total,
    this.header,
    this.heading,
    this.message,
    this.stale = false,
    this.arriving = false,
    this.onFilterChanged,
    this.onSources,
    this.onUnlockDetails,
  });

  final PrepProfile profile;

  /// Null while there are none to show; [message] then takes their place.
  final PrepStats? stats;

  /// What [stats] are narrowed by: the choices drawn as taken.
  final PrepFilter filter;

  /// Every game of the source read, which the chosen ones are counted out
  /// of.
  final int? total;

  /// Leads the list, inset by its owner.
  final Widget? header;

  /// Stands in for the tab's own heading, where the profile also shows one
  /// over [message].
  final Widget? heading;

  /// What About says while it has no statistics: games being read, none
  /// downloaded, a failure.
  final Widget? message;

  /// Whether [stats] are those of the source read a moment ago. They stay
  /// where they are, faint and out of reach, so nothing moves while the
  /// chosen source's games are read.
  final bool stale;

  /// Whether [stats] have just taken another source's place, and so settle
  /// in from faint rather than appear at once.
  final bool arriving;

  /// Takes [filter] with one choice taken or given up.
  final ValueChanged<PrepFilter>? onFilterChanged;
  final VoidCallback? onSources;

  /// Asked before a closed statistics panel opens, while the statistics
  /// are locked. Null lets every panel open.
  final Future<bool> Function()? onUnlockDetails;

  @override
  State<PrepOverviewTab> createState() => _PrepOverviewTabState();
}

class _PrepOverviewTabState extends State<PrepOverviewTab> {
  final _hold = _Hold();

  @override
  Widget build(BuildContext context) {
    final gutter = EdgeInsets.symmetric(
      horizontal: ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w),
    );
    final s = widget.stats;
    final filter = widget.filter;
    final still = MediaQuery.disableAnimationsOf(context);
    final Widget banner = s != null && filter.narrows
        ? Padding(
            padding: gutter.copyWith(bottom: 16.h),
            child: _FilterBanner(
              filter: filter,
              matching: s.matching,
              total: widget.total,
            ),
          )
        : const SizedBox.shrink();
    final list = CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(top: 6.h),
          sliver: SliverToBoxAdapter(child: widget.header),
        ),
        _HeldSliver(
          hold: _hold,
          child: Padding(
            padding: EdgeInsets.only(bottom: 40.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Opens over the statistics the way a player profile's does.
                if (still)
                  banner
                else
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    alignment: Alignment.topCenter,
                    clipBehavior: Clip.hardEdge,
                    child: banner,
                  ),
                if (widget.heading != null || s != null) ...[
                  Padding(
                    padding: gutter,
                    child:
                        widget.heading ??
                        PrepPerformanceHeader(
                          profile: widget.profile,
                          onSources: widget.onSources,
                        ),
                  ),
                  SizedBox(height: 12.h),
                ],
                if (s == null)
                  ?widget.message
                else
                  Padding(
                    padding: gutter,
                    child: _Settling(
                      // A new source's statistics are a new arrival, not
                      // the old ones changing.
                      key: ValueKey(filter.accountKey ?? ''),
                      stale: widget.stale,
                      arriving: widget.arriving,
                      child: _Statistics(
                        profile: widget.profile,
                        stats: s,
                        filter: filter,
                        onFilterChanged: widget.stale
                            ? null
                            : widget.onFilterChanged,
                        onUnlock: widget.onUnlockDetails,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
    return _Held(
      hold: _hold,
      child: still
          ? list
          : Stack(
              children: [
                list,
                Positioned.fill(
                  child: IgnorePointer(
                    child: _FilterFlash(
                      mark: s == null ? null : filter.labels.join('\n'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// What was last tapped and where it stood, for the list to keep it there.
class _Hold {
  RenderBox? _within;
  RenderBox? _target;
  double? _top;

  /// Notes where [context]'s box stands before a choice changes what is
  /// above it.
  void take(BuildContext context) {
    final box = context.findRenderObject();
    final within = _within;
    if (box is! RenderBox || within == null || !_under(box, within)) return;
    _target = box;
    _top = box.localToGlobal(Offset.zero, ancestor: within).dy;
  }

  /// How far the noted box has moved within [within] since; once.
  double settle(RenderBox within) {
    final target = _target;
    final top = _top;
    _within = within;
    _target = null;
    _top = null;
    if (target == null || top == null || !_under(target, within)) return 0;
    return target.localToGlobal(Offset.zero, ancestor: within).dy - top;
  }

  static bool _under(RenderObject box, RenderObject ancestor) {
    if (!box.attached || !ancestor.attached) return false;
    for (RenderObject? at = box; at != null; at = at.parent) {
      if (identical(at, ancestor)) return true;
    }
    return false;
  }
}

/// Reaches the list's [_Hold] from the choices inside it.
class _Held extends InheritedWidget {
  const _Held({required this.hold, required super.child});
  final _Hold hold;

  static void take(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_Held>()?.hold.take(context);

  @override
  bool updateShouldNotify(_Held old) => !identical(old.hold, hold);
}

/// The statistics as one sliver that keeps a tapped choice where it is.
///
/// A choice changes lists of other groups: a clock leaves fewer openings in
/// the panel above it. Those rows come and go at once, so without this the
/// row under the finger would jump by their height. The scroll offset takes
/// the difference in the same layout, and nothing on screen moves.
class _HeldSliver extends SingleChildRenderObjectWidget {
  const _HeldSliver({required this.hold, super.child});
  final _Hold hold;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHeldSliver(hold);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderHeldSliver renderObject,
  ) => renderObject.hold = hold;
}

class _RenderHeldSliver extends RenderSliverToBoxAdapter {
  _RenderHeldSliver(this.hold);
  _Hold hold;

  @override
  void performLayout() {
    super.performLayout();
    final box = child;
    if (box == null) return;
    final moved = hold.settle(box);
    // The viewport corrects its offset by this and lays out again; the
    // hold is spent by then, so the second pass is the plain one.
    if (moved.abs() >= 0.5) {
      geometry = SliverGeometry(scrollOffsetCorrection: moved);
    }
  }
}

/// Names what About is narrowed to and how many games that leaves: the
/// banner a player's profile opens over its statistics.
class _FilterBanner extends StatelessWidget {
  const _FilterBanner({
    required this.filter,
    required this.matching,
    required this.total,
  });

  final PrepFilter filter;
  final int matching;
  final int? total;

  static const _red = Color(0xFFEF4444);

  @override
  Widget build(BuildContext context) {
    final labels = filter.labels;
    return Container(
      key: const ValueKey('prep_filter_banner'),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: _red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10.br),
        border: Border.all(color: _red.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 8.w,
            height: 8.w,
            decoration: const BoxDecoration(
              color: _red,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              labels.isEmpty ? 'Filtered games' : labels.join(' • '),
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
          ),
          SizedBox(width: 8.w),
          Text(
            total == null
                ? prepGamesLabel(matching)
                : '${prepCount(matching)} of ${prepCount(total!)}',
            key: const ValueKey('prep_filter_count'),
            style: AppTypography.textXsMedium.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.7),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// The wave a player's profile sends down its About when a filter changes.
class _FilterFlash extends StatefulWidget {
  const _FilterFlash({required this.mark});

  /// What is chosen, as text; null while there is nothing to choose among.
  /// A change from one to another is what the wave answers.
  final String? mark;

  @override
  State<_FilterFlash> createState() => _FilterFlashState();
}

class _FilterFlashState extends State<_FilterFlash> {
  double _value = 0;
  Timer? _fall;

  @override
  void didUpdateWidget(_FilterFlash old) {
    super.didUpdateWidget(old);
    if (old.mark == null || widget.mark == null || old.mark == widget.mark) {
      return;
    }
    _value = 1;
    // The spring is turned back almost at once, so the wave only stirs.
    _fall?.cancel();
    _fall = Timer(const Duration(milliseconds: 50), () {
      if (mounted) setState(() => _value = 0);
    });
  }

  @override
  void dispose() {
    _fall?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleMotionBuilder(
    motion: const CupertinoMotion.bouncy(),
    value: _value,
    builder: (context, flash, _) {
      if (flash < 0.01) return const SizedBox.shrink();
      final opacity = flash * 0.35;
      return ShaderMask(
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 1.0),
            Colors.white.withValues(alpha: 0.6),
            Colors.transparent,
          ],
          stops: [0.0, 0.3 + (flash * 0.2), 0.5 + (flash * 0.3)],
        ).createShader(bounds),
        blendMode: BlendMode.dstIn,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                kPrimaryColor.withValues(alpha: opacity),
                kPrimaryColor.withValues(alpha: opacity * 0.7),
                kPrimaryColor.withValues(alpha: opacity * 0.3),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// The ink of a row the other choices leave no games. Only a chosen row is
/// ever one, so it recedes yet still reads: it has to be found to be given
/// up.
const double _kRecededName = 0.5;
const double _kRecededFigure = 0.42;

/// How a chosen thing is marked: a tint behind it, reaching [bleed] past
/// its own box, so marking it moves nothing.
@immutable
class _Mark {
  const _Mark({
    required this.fill,
    required this.radius,
    this.bleed = EdgeInsets.zero,
    this.outline,
    this.outlineWidth = 0,
    this.edge,
    this.glow,
    this.glowBlur = 0,
  });

  final Color fill;
  final double radius;
  final EdgeInsets bleed;

  /// A line around the tint, drawn in as the choice is taken.
  final Color? outline;
  final double outlineWidth;

  /// A bar down the leading side of the tint, as a chosen opening has.
  final Color? edge;

  /// The faint bloom a chosen card has on the dark theme.
  final Color? glow;
  final double glowBlur;

  /// A row: an opening, an opponent, a clock.
  factory _Mark.row(BuildContext context, {required EdgeInsets bleed}) => _Mark(
    fill: kPrimaryColor.withValues(alpha: 0.12),
    radius: 8.br,
    bleed: bleed,
    edge: context.isLightTheme ? context.colors.accentText : kPrimaryColor,
  );
}

/// One thing About can be narrowed to. It gives under the finger, takes its
/// mark when chosen and loses it on a second tap, on the springs a player's
/// profile moves the same on.
class _Pick extends StatefulWidget {
  const _Pick({
    required this.selected,
    required this.onTap,
    required this.mark,
    required this.builder,
    this.active = true,
    this.press = 0.97,
    this.lift = 0,
  });

  final bool selected;

  /// False where the other choices leave it no games: it recedes.
  final bool active;
  final VoidCallback? onTap;
  final _Mark mark;

  /// How small it is under the finger, and how much larger once chosen.
  final double press;
  final double lift;

  /// Builds the thing itself. `chosen` and `lit` run 0..1 as it is taken
  /// and as it is active.
  final Widget Function(BuildContext context, double chosen, double lit)
  builder;

  @override
  State<_Pick> createState() => _PickState();
}

class _PickState extends State<_Pick> {
  bool _down = false;

  void _press(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    final mark = widget.mark;
    final still = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      button: onTap != null,
      selected: widget.selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: onTap == null ? null : (_) => _press(true),
        onTapUp: onTap == null ? null : (_) => _press(false),
        onTapCancel: onTap == null ? null : () => _press(false),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedbackService.buttonPress();
                _Held.take(context);
                onTap();
              },
        child: SingleMotionBuilder(
          motion: const CupertinoMotion.snappy(),
          value: _down ? widget.press : 1.0,
          active: !still,
          builder: (context, pressed, _) => SingleMotionBuilder(
            motion: const CupertinoMotion.bouncy(),
            value: widget.selected ? 1.0 : 0.0,
            active: !still,
            builder: (context, taken, _) => SingleMotionBuilder(
              motion: const CupertinoMotion.bouncy(),
              value: widget.active ? 1.0 : 0.0,
              active: !still,
              builder: (context, lit, _) {
                // The spring carries past its ends; ink and widths do not.
                final chosen = taken.clamp(0.0, 1.0);
                final scale = pressed * (1 + taken * widget.lift);
                return Transform.scale(
                  // At rest it is itself, not a hair off its own size.
                  scale: (scale - 1).abs() < 0.002 ? 1.0 : scale,
                  child: Stack(
                    fit: StackFit.passthrough,
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: -mark.bleed.left,
                        top: -mark.bleed.top,
                        right: -mark.bleed.right,
                        bottom: -mark.bleed.bottom,
                        child: IgnorePointer(
                          child: _MarkBox(mark: mark, taken: taken),
                        ),
                      ),
                      widget.builder(context, chosen, lit.clamp(0.0, 1.0)),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _MarkBox extends StatelessWidget {
  const _MarkBox({required this.mark, required this.taken});
  final _Mark mark;

  /// 0 for not chosen to 1 for chosen, and a little past it as it lands.
  final double taken;

  @override
  Widget build(BuildContext context) {
    if (taken < 0.01) return const SizedBox.shrink();
    final t = taken.clamp(0.0, 1.0);
    final radius = BorderRadius.circular(mark.radius);
    final fill = mark.fill.withValues(alpha: mark.fill.a * t);
    final edge = mark.edge;
    if (edge != null) {
      // Clipped to the tint's own corners, so the bar grows without its
      // ends changing shape.
      return ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            border: taken > 0.1
                ? Border(
                    left: BorderSide(
                      color: edge.withValues(alpha: t * 0.8),
                      width: 3 * taken,
                    ),
                  )
                : null,
          ),
        ),
      );
    }
    final outline = mark.outline;
    final glow = mark.glow;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: outline == null
            ? null
            : Border.all(
                color: outline.withValues(alpha: outline.a * t),
                width: mark.outlineWidth * taken,
              ),
        // Paper gets no bloom.
        boxShadow: glow != null && taken > 0.5 && !context.isLightTheme
            ? [
                BoxShadow(
                  color: glow.withValues(alpha: glow.a * t),
                  blurRadius: mark.glowBlur * t,
                ),
              ]
            : null,
      ),
    );
  }
}

/// How statistics read while they are not the chosen source's own: faint
/// enough to recede, clear enough to stay legible.
const double _kFaint = 0.45;

/// Statistics at full strength once they are the chosen source's own. Those
/// of the source before it wait faint and out of reach; those that replace
/// them settle in from the same faintness, so the change is one movement.
class _Settling extends StatelessWidget {
  const _Settling({
    super.key,
    required this.stale,
    required this.arriving,
    required this.child,
  });

  final bool stale;
  final bool arriving;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: stale,
      child: SingleMotionBuilder(
        value: stale ? 1.0 : 0.0,
        from: arriving ? 1.0 : null,
        motion: kPrepToggleMotion,
        active: !MediaQuery.disableAnimationsOf(context),
        child: child,
        builder: (context, t, child) {
          final faint = t.clamp(0.0, 1.0);
          // At rest the statistics are themselves, not a layer around them.
          if (faint < 0.002) return child!;
          return Opacity(opacity: 1 - (1 - _kFaint) * faint, child: child);
        },
      ),
    );
  }
}

/// Everything About knows about one set of games.
class _Statistics extends StatelessWidget {
  const _Statistics({
    required this.profile,
    required this.stats,
    required this.filter,
    this.onFilterChanged,
    this.onUnlock,
  });

  final PrepProfile profile;
  final PrepStats stats;
  final PrepFilter filter;
  final ValueChanged<PrepFilter>? onFilterChanged;

  /// Asked before a panel opens; see [_DetailsPanel.onUnlock].
  final Future<bool> Function()? onUnlock;

  /// The source every rating figure is on the scale of, named as far as the
  /// profile needs: its site, and its username where the profile holds two
  /// of that site.
  String? get _scale {
    final account = profile.accounts
        .where(
          (a) =>
              stats.ratingPath?.endsWith(PrepRepository.gamesFileName(a)) ??
              false,
        )
        .firstOrNull;
    if (account == null) return stats.ratingSource?.label;
    return profile.accounts.where((a) => a.source == account.source).length > 1
        ? '${account.source.label} · ${prepAccountName(account)}'
        : account.source.label;
  }

  /// What a tap on a choice does: null while nothing may be chosen.
  VoidCallback? _take(PrepFilter Function() next) {
    final changed = onFilterChanged;
    return changed == null ? null : () => changed(next());
  }

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final mine = profile.kind == PrepKind.mine;
    final scale = _scale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OverallSummary(
          stats: s,
          chosen: filter.outcome,
          onOutcome: onFilterChanged == null
              ? null
              : (outcome) => onFilterChanged!(filter.toggleOutcome(outcome)),
        ),
        SizedBox(height: 20.h),
        _DetailsPanel(
          onUnlock: onUnlock,
          title: 'Performance by colour',
          children: [
            for (final side in [PrepSide.white, PrepSide.black]) ...[
              if (side == PrepSide.black) SizedBox(height: 20.h),
              _ColourRow(
                label: switch ((mine, side)) {
                  (true, PrepSide.white) => 'As White',
                  (true, _) => 'As Black',
                  (false, PrepSide.white) => 'Their White',
                  (false, _) => 'Their Black',
                },
                tally: side == PrepSide.white ? s.asWhite : s.asBlack,
                games: side == PrepSide.white ? s.whiteGames : s.blackGames,
                selected: filter.side == side,
                onTap: _take(() => filter.toggleSide(side)),
              ),
            ],
          ],
        ),
        if (s.whiteOpenings.isNotEmpty || s.blackOpenings.isNotEmpty) ...[
          SizedBox(height: 12.h),
          _DetailsPanel(
            onUnlock: onUnlock,
            title: 'Opening repertoire',
            children: [
              for (final side in [PrepSide.white, PrepSide.black])
                if ((side == PrepSide.white ? s.whiteOpenings : s.blackOpenings)
                    .isNotEmpty) ...[
                  Text(
                    side == PrepSide.white ? 'As White' : 'As Black',
                    style: AppTypography.textXsMedium.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                  SizedBox(height: 12.h),
                  for (final line
                      in side == PrepSide.white
                          ? s.whiteOpenings
                          : s.blackOpenings)
                    _LineRow(
                      title: line.name,
                      meta: line.eco,
                      tally: line.tally,
                      games: line.games,
                      selected: filter.holdsOpening(side, line.eco),
                      onTap: line.eco == null
                          ? null
                          : _take(() => filter.toggleOpening(side, line.eco!)),
                    ),
                ],
            ],
          ),
        ],
        if (s.clocks.isNotEmpty) ...[
          SizedBox(height: 12.h),
          _DetailsPanel(
            onUnlock: onUnlock,
            title: 'Time controls',
            children: [
              _ClockShare(
                clocks: s.clocks,
                source: filter.source,
                chosen: filter.speed,
                onTap: onFilterChanged == null
                    ? null
                    : (speed) => onFilterChanged!(filter.toggleSpeed(speed)),
              ),
            ],
          ),
        ],
        if (s.ratingHistory.length >= 2) ...[
          SizedBox(height: 12.h),
          _DetailsPanel(
            onUnlock: onUnlock,
            // Whose rating it is, wherever the profile has more than one.
            title: [
              'Rating history',
              if (profile.accounts.length > 1) ?scale,
              ?s.ratingSpeed?.labelFor(s.ratingSource),
            ].join(' · '),
            children: [PrepRatingHistory(points: s.ratingHistory)],
          ),
        ],
        SizedBox(height: 12.h),
        _DetailsPanel(
          onUnlock: onUnlock,
          title: 'More statistics',
          children: [
            PrepStatStrip(
              items: [
                ('Peak rating', s.peakRating?.toString() ?? '–'),
                ('Rating now', s.currentRating?.toString() ?? '–'),
                ('Performance', s.performance?.toString() ?? '–'),
              ],
            ),
            // Several sources are several rating scales: these follow one.
            if (s.accounts > 1 && scale != null) ...[
              SizedBox(height: 8.h),
              Text(
                'Rating figures are from $scale games only: rating scales '
                'differ between sources.',
                key: const ValueKey('prep_rating_scale'),
                style: AppTypography.textXsRegular.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
            if (s.decisiveRate case final rate?) ...[
              SizedBox(height: 12.h),
              Text(
                '${prepCount(s.decisive)} decisive games · ${(rate * 100).round()}% decisive',
                style: AppTypography.textXsRegular.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
            if (s.averageOpponent != null) ...[
              SizedBox(height: s.decisiveRate == null ? 12.h : 4.h),
              Text(
                'Average opponent rating ${s.averageOpponent}',
                style: AppTypography.textXsRegular.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
            if (s.opponents.isNotEmpty) ...[
              SizedBox(height: 24.h),
              Text('Most played opponents', style: AppTypography.textSmBold),
              SizedBox(height: 12.h),
              for (final o in s.opponents)
                _LineRow(
                  title: o.name,
                  meta: o.rating == null ? null : 'avg ${o.rating}',
                  tally: o.tally,
                  games: o.games,
                  selected: filter.holdsOpponent(o.name),
                  onTap: _take(() => filter.toggleOpponent(o.name)),
                ),
            ],
            // A chosen year keeps its bar, alone if need be, to be given
            // up by.
            if (s.byYear.length > 1 ||
                (s.byYear.isNotEmpty && filter.year != null)) ...[
              SizedBox(height: 24.h),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Games by year',
                      style: AppTypography.textSmBold,
                    ),
                  ),
                  Text(
                    '${prepCount(s.byYear.fold(0, (n, y) => n + y.total))} total',
                    style: AppTypography.textXsRegular.copyWith(
                      color: context.colors.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12.h),
              _YearBars(
                years: s.byYear,
                chosen: filter.year,
                onYear: onFilterChanged == null
                    ? null
                    : (year) => onFilterChanged!(filter.toggleYear(year)),
              ),
            ],
            SizedBox(height: 24.h),
            Text('Game length', style: AppTypography.textSmBold),
            SizedBox(height: 12.h),
            _LengthBars(
              lengths: s.lengths,
              chosen: filter.length,
              onLength: onFilterChanged == null
                  ? null
                  : (length) => onFilterChanged!(filter.toggleLength(length)),
            ),
            if (s.overall.total < s.games) ...[
              SizedBox(height: 16.h),
              Text(
                '${prepCount(s.games - s.overall.total)} games are excluded from results because they are unfinished or the player name did not match.',
                style: AppTypography.textXsRegular.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// About's heading. A profile with several sources also carries the switch
/// between reading them together and reading one alone, and names the choice.
class PrepPerformanceHeader extends StatelessWidget {
  const PrepPerformanceHeader({
    super.key,
    required this.profile,
    this.accountKey,
    this.onAccount,
    this.onSources,
    this.progress,
  });

  final PrepProfile profile;
  final String? accountKey;
  final ValueChanged<String?>? onAccount;
  final VoidCallback? onSources;

  /// What reading the chosen source's games is doing, said in place of its
  /// name until they are read.
  final String? progress;

  static const _title = 'Overall Performance';

  @override
  Widget build(BuildContext context) {
    final onAccount = this.onAccount;
    if (onAccount == null || profile.accounts.length < 2) {
      return Row(
        children: [
          Expanded(child: Text(_title, style: AppTypography.textSmBold)),
          if (profile.accounts.isNotEmpty)
            IconButton(
              tooltip: 'Manage sources',
              onPressed: onSources,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              icon: PrepSourceMarks(
                sources: profile.accounts.map((a) => a.source),
                size: 16.sp,
              ),
            ),
        ],
      );
    }
    // Same order as the My Games source list.
    final accounts = [
      for (final source in PrepSource.values)
        ...profile.accounts.where((a) => a.source == source),
    ];
    final chosen = accounts.where((a) => a.key == accountKey).firstOrNull;
    final caption = AppTypography.textXsRegular.copyWith(
      color: context.colors.textSecondary,
    );
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_title, style: AppTypography.textSmBold),
        if (progress case final reading?)
          PrepShimmerText(
            reading,
            key: const ValueKey('prep_switch_progress'),
            style: caption.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          )
        else
          Text(
            chosen == null
                ? 'Combined · ${accounts.length} sources'
                : '${chosen.source.label} · ${prepAccountName(chosen)}',
            key: const ValueKey('prep_switch_caption'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: caption,
          ),
      ],
    );
    final choice = PrepAccountSwitch(
      accounts: accounts,
      selectedKey: chosen?.key,
      onSelected: onAccount,
    );
    return LayoutBuilder(
      builder: (context, box) {
        final title = TextPainter(
          text: TextSpan(text: _title, style: AppTypography.textSmBold),
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final titleWidth = title.width;
        title.dispose();
        // Decided by the title alone, so choosing a source with a longer
        // name never moves the switch to another line.
        final beside =
            titleWidth + 12.w + PrepAccountSwitch.widthOf(context, accounts) <=
            box.maxWidth;
        if (beside) {
          return Row(
            children: [
              Expanded(child: heading),
              SizedBox(width: 12.w),
              choice,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading,
            SizedBox(height: 4.h),
            // More sources than the line holds scroll under the heading,
            // running off the screen's edge rather than being cut at the
            // margin.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: choice,
            ),
          ],
        );
      },
    );
  }
}

/// A single surface replaces the headline strip and three result cards.
class _OverallSummary extends StatelessWidget {
  const _OverallSummary({required this.stats, this.chosen, this.onOutcome});
  final PrepStats stats;

  /// The result About is narrowed to, if any.
  final PrepOutcome? chosen;
  final ValueChanged<PrepOutcome>? onOutcome;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final score = stats.overall.score;
    return Container(
      padding: EdgeInsets.all(16.sp),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12.br),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _SummaryValue(
                  label: 'Games analyzed',
                  value: prepCount(stats.overall.total),
                ),
              ),
              Expanded(
                child: _SummaryValue(
                  label: 'Score',
                  value: score == null ? '–' : '${(score * 100).round()}%',
                  end: true,
                ),
              ),
            ],
          ),
          SizedBox(height: 20.h),
          PrepResultBar(tally: stats.overall, height: 8),
          SizedBox(height: 16.h),
          Row(
            children: [
              for (final outcome in [
                PrepOutcome.win,
                PrepOutcome.draw,
                PrepOutcome.loss,
              ])
                Expanded(
                  child: _result(context, outcome, switch (outcome) {
                    PrepOutcome.win => colors.accentText,
                    PrepOutcome.draw => colors.textSecondary,
                    _ => colors.danger,
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _result(BuildContext context, PrepOutcome outcome, Color ink) {
    final onOutcome = this.onOutcome;
    return _Pick(
      selected: chosen == outcome,
      onTap: onOutcome == null ? null : () => onOutcome(outcome),
      press: 0.95,
      lift: 0.02,
      // The stat box of a player's profile, drawn only once chosen: it
      // reaches into the space around the count, which stays where it was.
      mark: _Mark(
        fill: ink.withValues(alpha: 0.15),
        radius: 8.br,
        bleed: EdgeInsets.fromLTRB(-4.w, 6.h, -4.w, 6.h),
        outline: ink,
        outlineWidth: 1.5,
        glow: ink.withValues(alpha: 0.2),
        glowBlur: 8,
      ),
      builder: (context, _, _) => Padding(
        padding: EdgeInsets.symmetric(vertical: 4.h),
        child: Column(
          children: [
            Text(
              prepCount(switch (outcome) {
                PrepOutcome.win => stats.overall.wins,
                PrepOutcome.draw => stats.overall.draws,
                _ => stats.overall.losses,
              }),
              style: AppTypography.textLgBold.copyWith(
                color: ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              switch (outcome) {
                PrepOutcome.win => 'Wins',
                PrepOutcome.draw => 'Draws',
                _ => 'Losses',
              },
              style: AppTypography.textXsRegular.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({
    required this.label,
    required this.value,
    this.end = false,
  });
  final String label;
  final String value;
  final bool end;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: AppTypography.textXsRegular.copyWith(
          color: context.colors.textSecondary,
        ),
      ),
      SizedBox(height: 4.h),
      Text(
        value,
        style: AppTypography.textXlBold.copyWith(
          color: context.colors.textPrimary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
}

/// Uses the platform expansion control; details never crowd the first view.
class _DetailsPanel extends StatefulWidget {
  /// Keyed by [title], so a panel keeps its own state and remembered
  /// opening as the panels before it come and go.
  _DetailsPanel({required this.title, required this.children, this.onUnlock})
    : super(key: PageStorageKey<String>(title));
  final String title;
  final List<Widget> children;

  /// Asked before the panel opens, while the statistics are locked: it
  /// opens once this allows it. Null lets it open at once.
  final Future<bool> Function()? onUnlock;

  @override
  State<_DetailsPanel> createState() => _DetailsPanelState();
}

class _DetailsPanelState extends State<_DetailsPanel> {
  final _controller = ExpansibleController();
  bool _asking = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// A locked panel that starts to open closes in the same tap, before a
  /// frame shows it move, and opens once access is granted. One restored
  /// open while it is built was opened with access, and stays so.
  void _changed(bool open) {
    final unlock = widget.onUnlock;
    if (!open || unlock == null || _asking) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      return;
    }
    _controller.collapse();
    unawaited(_ask(unlock));
  }

  Future<void> _ask(Future<bool> Function() unlock) async {
    _asking = true;
    try {
      if (await unlock() && mounted) _controller.expand();
    } finally {
      _asking = false;
    }
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    controller: _controller,
    onExpansionChanged: _changed,
    title: Text(widget.title, style: AppTypography.textSmMedium),
    backgroundColor: context.colors.surface,
    collapsedBackgroundColor: context.colors.surface,
    textColor: context.colors.textPrimary,
    collapsedTextColor: context.colors.textPrimary,
    iconColor: context.colors.iconSecondary,
    collapsedIconColor: context.colors.iconSecondary,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.br)),
    collapsedShape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12.br),
    ),
    tilePadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 2.h),
    childrenPadding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 16.h),
    children: [
      // The tile stores its open flag (a bool) under the panel's key. A
      // scroll view inside with no key of its own resolves to that same
      // identifier and reads the bool as its offset: "type 'bool' is not a
      // subtype of type 'double?'" (CHESSEVER-24D/249). This key gives
      // everything inside an identifier of its own.
      Column(
        key: PageStorageKey<String>('${widget.title}/details'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: widget.children,
      ),
    ],
  );
}

class _ColourRow extends StatelessWidget {
  const _ColourRow({
    required this.label,
    required this.tally,
    required this.games,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final PrepTally tally;

  /// Every game with the colour, unfinished ones too.
  final int games;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = colors.accentText;
    return _Pick(
      selected: selected,
      onTap: onTap,
      press: 0.96,
      // A player profile's colour card, drawn only once chosen.
      mark: _Mark(
        fill: accent.withValues(alpha: 0.12),
        radius: 12.br,
        bleed: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
        outline: accent,
        outlineWidth: 2,
        glow: accent.withValues(alpha: 0.15),
        glowBlur: 10,
      ),
      builder: (context, chosen, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.textSmMedium.copyWith(
                    color: Color.lerp(colors.textPrimary, accent, chosen * 0.5),
                  ),
                ),
              ),
              Text(
                tally.score == null ? '–' : '${(tally.score! * 100).round()}%',
                style: AppTypography.textLgBold.copyWith(
                  color: Color.lerp(colors.textPrimary, accent, chosen * 0.3),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          PrepResultBar(tally: tally, height: 4),
          SizedBox(height: 8.h),
          Wrap(
            spacing: 12.w,
            runSpacing: 4.h,
            children: [
              Text(
                prepGamesLabel(games),
                style: AppTypography.textXsRegular.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              PrepTallyText(tally: tally),
            ],
          ),
        ],
      ),
    );
  }
}

/// A named row with its game count, score and result bar: an opening, an
/// opponent.
class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.title,
    required this.tally,
    required this.games,
    this.meta,
    this.selected = false,
    this.onTap,
  });

  final String title;
  final String? meta;
  final PrepTally tally;

  /// Every game in the row, unfinished ones too.
  final int games;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final score = tally.score;
    return _Pick(
      selected: selected,
      // Only a chosen row is listed without games: the other choices left
      // it none, and it waits to be given up.
      active: games > 0,
      onTap: onTap,
      lift: 0.01,
      mark: _Mark.row(
        context,
        // Half of the gap under the row, so the tint sits evenly around it.
        bleed: EdgeInsets.fromLTRB(8.w, 6.h, 8.w, -6.h),
      ),
      builder: (context, chosen, lit) {
        final faded = 1 - lit;
        return Padding(
          padding: EdgeInsets.only(bottom: 12.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: title),
                          if (meta != null)
                            TextSpan(
                              text: '  $meta',
                              style: TextStyle(
                                color: Color.lerp(
                                  colors.textTertiary,
                                  context.textInk(_kRecededFigure),
                                  faded,
                                ),
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.textSmMedium.copyWith(
                        color: Color.lerp(
                          Color.lerp(
                            colors.textPrimary,
                            colors.accentText,
                            chosen * 0.6,
                          ),
                          context.textInk(_kRecededName),
                          faded,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    '${prepCount(games)} · ${score == null ? '–' : '${(score * 100).round()}%'}',
                    style: AppTypography.textXsMedium.copyWith(
                      color: Color.lerp(
                        Color.lerp(
                          colors.textSecondary,
                          colors.accentText,
                          chosen * 0.4,
                        ),
                        context.textInk(_kRecededFigure),
                        faded,
                      ),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 6.h),
              RestAwareOpacity(
                opacity: 1 - 0.6 * faded,
                child: PrepResultBar(tally: tally, height: 4),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _YearBars extends StatelessWidget {
  const _YearBars({required this.years, this.chosen, this.onYear});
  final List<PrepYearLine> years;
  final int? chosen;
  final ValueChanged<int>? onYear;

  /// How many years fit before the row scrolls.
  static const _fit = 10;

  @override
  Widget build(BuildContext context) {
    final most = years.fold<int>(1, (m, y) => math.max(m, y.total));
    final onYear = this.onYear;
    Widget bar(PrepYearLine y) => _Pick(
      selected: y.year == chosen,
      onTap: onYear == null ? null : () => onYear(y.year),
      press: 0.95,
      mark: _Mark(fill: kPrimaryColor.withValues(alpha: 0.12), radius: 6.br),
      builder: (context, taken, _) => _Bar(
        fraction: y.total / most,
        tally: y.tally,
        rest: y.total - y.tally.total,
        label: "'${(y.year % 100).toString().padLeft(2, '0')}",
        value: prepCount(y.total),
        chosen: taken,
      ),
    );
    return SizedBox(
      height: 120.h,
      child: years.length <= _fit
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [for (final y in years) Expanded(child: bar(y))],
            )
          // Every year is kept; the newest stay in view and the rest scroll.
          : LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final y in years)
                      SizedBox(
                        width: constraints.maxWidth / _fit,
                        height: 120.h,
                        child: bar(y),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// How the games divide by clock. A row narrows About to its clock.
class _ClockShare extends StatelessWidget {
  const _ClockShare({
    required this.clocks,
    required this.onTap,
    this.source,
    this.chosen,
  });
  final List<(PrepTimeControl?, int)> clocks;
  final PrepSource? source;
  final PrepTimeControl? chosen;
  final ValueChanged<PrepTimeControl>? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final total = clocks.fold<int>(0, (n, c) => n + c.$2);
    final onTap = this.onTap;
    return Column(
      children: [
        for (final (speed, count) in clocks)
          _Pick(
            selected: speed != null && speed == chosen,
            active: count > 0,
            onTap: speed == null || onTap == null ? null : () => onTap(speed),
            lift: 0.01,
            mark: _Mark.row(
              context,
              bleed: EdgeInsets.symmetric(horizontal: 8.w),
            ),
            builder: (context, taken, lit) => ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      speed?.labelFor(source) ?? 'Unknown',
                      style: AppTypography.textSmMedium.copyWith(
                        color: Color.lerp(
                          Color.lerp(
                            colors.textPrimary,
                            colors.accentText,
                            taken * 0.6,
                          ),
                          context.textInk(_kRecededName),
                          1 - lit,
                        ),
                      ),
                    ),
                  ),
                  Text(
                    '${prepCount(count)} · '
                    '${total == 0 ? 0 : (count * 100 / total).round()}%',
                    style: AppTypography.textXsMedium.copyWith(
                      color: Color.lerp(
                        Color.lerp(
                          colors.textSecondary,
                          colors.accentText,
                          taken * 0.4,
                        ),
                        context.textInk(_kRecededFigure),
                        1 - lit,
                      ),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _LengthBars extends StatelessWidget {
  const _LengthBars({required this.lengths, this.chosen, this.onLength});
  final List<int> lengths;

  /// The length About is narrowed to: an index into [_labels].
  final int? chosen;
  final ValueChanged<int>? onLength;

  static const _labels = PrepStats.lengthLabels;

  @override
  Widget build(BuildContext context) {
    final most = lengths.fold<int>(1, math.max);
    final onLength = this.onLength;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 100.h,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < lengths.length; i++)
                Expanded(
                  child: _Pick(
                    selected: i == chosen,
                    onTap: onLength == null ? null : () => onLength(i),
                    press: 0.95,
                    mark: _Mark(
                      fill: kPrimaryColor.withValues(alpha: 0.12),
                      radius: 6.br,
                    ),
                    builder: (context, taken, _) => _Bar(
                      fraction: lengths[i] / most,
                      label: _labels[i],
                      value: prepCount(lengths[i]),
                      chosen: taken,
                    ),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: 6.h),
        Text(
          'Moves per game',
          style: AppTypography.textXsRegular.copyWith(
            color: context.colors.textTertiary,
          ),
        ),
      ],
    );
  }
}

/// One column of a small bar chart; split by result when [tally] is given.
class _Bar extends StatelessWidget {
  const _Bar({
    required this.fraction,
    required this.label,
    required this.value,
    this.tally,
    this.rest = 0,
    this.chosen = 0,
  });

  final double fraction;
  final String label;
  final String value;
  final PrepTally? tally;

  /// Games without a result, drawn above the results as their own segment.
  final int rest;

  /// 0..1 as the column is taken as the choice.
  final double chosen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = tally;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 3.w),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            value,
            maxLines: 1,
            style: AppTypography.textXxsRegular.copyWith(
              color: Color.lerp(
                colors.textSecondary,
                colors.accentText,
                chosen,
              ),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          SizedBox(height: 3.h),
          Flexible(
            child: FractionallySizedBox(
              heightFactor: fraction.clamp(0.02, 1.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3.br),
                child: t == null || t.total + rest == 0
                    ? ColoredBox(
                        color: colors.textPrimary.withValues(alpha: 0.35),
                        child: const SizedBox.expand(),
                      )
                    : Column(
                        children: [
                          if (rest > 0)
                            Expanded(
                              flex: rest,
                              child: ColoredBox(
                                color: colors.textPrimary.withValues(
                                  alpha: 0.18,
                                ),
                                child: const SizedBox.expand(),
                              ),
                            ),
                          if (t.losses > 0)
                            Expanded(
                              flex: t.losses,
                              child: ColoredBox(
                                color: colors.danger,
                                child: const SizedBox.expand(),
                              ),
                            ),
                          if (t.draws > 0)
                            Expanded(
                              flex: t.draws,
                              child: ColoredBox(
                                color: colors.textTertiary,
                                child: const SizedBox.expand(),
                              ),
                            ),
                          if (t.wins > 0)
                            Expanded(
                              flex: t.wins,
                              child: ColoredBox(
                                color: colors.brand,
                                child: const SizedBox.expand(),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            label,
            maxLines: 1,
            style: AppTypography.textXxsRegular.copyWith(
              color: Color.lerp(colors.textTertiary, colors.accentText, chosen),
            ),
          ),
        ],
      ),
    );
  }
}
