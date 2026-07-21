import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:flutter/material.dart';

/// What a miniature is, and nothing else.
///
/// The stats dashboard that used to live here was removed. Every figure on it
/// (totals, colour split, ECO volumes, top openings, time controls, busiest
/// day, shortest and strongest games) was a decorated shortcut into a filter
/// the Games tab already exposes directly, so the two tabs restated the same
/// database twice. This one now answers the single question the other two
/// cannot: what makes a game a miniature.
///
/// It reads no provider and makes no request, so it renders instantly, works
/// offline, and has no loading or error state to get wrong.
class MiniaturesAboutTab extends StatefulWidget {
  const MiniaturesAboutTab({super.key});

  @override
  State<MiniaturesAboutTab> createState() => _MiniaturesAboutTabState();
}

class _MiniaturesAboutTabState extends State<MiniaturesAboutTab>
    with ScrollToTopListenerMixin {
  final ScrollController _scrollController = ScrollController();

  @override
  void onScrollToTopRequested() {
    animateScrollControllerToTop(_scrollController);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Matches the Games and Players tabs so the three read as one screen.
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );

    Widget content = ListView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        28.h,
        horizontalPadding,
        40.h,
      ),
      children: [
        const _Definition(),
        SizedBox(height: 30.h),
        const _MoveWindow(),
        SizedBox(height: 34.h),
        const _Rules(),
      ],
    );

    if (ResponsiveHelper.isTablet) {
      content = Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: content,
        ),
      );
    }

    return content;
  }
}

class _Definition extends StatelessWidget {
  const _Definition();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'A miniature is a game won in 25 moves or fewer.',
          style: AppTypography.textLgMedium.copyWith(
            color: context.colors.textPrimary,
            fontSize: 23.sp,
            fontWeight: FontWeight.w600,
            height: 1.28,
          ),
        ),
        SizedBox(height: 12.h),
        Text(
          'Short decisive games: an opening trap, a missed tactic, an attack '
          'that lands before the position settles.',
          style: AppTypography.textSmRegular.copyWith(
            color: context.colors.textSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

/// The qualifying window drawn as a band, labelled at both ends. It states the
/// rule the sentence above states, in the one form a move count actually has.
///
/// The band deliberately runs the full width and carries no scale past move
/// 25: a partial band would imply a proportion of some "normal" game length,
/// which is a number this screen does not have and should not invent.
class _MoveWindow extends StatelessWidget {
  const _MoveWindow();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 7.h,
          child: DecoratedBox(
            decoration: BoxDecoration(
              // Tonal, not the brand cyan: this marks the subject of the page,
              // not an action or a live state. Held just under full strength
              // so it supports the definition above rather than outshouting
              // it.
              color: context.colors.textPrimary.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(4.br),
            ),
          ),
        ),
        SizedBox(height: 10.h),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [_Tick('Move 3'), _Tick('Move 25')],
        ),
      ],
    );
  }
}

class _Tick extends StatelessWidget {
  const _Tick(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: AppTypography.textXsMedium.copyWith(
        color: context.colors.textSecondary,
      ),
    );
  }
}

/// The three conditions a game has to meet, straight from the index that
/// builds this database.
class _Rules extends StatelessWidget {
  const _Rules();

  static const List<(String, String)> _rules = [
    ('Length', '3 to 25 moves. White never plays a 26th.'),
    ('Result', 'One side wins. A draw is never a miniature.'),
    (
      'Finish',
      'Mate on the board, or an engine confirming the winner was clearly '
          'ahead when the game stopped.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // A Table rather than a Row per rule: the label column takes the width of
    // its widest label and every rule then starts on that one shared rail, so
    // the three rows cannot go ragged as the copy changes.
    return Table(
      columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        for (var i = 0; i < _rules.length; i++)
          TableRow(
            children: [
              Padding(
                padding: EdgeInsets.only(
                  right: 18.w,
                  bottom: i == _rules.length - 1 ? 0 : 16.h,
                ),
                child: Text(
                  _rules[i].$1,
                  // Same size and line height as the rule beside it, so the
                  // two columns share a first baseline instead of only a top
                  // edge. Weight and tone carry the hierarchy.
                  style: AppTypography.textSmMedium.copyWith(
                    color: context.colors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(
                  bottom: i == _rules.length - 1 ? 0 : 16.h,
                ),
                child: Text(
                  _rules[i].$2,
                  style: AppTypography.textSmRegular.copyWith(
                    color: context.colors.textPrimary,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
