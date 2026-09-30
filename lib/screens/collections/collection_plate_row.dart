import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart'
    show DiscoveryPadlock;
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart' show TappableScale;
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:flutter/material.dart';

/// The row every collection list draws: the [plate] on the left
/// ([plateSize]: an event's 5:4 picture or a book's 2:3 cover), the title
/// (two lines at most), the [meta] line ([metaMaxLines] of them), the
/// [tally] under it, and the optional [note] last. [locked] trails the
/// tally (or, without one, the meta) with the Premium padlock, which the
/// text gives way to. A null [onTap] draws the row with no press and no
/// target (an event the server could not resolve still shows what the book
/// covers).
class CollectionPlateRow extends StatelessWidget {
  const CollectionPlateRow({
    super.key,
    required this.plate,
    required this.title,
    required this.meta,
    required this.semanticsLabel,
    this.plateSize,
    this.metaMaxLines = 1,
    this.tally,
    this.locked = false,
    this.note,
    this.onTap,
    this.menuActions,
    this.trailing,
    this.stats,
    this.compactDetails = false,
    this.detailItems = const [],
  });

  /// An event's picture: landscape, 5:4.
  static Size get eventPlate => Size(108.w, 108.w * 4 / 5);

  /// A book's cover, standing as a book stands: 2:3, the shape most covers
  /// are printed in, so a jacket keeps its title and its author.
  static Size get bookPlate => Size(64.w, 96.w);

  final Widget plate;

  /// [eventPlate] when null.
  final Size? plateSize;
  final String title;
  final String? meta;
  final String semanticsLabel;
  final int metaMaxLines;

  /// Trailing action (a collection's star), top-aligned at the row's end.
  /// Null draws the row exactly as before.
  final Widget? trailing;
  final Widget? stats;

  /// Books keep their counts together instead of adding another text row.
  final bool compactDetails;
  final List<Widget> detailItems;

  /// How much the collection holds ("55 games"), on its own line.
  final String? tally;
  final bool locked;
  final String? note;
  final VoidCallback? onTap;
  final CardMenuActionsBuilder? menuActions;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isLight = context.isLightTheme;
    final size = plateSize ?? eventPlate;
    final metaStyle = AppTypography.textXsMedium.copyWith(
      color: colors.textPrimaryMuted,
    );
    final line = meta;
    final count = tally;
    final caption = note;

    // The padlock stands outside the text, so a long credit or a larger
    // text size shortens the words and never cuts the lock off with them.
    Widget withLock(Widget? text) => Row(
      children: [
        if (text != null) Flexible(child: text),
        if (locked) ...[
          if (text != null) SizedBox(width: DiscoveryPadlock.gap),
          const DiscoveryPadlock(
            key: ValueKey<String>('collection_card_padlock'),
          ),
        ],
      ],
    );

    final Widget? metaText = line == null
        ? null
        : metaMaxLines < 2
        ? Text(
            line,
            maxLines: metaMaxLines,
            overflow: TextOverflow.ellipsis,
            style: metaStyle,
          )
        : LayoutBuilder(
            builder: (context, constraints) => Text(
              _breakAtLastDot(context, line, metaStyle, constraints.maxWidth),
              maxLines: metaMaxLines,
              overflow: TextOverflow.ellipsis,
              style: metaStyle,
            ),
          );

    final identity = <Widget>[
      Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.textSmMedium.copyWith(
          color: colors.textPrimary,
          fontSize: compactDetails ? 16.f : 14.f,
          fontWeight: compactDetails ? FontWeight.w600 : FontWeight.w500,
          height: 1.2,
        ),
      ),
      if (metaText != null) ...[
        SizedBox(height: 4.h),
        count == null ? withLock(metaText) : metaText,
      ],
    ];
    final details = ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (compactDetails)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: EdgeInsetsDirectional.only(end: 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: identity,
                ),
              ),
            )
          else
            ...identity,
          if (compactDetails &&
              (count != null || detailItems.isNotEmpty || stats != null)) ...[
            SizedBox(height: 8.sp),
            Wrap(
              spacing: 12.sp,
              runSpacing: 4.sp,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (count != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          count,
                          style: AppTypography.textXsRegular.copyWith(
                            color: colors.textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      if (locked) ...[
                        SizedBox(width: DiscoveryPadlock.gap),
                        const DiscoveryPadlock(
                          key: ValueKey<String>('collection_card_padlock'),
                        ),
                      ],
                    ],
                  ),
                ...detailItems,
                if (stats != null) stats!,
              ],
            ),
          ] else if (count != null) ...[
            SizedBox(height: metaText == null ? 4.h : 2.h),
            withLock(
              Text(
                count,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: metaStyle.copyWith(
                  color: colors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ] else if (metaText == null && locked) ...[
            SizedBox(height: 4.h),
            withLock(null),
          ],
          if (!compactDetails && stats != null) ...[
            SizedBox(height: 6.h),
            stats!,
          ],
          if (caption != null) ...[
            SizedBox(height: 6.h),
            Text(
              caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textXsRegular.copyWith(
                color: colors.textSecondary,
                height: 16 / 12,
              ),
            ),
          ],
        ],
      ),
    );

    Widget card = Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8.br),
        border: isLight
            ? Border.all(color: colors.divider.withValues(alpha: 0.4))
            : null,
      ),
      padding: EdgeInsets.all(6.sp),
      child: Row(
        children: [
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6.br),
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: plate,
              ),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Padding(
              padding: EdgeInsetsDirectional.only(end: 6.sp),
              child: compactDetails
                  ? Padding(
                      padding: EdgeInsets.only(top: 4.sp),
                      child: details,
                    )
                  : details,
            ),
          ),
          if (trailing != null)
            Align(
              alignment: Alignment.topCenter,
              child: compactDetails
                  ? Transform.translate(
                      offset: Offset(0, -4.sp),
                      child: trailing,
                    )
                  : trailing,
            ),
        ],
      ),
    );

    final tap = onTap;
    if (tap == null) {
      return Semantics(
        label: semanticsLabel,
        excludeSemantics: true,
        child: card,
      );
    }
    final actions = menuActions;
    if (actions != null) {
      card = CardContextMenu(onPreviewTap: tap, actions: actions, child: card);
    }
    return Semantics(
      button: true,
      label: semanticsLabel,
      excludeSemantics: trailing == null,
      container: trailing != null,
      explicitChildNodes: trailing != null,
      onTap: tap,
      child: TappableScale(onTap: tap, child: card),
    );
  }
}

/// [line] as it should wrap in [width]: whole when it fits on one line;
/// otherwise, when its last part ("Jan 13-28, 2024" after "Wijk aan Zee ·")
/// and what leads it each fit a line, broken there with the dot dropped, so
/// no line ends on a dangling separator. Anything longer wraps as it falls.
String _breakAtLastDot(
  BuildContext context,
  String line,
  TextStyle style,
  double width,
) {
  const dot = ' · ';
  final at = line.lastIndexOf(dot);
  if (at <= 0 || !width.isFinite) return line;
  final scaler = MediaQuery.textScalerOf(context);
  final direction = Directionality.of(context);
  // Measured as the Text will draw it: over the ambient style, whose
  // letter spacing the line inherits.
  final drawn = DefaultTextStyle.of(context).style.merge(style);
  bool fits(String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: drawn),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout(maxWidth: width);
    final fit = !painter.didExceedMaxLines;
    painter.dispose();
    return fit;
  }

  if (fits(line)) return line;
  final head = line.substring(0, at);
  final tail = line.substring(at + dot.length);
  return fits(head) && fits(tail) ? '$head\n$tail' : line;
}
