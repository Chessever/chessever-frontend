import 'dart:async';

import 'package:chessever2/screens/feed/race/puzzle_rating_range.dart';
import 'package:chessever2/screens/feed/widgets/feed_action_row.dart';
import 'package:chessever2/screens/feed/widgets/feed_glyphs.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/game_filter/wheel_range_filter.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// The puzzle difficulty picker: the shared presets, and a custom rating
/// range on two wheels. One sheet for the Feed's puzzles and Puzzle Race,
/// both reading [puzzleRatingRangeProvider].
///
/// A preset applies at once and closes the sheet. A custom range applies
/// when the sheet closes, so turning a wheel does not reload the puzzles on
/// every tick.
Future<void> showPuzzleDifficultySheet(
  BuildContext context,
  WidgetRef ref,
) async {
  HapticFeedbackService.selection();
  final notifier = ref.read(puzzleRatingRangeProvider.notifier);
  final initial = ref.read(puzzleRatingRangeProvider);
  PuzzleRatingRange? custom;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: context.colors.scrim,
    builder: (sheetContext) => PuzzleDifficultySheet(
      initial: initial,
      onPreset: (preset) {
        HapticFeedbackService.selection();
        custom = null;
        unawaited(notifier.choose(preset));
        Navigator.of(sheetContext).pop();
      },
      onCustom: (range) => custom = range,
    ),
  );
  final range = custom;
  if (range != null && range != initial) unawaited(notifier.set(range));
}

/// The body of [showPuzzleDifficultySheet].
class PuzzleDifficultySheet extends StatefulWidget {
  const PuzzleDifficultySheet({
    required this.initial,
    required this.onPreset,
    required this.onCustom,
    super.key,
  });

  final PuzzleRatingRange initial;
  final ValueChanged<PuzzleRatingPreset> onPreset;

  /// A custom range the wheels settled on, applied when the sheet closes.
  final ValueChanged<PuzzleRatingRange> onCustom;

  @override
  State<PuzzleDifficultySheet> createState() => _PuzzleDifficultySheetState();
}

class _PuzzleDifficultySheetState extends State<PuzzleDifficultySheet> {
  late PuzzleRatingRange _range = widget.initial;
  late bool _customOpen = widget.initial.preset == null;

  String _label(PuzzleRatingRange range) => '${range.min}–${range.max}';

  void _apply(PuzzleRatingRange next) {
    if (next == _range) return;
    setState(() => _range = next);
    widget.onCustom(next);
  }

  /// [_range] with one bound moved [by] points; the other gives way to keep
  /// the minimum span, as it does when the wheels cross.
  PuzzleRatingRange _nudged({required bool low, required int by}) {
    var lo = _range.min;
    var hi = _range.max;
    if (low) {
      lo = (lo + by)
          .clamp(
            kPuzzleRatingFloor,
            kPuzzleRatingCeiling - kPuzzleRatingMinSpan,
          )
          .toInt();
      if (hi - lo < kPuzzleRatingMinSpan) hi = lo + kPuzzleRatingMinSpan;
    } else {
      hi = (hi + by)
          .clamp(
            kPuzzleRatingFloor + kPuzzleRatingMinSpan,
            kPuzzleRatingCeiling,
          )
          .toInt();
      if (hi - lo < kPuzzleRatingMinSpan) lo = hi - kPuzzleRatingMinSpan;
    }
    return normalizePuzzleRatingRange(lo, hi);
  }

  /// One wheel as a screen reader meets it: named, and adjusted a step at a
  /// time. The wheels' own nodes are only unnamed numbers, so they are
  /// excluded and these two stand in for them.
  Widget _wheelSemantics({required bool low}) {
    int bound(PuzzleRatingRange range) => low ? range.min : range.max;
    final up = _nudged(low: low, by: kPuzzleRatingStep);
    final down = _nudged(low: low, by: -kPuzzleRatingStep);
    return Semantics(
      key: ValueKey('puzzle_difficulty_${low ? 'lowest' : 'highest'}'),
      slider: true,
      label: low ? 'Lowest rating' : 'Highest rating',
      value: '${bound(_range)}',
      increasedValue: up == _range ? null : '${bound(up)}',
      decreasedValue: down == _range ? null : '${bound(down)}',
      onIncrease: up == _range ? null : () => _apply(up),
      onDecrease: down == _range ? null : () => _apply(down),
      // Childless, so it never takes a touch from the wheel above it.
      child: const SizedBox.expand(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final preset = _range.preset;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final wheels = ExcludeSemantics(
      // Folded away, the wheels are not there to find.
      excluding: !_customOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Stack(
          children: [
            Positioned.fill(
              child: Row(
                children: [
                  Expanded(child: _wheelSemantics(low: true)),
                  Expanded(child: _wheelSemantics(low: false)),
                ],
              ),
            ),
            ExcludeSemantics(
              child: WheelRangeFilter(
                minValue: kPuzzleRatingFloor.toDouble(),
                maxValue: kPuzzleRatingCeiling.toDouble(),
                divisions:
                    (kPuzzleRatingCeiling - kPuzzleRatingFloor) ~/
                    kPuzzleRatingStep,
                currentStart: _range.min.toDouble(),
                currentEnd: _range.max.toDouble(),
                onChanged: (values) => _apply(
                  normalizePuzzleRatingRange(
                    values.start.round(),
                    values.end.round(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.divider),
        ),
        clipBehavior: Clip.antiAlias,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        // Scrolls on a short screen rather than cutting the custom wheels.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Semantics(
                  header: true,
                  child: Text(
                    'Puzzle difficulty',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.textLgBold.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ),
              for (final option in PuzzleRatingPreset.values)
                _Row(
                  key: ValueKey('puzzle_difficulty_${option.name}'),
                  label: option.label,
                  value: _label(option.range),
                  selected: preset == option,
                  onTap: () => widget.onPreset(option),
                ),
              _Row(
                key: const ValueKey('puzzle_difficulty_custom'),
                label: 'Custom',
                value: preset == null ? _label(_range) : null,
                selected: preset == null,
                expanded: _customOpen,
                onTap: () {
                  HapticFeedbackService.selection();
                  setState(() => _customOpen = !_customOpen);
                },
              ),
              // The wheels open under Custom; content stays laid out, only its
              // visible height moves, on a spring.
              if (reduceMotion)
                _customOpen ? wheels : const SizedBox.shrink()
              else
                ClipRect(
                  child: SingleMotionBuilder(
                    value: _customOpen ? 1.0 : 0.0,
                    motion: const CupertinoMotion.smooth(),
                    child: wheels,
                    builder: (context, t, child) => Align(
                      alignment: Alignment.topCenter,
                      heightFactor: t.clamp(0.0, 1.0),
                      child: child,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
    this.expanded,
    super.key,
  });

  final String label;
  final String? value;
  final bool selected;
  final VoidCallback onTap;

  /// Whether Custom's wheels are open; null for a preset.
  final bool? expanded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final value = this.value;
    return FeedPressable(
      semanticsLabel: [label, ?value].join(', '),
      selected: selected,
      inMutuallyExclusiveGroup: true,
      expanded: expanded,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textMdMedium.copyWith(
                    color: colors.textPrimary,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: 12),
                Text(
                  value,
                  maxLines: 1,
                  style: AppTypography.textSmMedium.copyWith(
                    color: colors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
              const SizedBox(width: 12),
              SizedBox.square(
                dimension: 20,
                child: selected
                    ? FeedGlyph(
                        FeedGlyphs.tick,
                        width: 20,
                        height: 20,
                        color: colors.textPrimary,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
