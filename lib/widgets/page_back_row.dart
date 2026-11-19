import 'dart:math' as math;

import 'package:chessever2/widgets/home_top_bar.dart' show PageTitle;
import 'package:chessever2/widgets/search_mode/search_mode.dart';
import 'package:flutter/widgets.dart';

/// A pushed page's back row, one composition on every page with a search
/// header: the [PageBackButton] at [SearchHeaderMetrics.leadingInset] (where
/// the search header's chevron is), the page's controls ending on the
/// gutter (where the search header's trailing ones end), and the title
/// centred on the screen between them in the one page-title voice
/// ([PageTitle]).
///
/// The title moves toward the chevron only as far as it must to clear
/// [reservedEnd]: give it the widest the controls ever get (the tab with the
/// most), and the title sits at one place whichever tab's controls show.
class PageBackRow extends StatelessWidget {
  const PageBackRow({
    super.key,
    required this.title,
    this.actions = const <Widget>[],
    this.reservedEnd = 0,
    this.showBack = true,
    this.onBack,
  });

  /// The page's name: a [PageTitle], or a `Text` in [PageTitle.style].
  final Widget title;

  /// 44pt glyph targets after the title; the last one's glyph lands on the
  /// gutter.
  final List<Widget> actions;

  /// The room kept for [actions] at their widest.
  final double reservedEnd;

  final bool showBack;

  /// Null pops the route.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final start = SearchHeaderMetrics.leadingInset;
    // With controls the row ends where the search header's does: their
    // glyph sits on the gutter in both headers. Without, it mirrors the
    // chevron's inset.
    final end = actions.isEmpty && reservedEnd <= 0
        ? start
        : math.max(
            0.0,
            SearchHeaderMetrics.gutter - SearchHeaderMetrics.trailingReach,
          );
    return Padding(
      padding: EdgeInsetsDirectional.only(start: start, end: end),
      child: SizedBox(
        height: SearchHeaderMetrics.rowHeight,
        child: CustomMultiChildLayout(
          delegate: _BackRowLayout(
            textDirection: Directionality.of(context),
            reservedEnd: reservedEnd,
            // Kept clear on the start side too, as if the chevron were
            // there, so a title never sits off the screen's centre because
            // one page has no way back.
            reservedStart: SearchHeaderMetrics.backTarget,
            // The row is inset unevenly (the chevron's start, the gutter's
            // end): the title centres on the screen, not on the row.
            centreShift: (end - start) / 2,
          ),
          children: [
            if (showBack)
              LayoutId(
                id: _BackRowSlot.back,
                child: PageBackButton(onPressed: onBack),
              ),
            LayoutId(id: _BackRowSlot.title, child: title),
            LayoutId(
              id: _BackRowSlot.end,
              child: Row(mainAxisSize: MainAxisSize.min, children: actions),
            ),
          ],
        ),
      ),
    );
  }
}

enum _BackRowSlot { back, title, end }

/// The back row: the chevron at the start, the controls at the end, and the
/// title centred on the screen, moved toward the chevron only as far as it
/// must to clear [reservedEnd]: so it stays put whichever tab's controls
/// are showing, and never runs under them.
class _BackRowLayout extends MultiChildLayoutDelegate {
  _BackRowLayout({
    required this.textDirection,
    required this.reservedEnd,
    required this.reservedStart,
    required this.centreShift,
  });

  final TextDirection textDirection;
  final double reservedEnd;
  final double reservedStart;

  /// From the row's centre to the screen's, toward the end.
  final double centreShift;

  /// The least room between the title and its neighbours.
  static const double gap = 4;

  @override
  void performLayout(Size size) {
    final rtl = textDirection == TextDirection.rtl;
    final loose = BoxConstraints.loose(size);
    Offset at(double start, Size child) => Offset(
      rtl ? size.width - start - child.width : start,
      (size.height - child.height) / 2,
    );
    var backWidth = 0.0;
    if (hasChild(_BackRowSlot.back)) {
      final back = layoutChild(_BackRowSlot.back, loose);
      backWidth = back.width;
      positionChild(_BackRowSlot.back, at(0, back));
    }
    final end = layoutChild(_BackRowSlot.end, loose);
    positionChild(_BackRowSlot.end, at(size.width - end.width, end));

    final from = math.max(backWidth, reservedStart) + gap;
    final to = size.width - math.max(reservedEnd, end.width) - gap;
    final title = layoutChild(
      _BackRowSlot.title,
      BoxConstraints.loose(Size(math.max(0.0, to - from), size.height)),
    );
    final centred = (size.width - title.width) / 2 + centreShift;
    final start = centred
        .clamp(from, math.max(from, to - title.width))
        .toDouble();
    positionChild(_BackRowSlot.title, at(start, title));
  }

  @override
  bool shouldRelayout(_BackRowLayout oldDelegate) =>
      oldDelegate.textDirection != textDirection ||
      oldDelegate.reservedEnd != reservedEnd ||
      oldDelegate.reservedStart != reservedStart ||
      oldDelegate.centreShift != centreShift;
}
