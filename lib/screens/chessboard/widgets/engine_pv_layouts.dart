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
    this.scrollTargetKey,
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

  /// When set, the list row horizontally auto-scrolls so the widget carrying
  /// this key (the highlighted/cursor move) stays visible while traversing.
  final GlobalKey? scrollTargetKey;

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
            child:
                i < items.length
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

/// Compact eval badge sized to its content (with a small min width so rows stay
/// aligned) — deliberately close to the move text's weight/size so it reads as
/// part of the line, not a bulky block.
class _EvalBadge extends StatelessWidget {
  const _EvalBadge({
    required this.text,
    required this.background,
    required this.foreground,
  });

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: 26.w),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 5.sp, vertical: 1.5.sp),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(3.br),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: foreground,
            fontSize: 10.5.f,
            fontWeight: FontWeight.w700,
            height: 1.1,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// Horizontally scrollable move text with soft overflow fades. The leading
/// edge stays fully opaque at the initial position so the first move is always
/// cleanly readable; its fade appears only after the row has been scrolled.
class _FadeScroller extends StatelessWidget {
  const _FadeScroller({required this.controller, required this.child});

  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final hasClients = controller.hasClients;
        final fadeLeadingEdge = hasClients && controller.offset > 0.5;
        final fadeTrailingEdge =
            hasClients && controller.position.extentAfter > 0.5;

        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) {
            final opaque = const Color(0xFF000000);
            final transparent = const Color(0x00000000);
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                fadeLeadingEdge ? transparent : opaque,
                fadeLeadingEdge ? opaque : opaque,
                fadeTrailingEdge ? opaque : opaque,
                fadeTrailingEdge ? transparent : opaque,
              ],
              stops: const [0.0, 0.035, 0.9, 1.0],
            ).createShader(rect);
          },
          child: SingleChildScrollView(
            controller: controller,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: child,
          ),
        );
      },
    );
  }
}

class _PvRow extends StatefulWidget {
  const _PvRow({required this.item});

  final EnginePvItem item;

  @override
  State<_PvRow> createState() => _PvRowState();
}

class _PvRowState extends State<_PvRow> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _scheduleFollow();
  }

  @override
  void didUpdateWidget(covariant _PvRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleFollow();
  }

  /// Animate the row so the highlighted (cursor) move stays visible when the
  /// user traverses the line with the arrow keys.
  ///
  /// IMPORTANT: this drives ONLY this row's own [ScrollController]. We must not
  /// use [Scrollable.ensureVisible] here — it recursively scrolls every
  /// scrollable ancestor, which would nudge the parent board PageView and make
  /// the whole page twitch/swipe on each arrow press.
  void _scheduleFollow() {
    final key = widget.item.scrollTargetKey;
    if (key == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final targetCtx = key.currentContext;
      if (targetCtx == null) return;
      final targetObj = targetCtx.findRenderObject();
      if (targetObj is! RenderBox) return;
      // The nearest Scrollable is this row's horizontal SingleChildScrollView.
      final scrollable = Scrollable.maybeOf(targetCtx);
      final viewportObj = scrollable?.context.findRenderObject();
      if (viewportObj is! RenderBox) return;

      // Target position relative to the visible viewport (accounts for the
      // current scroll offset already).
      final dx = targetObj.localToGlobal(Offset.zero, ancestor: viewportObj).dx;
      final targetWidth = targetObj.size.width;
      final viewportWidth = viewportObj.size.width;
      final current = _controller.offset;
      final maxExtent = _controller.position.maxScrollExtent;
      final desired = (current + dx + targetWidth / 2 - viewportWidth / 2)
          .clamp(0.0, maxExtent);
      if ((desired - current).abs() < 1.0) return;
      _controller.animateTo(
        desired,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
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
          padding: EdgeInsets.only(left: 10.sp, right: 4.sp),
          child: Row(
            children: [
              _EvalBadge(
                text: item.evalText,
                background: evalBgColor,
                foreground: evalTextColor,
              ),
              SizedBox(width: 7.sp),
              Expanded(
                child: _FadeScroller(
                  controller: _controller,
                  child: Text.rich(
                    TextSpan(children: item.moveSpans),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                  ),
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
  const _PvRowPlaceholder({
    required this.isPrimary,
    required this.isEvaluating,
  });

  final bool isPrimary;
  final bool isEvaluating;

  @override
  Widget build(BuildContext context) {
    final badgeText = isEvaluating ? '···' : '–';
    return Padding(
      padding: EdgeInsets.only(left: 10.sp, right: 4.sp),
      child: Row(
        children: [
          _EvalBadge(
            text: badgeText,
            background: context.colors.textSecondary.withValues(alpha: 0.2),
            foreground: context.colors.textPrimary.withValues(
              alpha: isEvaluating ? 0.35 : 0.18,
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
          child:
              items.isEmpty
                  ? (widget.emptyPlaceholder ?? const SizedBox.shrink())
                  : PageView.builder(
                    controller: _pageController,
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    padEnds: false,
                    onPageChanged:
                        (index) => setState(() => _currentPage = index),
                    itemCount: items.length,
                    itemBuilder:
                        (context, index) => _PvCard(item: items[index]),
                  ),
        ),
        SizedBox(height: 4.h),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(pageCount, (index) {
            final isActive = index == _currentPage;
            final accent =
                items.isEmpty
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
                padding: EdgeInsets.symmetric(
                  horizontal: 10.sp,
                  vertical: 10.sp,
                ),
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
