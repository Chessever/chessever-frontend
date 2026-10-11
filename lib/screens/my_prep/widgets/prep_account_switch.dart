import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// Whose games a profile reads: every source together, or one of them. The
/// thumb rests on the choice, and the sources it leaves out dim.
///
/// A source is its mark. Where a profile holds several sources of one kind,
/// their marks would be alike, so each of those is named beside its mark.
class PrepAccountSwitch extends StatelessWidget {
  const PrepAccountSwitch({
    super.key,
    required this.accounts,
    required this.selectedKey,
    required this.onSelected,
  });

  /// In the order the profile lists its sources.
  final List<PrepAccount> accounts;

  /// The chosen source's key, or null for every source together.
  final String? selectedKey;
  final ValueChanged<String?> onSelected;

  static const _all = 'All';
  static const _mark = 18.0;

  /// A segment holding a mark alone, and the least any segment is wide.
  static const _segment = 38.0;
  static const _thumb = 30.0;

  /// The thumb's margin inside the track, on every side.
  static const _inset = 3.0;

  /// Space either side of a segment's text, and between a mark and its name.
  static const _pad = 10.0;
  static const _gap = 6.0;

  /// The widest a name is written before it is cut short.
  static const _nameLimit = 96.0;

  /// How wide the switch lays out for [accounts].
  static double widthOf(BuildContext context, List<PrepAccount> accounts) =>
      _Metrics.of(context, accounts).width;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final still = MediaQuery.disableAnimationsOf(context);
    final metrics = _Metrics.of(context, accounts);
    final chosen = accounts.indexWhere((a) => a.key == selectedKey);
    TextStyle text(bool lit) => AppTypography.textXsMedium.copyWith(
      color: lit ? colors.textPrimary : colors.textSecondary,
    );

