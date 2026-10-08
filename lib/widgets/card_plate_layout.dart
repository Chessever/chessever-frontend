import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// The same artwork and live details, beside one another in a row or stacked
/// in a small card. Artwork keeps its proportions instead of being squeezed
/// along with a horizontal row into half the page.
class CardPlateLayout extends StatelessWidget {
  const CardPlateLayout({
    super.key,
    required this.plate,
    required this.details,
    this.stacked = false,
    this.trailing,
  });

  final Widget plate;
  final Widget details;
  final Widget? trailing;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Align(alignment: Alignment.topCenter, child: plate),
              if (trailing != null)
                Positioned(top: 0, right: 0, child: trailing!),
            ],
          ),
          SizedBox(height: 10.sp),
          Padding(padding: EdgeInsets.all(6.sp), child: details),
        ],
      );
    }
    return Row(
      children: [
        plate,
        SizedBox(width: 10.w),
        Expanded(child: details),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Small cards reserve two title lines so metadata stays aligned beside a
/// neighbour with a longer name. Full rows keep their natural text height.
class CardPlateTitle extends StatelessWidget {
  const CardPlateTitle({super.key, required this.child, required this.stacked});

  final Text child;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    if (!stacked) return child;
    final painter = TextPainter(
      text: TextSpan(
        text: 'Ag\nAg',
        style: DefaultTextStyle.of(context).style.merge(child.style),
      ),
      textDirection: Directionality.of(context),
      textScaler: child.textScaler ?? MediaQuery.textScalerOf(context),
      maxLines: 2,
    )..layout();
    final height = painter.height.ceilToDouble();
    painter.dispose();
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      child: child,
    );
  }
}
