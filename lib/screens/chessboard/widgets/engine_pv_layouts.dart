import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// A single engine principal-variation entry, rendered by either
/// [EnginePvListView] (traditional vertical rows) or [EnginePvCardsView]
/// (ChessEver swipeable cards). Move spans are pre-built by the caller so each
/// surface keeps its own figurine / SAN formatting.
class EnginePvItem {
  const EnginePvItem({
    required this.evalText,
    required this.moveSpans,
    required this.accentColor,
    this.isWhiteWinning = false,
    this.isBlackWinning = false,
    this.isPrimary = false,
    this.onTap,
    this.onLongPress,
  });

  final String evalText;
  final List<InlineSpan> moveSpans;

  /// Tint used for the card border and eval badge (variant color on the board).
  final Color accentColor;

  /// Winning-side hints drive the eval-badge colors in the list layout.
  final bool isWhiteWinning;
  final bool isBlackWinning;

  /// The top line is emphasized in the list layout.
  final bool isPrimary;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
}

/// Traditional layout: engine lines stacked vertically, one per row, matching
/// the Library opening-explorer look (eval badge + move text).
///
/// The layout is STABLE: it always reserves exactly [slotCount] fixed-height
/// rows (capped at 3), so rows never appear/disappear or resize as the engine
/// streams results — missing lines render as placeholders holding their space.
class EnginePvListView extends StatelessWidget {
  const EnginePvListView({
    super.key,
    required this.items,
    this.slotCount = 3,
    this.isEvaluating = false,
    this.trailingDivider = true,
  });

  final List<EnginePvItem> items;

  /// Number of fixed-height rows to always reserve (hard-capped at 3).
  final int slotCount;
  final bool isEvaluating;
  final bool trailingDivider;

  /// Fixed height per row so text updates never shift the layout vertically.
  static double get rowHeight => 30.h;

  @override
  Widget build(BuildContext context) {
    final rows = slotCount.clamp(1, 3);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              color: context.colors.divider.withValues(alpha: 0.3),
              indent: 12.sp,
              endIndent: 12.sp,
            ),
          SizedBox(
            height: rowHeight,
            child: i < items.length
                ? _PvRow(item: items[i])
                : _PvRowPlaceholder(
                    isPrimary: i == 0,
                    isEvaluating: isEvaluating,
                  ),
          ),
        ],
        if (trailingDivider) Divider(color: context.colors.divider, height: 1),
      ],
    );
  }
}

class _PvRow extends StatelessWidget {
  const _PvRow({required this.item});

  final EnginePvItem item;