    return SizedBox(
      width: metrics.width,
      // The track is slimmer than a tap target; the segments are not.
      height: math.max(kMinInteractiveDimension, metrics.thumb + _inset * 2),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: metrics.thumb + _inset * 2,
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(10.br),
            ),
          ),
          Positioned.fill(
            left: _inset,
            right: _inset,
            child: SingleMotionBuilder(
              // Segment 0 is every source together; a source follows at its
              // place + 1.
              value: chosen + 1.0,
              motion: kPrepToggleMotion,
              active: !still,
              builder: (context, t, _) {
                final at = t.clamp(0.0, accounts.length.toDouble());
                final from = at.floor();
                final to = at.ceil();
                return CustomPaint(
                  painter: _ThumbPainter(
                    left: lerpDouble(
                      metrics.left(from),
                      metrics.left(to),
                      at - from,
                    )!,
                    width: lerpDouble(
                      metrics.widths[from],
                      metrics.widths[to],
                      at - from,
                    )!,
                    height: metrics.thumb,
                    radius: 7.br,
                    // A step off the track in the ink's own direction, as a
                    // pressed card button takes.
                    color: colors.textPrimary.withValues(
                      alpha: context.isLightTheme ? 0.08 : 0.12,
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _inset),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Segment(
                  key: const ValueKey('prep_switch_all'),
                  width: metrics.widths.first,
                  label: 'All sources combined',
                  selected: chosen < 0,
                  onTap: () => onSelected(null),
                  child: Text(_all, maxLines: 1, style: text(chosen < 0)),
                ),
                for (final (i, account) in accounts.indexed)
                  _Segment(
                    key: ValueKey('prep_switch_${account.key}'),
                    width: metrics.widths[i + 1],
                    label:
                        '${prepAccountName(account)} on ${account.source.label}',
                    selected: i == chosen,
                    onTap: () => onSelected(account.key),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Dimmed(
                          // Together every source is read, so every mark is
                          // lit.
                          lit: chosen < 0 || i == chosen,
                          still: still,
                          child: PrepSourceMark(
                            source: account.source,
                            size: _mark,
                          ),
                        ),
                        if (metrics.names[i] case final name?) ...[
                          const SizedBox(width: _gap),
                          SizedBox(
                            width: name,
                            child: Text(
                              prepAccountName(account),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text(chosen < 0 || i == chosen),
                            ),
                          ),
                        ],
                      ],
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

/// Where the switch's segments fall. Text is measured, so large text widens
/// and heightens its segment rather than being clipped by it.
class _Metrics {
  const _Metrics._(this.widths, this.names, this.thumb);

  factory _Metrics.of(BuildContext context, List<PrepAccount> accounts) {
    final scaler = MediaQuery.textScalerOf(context);
    Size measure(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: AppTypography.textXsMedium),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final size = painter.size;
      painter.dispose();
      return size;
    }

    final all = measure(PrepAccountSwitch._all);
    final perSource = <PrepSource, int>{};
    for (final account in accounts) {
      perSource.update(account.source, (n) => n + 1, ifAbsent: () => 1);
    }
    final names = [
      for (final account in accounts)
        perSource[account.source]! > 1
            ? math.min(
                // A rounding difference may only ever leave spare room.
                measure(prepAccountName(account)).width.ceilToDouble(),
                PrepAccountSwitch._nameLimit,
              )
            : null,
    ];
    return _Metrics._(
      [
        math.max(
          PrepAccountSwitch._segment,
          all.width + PrepAccountSwitch._pad * 2,
        ),
        for (final name in names)
          name == null
              ? PrepAccountSwitch._segment
              : PrepAccountSwitch._pad * 2 +
                    PrepAccountSwitch._mark +
                    PrepAccountSwitch._gap +
                    name,
      ],
      names,
      math.max(PrepAccountSwitch._thumb, all.height + 8),
    );
  }

  /// Every segment's width: all sources first, then each source.
  final List<double> widths;

  /// How wide each source's name is written, or null for a mark alone.
  final List<double?> names;

  /// The thumb's height.
  final double thumb;

  double get width =>
      widths.fold(PrepAccountSwitch._inset * 2, (sum, w) => sum + w);

  /// Where segment [index] starts, from the thumb's own left edge.
  double left(int index) => widths.take(index).fold(0, (sum, w) => sum + w);
}

/// One choice: a full-height tap target around its mark or label. Chosen in
/// a switch too wide for its line, it scrolls itself into view, and no
/// further.
class _Segment extends StatefulWidget {
  const _Segment({
    super.key,
    required this.width,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final double width;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  /// The spring's first second, played over that second.
  static final Curve _glide = kPrepToggleMotion.toCurve;

  @override
  void initState() {
    super.initState();
    if (widget.selected) _reveal(glide: false);
  }

  @override
  void didUpdateWidget(_Segment old) {
    super.didUpdateWidget(old);
    if (widget.selected && !old.selected) _reveal(glide: true);
  }

  void _reveal({required bool glide}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Only the switch's own line moves, never the page it sits in.
      final line = Scrollable.maybeOf(context, axis: Axis.horizontal);
      final box = context.findRenderObject();
      if (line == null || box == null) return;
      // At most one of the two finds the segment past its edge.
      for (final edge in const [
        ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      ]) {
        line.position.ensureVisible(
          box,
          alignmentPolicy: edge,
          duration: glide && !MediaQuery.disableAnimationsOf(context)
              ? const Duration(seconds: 1)
              : Duration.zero,
          curve: _glide,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: Tooltip(
        message: widget.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (widget.selected) return;
            HapticFeedbackService.selection();
            widget.onTap();
          },
          child: SizedBox(
            width: widget.width,
            child: Center(child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// A source's mark at full strength while its games are read, faint while
/// another source is read alone.
class _Dimmed extends StatelessWidget {
  const _Dimmed({required this.lit, required this.still, required this.child});

  final bool lit;
  final bool still;
  final Widget child;

  static const _faint = 0.38;

  @override
  Widget build(BuildContext context) {
    return SingleMotionBuilder(
      value: lit ? 1.0 : 0.0,
      motion: kPrepToggleMotion,
      active: !still,
      child: child,
      builder: (context, t, child) {
        final k = t.clamp(0.0, 1.0);
        // At rest a lit mark is the mark itself, not a layer around it.
        if (k > 0.998) return child!;
        return Opacity(opacity: _faint + (1 - _faint) * k, child: child);
      },
    );
  }
}

class _ThumbPainter extends CustomPainter {
  const _ThumbPainter({
    required this.left,
    required this.width,
    required this.height,
    required this.radius,
    required this.color,
  });

  final double left;
  final double width;
  final double height;
  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(left, (size.height - height) / 2, width, height),
        Radius.circular(radius),
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_ThumbPainter old) =>
      old.left != left ||
      old.width != width ||
      old.height != height ||
      old.radius != radius ||
      old.color != color;
}