  @override
  Widget build(BuildContext context) {
    Color evalBgColor;
    Color evalTextColor;
    if (item.isWhiteWinning) {
      evalBgColor = context.colors.textPrimary;
      evalTextColor = context.colors.surface;
    } else if (item.isBlackWinning) {
      evalBgColor = context.colors.divider;
      evalTextColor = context.colors.textPrimary;
    } else {
      evalBgColor = context.colors.textSecondary.withValues(alpha: 0.3);
      evalTextColor = context.colors.textPrimary;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        onLongPress: item.onLongPress,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.sp),
          child: Row(
            children: [
              Container(
                width: 44.w,
                padding: EdgeInsets.symmetric(vertical: 2.sp),
                decoration: BoxDecoration(
                  color: evalBgColor,
                  borderRadius: BorderRadius.circular(3.br),
                ),
                child: Text(
                  item.evalText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: evalTextColor,
                    fontSize: 11.f,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              SizedBox(width: 8.sp),
              Expanded(
                child: RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(children: item.moveSpans),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PvRowPlaceholder extends StatelessWidget {
  const _PvRowPlaceholder({required this.isPrimary, required this.isEvaluating});

  final bool isPrimary;
  final bool isEvaluating;

  @override
  Widget build(BuildContext context) {
    final badgeText = isEvaluating ? '...' : '-';
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.sp),
      child: Row(
        children: [
          Container(
            width: 44.w,
            padding: EdgeInsets.symmetric(vertical: 2.sp),
            decoration: BoxDecoration(
              color: context.colors.textSecondary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(3.br),
            ),
            child: Text(
              badgeText,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.textPrimary.withValues(
                  alpha: isEvaluating ? 0.35 : 0.18,
                ),
                fontSize: 11.f,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          SizedBox(width: 8.sp),
          Expanded(
            child: Text(
              ' ',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.colors.textPrimary.withValues(
                  alpha: isPrimary ? 0.65 : 0.18,
                ),
                fontSize: 12.f,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ChessEver layout: engine lines as horizontally swipeable cards with a page
/// indicator, matching the analysis-board PV carousel.
class EnginePvCardsView extends StatefulWidget {
  const EnginePvCardsView({
    super.key,
    required this.items,
    this.cardHeight,
    this.emptyPlaceholder,
  });

  final List<EnginePvItem> items;
  final double? cardHeight;

  /// Shown (as a single non-swipeable card) when there are no lines yet.
  final Widget? emptyPlaceholder;

  @override
  State<EnginePvCardsView> createState() => _EnginePvCardsViewState();
}

class _EnginePvCardsViewState extends State<EnginePvCardsView> {
  final PageController _pageController = PageController(viewportFraction: 0.92);
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final height = widget.cardHeight ?? 78.h;
    final pageCount = items.isEmpty ? 1 : items.length;

    // Keep _currentPage in range if the line count shrinks.
    if (_currentPage >= pageCount) {
      _currentPage = pageCount - 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          height: height,
          child: items.isEmpty
              ? (widget.emptyPlaceholder ?? const SizedBox.shrink())
              : PageView.builder(
                  controller: _pageController,
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  padEnds: false,
                  onPageChanged: (index) =>
                      setState(() => _currentPage = index),
                  itemCount: items.length,
                  itemBuilder: (context, index) => _PvCard(item: items[index]),
                ),
        ),
        SizedBox(height: 4.h),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(pageCount, (index) {
            final isActive = index == _currentPage;
            final accent = items.isEmpty
                ? context.colors.textPrimary.withValues(alpha: 0.1)
                : items[index.clamp(0, items.length - 1)].accentColor;
            return Container(
              margin: EdgeInsets.symmetric(horizontal: 4.sp),
              width: 6.w,
              height: 6.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive ? accent : accent.withValues(alpha: 0.35),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _PvCard extends StatelessWidget {
  const _PvCard({required this.item});

  final EnginePvItem item;

  @override
  Widget build(BuildContext context) {
    final borderColor = item.accentColor.withValues(alpha: 0.7);
    final backgroundColor = item.accentColor.withValues(alpha: 0.15);

    return GestureDetector(
      onTap: item.onTap,
      onLongPress: item.onLongPress,
      child: Container(
        width: double.infinity,
        margin: EdgeInsets.symmetric(horizontal: 2.sp),
        decoration: BoxDecoration(
          border: Border.all(color: borderColor, width: 1.5),
          borderRadius: BorderRadius.circular(6.sp),
          color: backgroundColor,
        ),
        clipBehavior: Clip.hardEdge,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 48.sp,
              decoration: BoxDecoration(
                color: item.accentColor.withValues(alpha: 0.25),
                border: Border(
                  right: BorderSide(
                    color: item.accentColor.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
              ),
              child: Center(
                child: Text(
                  item.evalText,
                  style: AppTypography.textSmBold.copyWith(
                    color: context.colors.textPrimary,
                    fontSize: 12.sp,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                primary: false,
                scrollDirection: Axis.vertical,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 10.sp),
                child: RichText(
                  text: TextSpan(
                    style: AppTypography.textXsMedium.copyWith(
                      color: context.colors.textPrimary.withValues(alpha: 0.95),
                      fontWeight: FontWeight.w600,
                    ),
                    children: item.moveSpans,
                  ),
                  softWrap: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
