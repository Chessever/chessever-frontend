import 'dart:math' as math;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// How a piece of header text is set.
enum FeedHeaderTone {
  /// A name: full ink, semibold.
  strong,

  /// The event: full ink.
  primary,

  /// Supporting words ("Your favorite", the opening's name).
  secondary,
}

/// One run inside a [FeedHeaderPart]: text in a [FeedHeaderTone], or a drawn
/// glyph of a fixed width.
@immutable
class FeedHeaderPiece {
  const FeedHeaderPiece.text(
    String this.text, {
    this.tone = FeedHeaderTone.primary,
  }) : glyph = null,
       width = 0;

  const FeedHeaderPiece.glyph(Widget this.glyph, {required this.width})
    : text = null,
      tone = FeedHeaderTone.primary;

  /// Blank space of [width].
  const FeedHeaderPiece.gap(this.width)
    : text = null,
      glyph = null,
      tone = FeedHeaderTone.primary;

  final String? text;
  final FeedHeaderTone tone;
  final Widget? glyph;
  final double width;
}

/// One segment of the header line: the signal, the event, the opening.
/// [compact] is the shorter form the line falls back to when it runs out of
/// room; a [shrinkable] part ellipsizes its last text as a last resort.
@immutable
class FeedHeaderPart {
  const FeedHeaderPart({
    required this.pieces,
    this.compact,
    this.onTap,
    this.semanticsLabel,
    this.shrinkable = false,
    this.id,
  });

  final List<FeedHeaderPiece> pieces;
  final List<FeedHeaderPiece>? compact;
  final VoidCallback? onTap;
  final String? semanticsLabel;
  final bool shrinkable;

  /// Keys the part's widget (`feed_header_<id>`), for tests.
  final String? id;
}

/// The one-line header above a Feed post: what kind of game, why it is here,
/// where it was played and what was played, in a single 44pt row.
///
/// Parts are separated by a quiet " · ". When the line would not fit it
/// compacts instead of wrapping, in this order: the parts in [compactOrder]
/// take their short forms one by one, then the parts in [shrinkOrder] give up
/// width one by one (down to [minPartWidth]), ellipsizing their last words,
/// then the parts in [dropOrder] leave the line, and only then do shrinkable
/// parts go below [minPartWidth]. It never takes a second line, and never
/// runs past its edge, at any width or text size.
///
/// Tappable parts get the whole row height as their target, and at least
/// [minTapWidth] across even when their text is a bare code like "C65"; they
/// dim while pressed; no underline, no chip.
class FeedPostHeader extends StatelessWidget {
  const FeedPostHeader({
    required this.height,
    required this.parts,
    this.leading,
    this.leadingWidth = 0,
    this.trailing,
    this.compactOrder = const [],
    this.shrinkOrder = const [],
    this.dropOrder = const [],
    super.key,
  });

  final double height;
  final List<FeedHeaderPart> parts;

  /// A mark before everything else (the time-control glyph), [leadingWidth]
  /// wide.
  final Widget? leading;
  final double leadingWidth;

  /// A control held to the right edge (the puzzle difficulty).
  final FeedHeaderPart? trailing;

  /// Indexes into [parts], in the order they take their [FeedHeaderPart.compact]
  /// form.
  final List<int> compactOrder;

  /// Indexes into [parts], in the order they give up width.
  final List<int> shrinkOrder;

  /// Indexes into [parts], in the order they leave the line when even their
  /// shortest forms do not fit (a very narrow screen at a very large text
  /// size). Parts not listed always stay.
  final List<int> dropOrder;

  static const double fontSize = 13;
  static const double lineHeight = 18;
  static const double leadingGap = 8;
  static const double trailingGap = 12;
  static const double minPartWidth = 64;

  /// The narrowest a tappable part's target gets, however short its text.
  /// Only a line with no room at all for it (a tiny width at a huge text
  /// size) goes below, so the line still never runs past its edge.
  static const double minTapWidth = 44;
  static const String separator = ' · ';

  /// The header's text style for [tone].
  static TextStyle styleFor(BuildContext context, FeedHeaderTone tone) {
    final colors = context.colors;
    final base = AppTypography.textXsMedium.copyWith(
      fontSize: fontSize,
      height: lineHeight / fontSize,
    );
    return switch (tone) {
      FeedHeaderTone.strong => base.copyWith(
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
      ),
      FeedHeaderTone.primary => base.copyWith(
        fontWeight: FontWeight.w500,
        color: colors.textPrimary,
      ),
      FeedHeaderTone.secondary => base.copyWith(
        fontWeight: FontWeight.w500,
        color: colors.textSecondary,
      ),
    };
  }

  static TextStyle separatorStyle(BuildContext context) => styleFor(
    context,
    FeedHeaderTone.secondary,
  ).copyWith(fontWeight: FontWeight.w400, color: context.colors.textTertiary);

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    // Measured exactly as [Text] will lay it out: merged into the ambient
    // text style, which may add letter spacing or features.
    final ambient = DefaultTextStyle.of(context).style;

    double textWidth(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: ambient.merge(style)),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width.ceilToDouble() + 1;
    }

    double piecesWidth(List<FeedHeaderPiece> pieces) {
      var sum = 0.0;
      for (final piece in pieces) {
        final text = piece.text;
        sum += text == null
            ? piece.width
            : textWidth(text, styleFor(context, piece.tone));
      }
      return sum;
    }

    // A tappable part is never narrower than its target.
    double floorOf(FeedHeaderPart part) => part.onTap == null ? 0 : minTapWidth;
    double partWidth(FeedHeaderPart part, List<FeedHeaderPiece> pieces) =>
        math.max(floorOf(part), piecesWidth(pieces));

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final max = constraints.maxWidth;
          final sepWidth = textWidth(separator, separatorStyle(context));
          final full = [for (final part in parts) partWidth(part, part.pieces)];
          final short = [
            for (final part in parts)
              part.compact == null ? null : partWidth(part, part.compact!),
          ];
          final useCompact = List<bool>.filled(parts.length, false);
          final widths = List<double>.of(full);
          final shrunk = List<bool>.filled(parts.length, false);
          final kept = List<bool>.filled(parts.length, true);
          final trailing = this.trailing;
          var trailingWidth = trailing == null
              ? 0.0
              : partWidth(trailing, trailing.pieces) + trailingGap;
          var trailingShrunk = false;
          final leadWidth = leading == null ? 0.0 : leadingWidth + leadingGap;

          double total() {
            var sum = leadWidth + trailingWidth;
            var shown = 0;
            for (var i = 0; i < parts.length; i++) {
              if (!kept[i]) continue;
              sum += widths[i];
              if (shown++ > 0) sum += sepWidth;
            }
            return sum;
          }

          for (final i in compactOrder) {
            if (total() <= max) break;
            final compactWidth = short[i];
            if (compactWidth == null) continue;
            useCompact[i] = true;
            widths[i] = compactWidth;
          }
          for (final i in shrinkOrder) {
            final over = total() - max;
            if (over <= 0) break;
            if (!parts[i].shrinkable) continue;
            final next = math.max(minPartWidth, widths[i] - over);
            if (next < widths[i]) {
              widths[i] = next;
              shrunk[i] = true;
            }
          }
          // Still over (a very narrow screen at a large text size): the
          // least important parts leave the line...
          for (final i in dropOrder) {
            if (total() <= max) break;
            kept[i] = false;
          }
          // ...and the shrinkable ones left give up the rest, down to
          // nothing (a tappable one to its target) if they must.
          for (final i in shrinkOrder.reversed) {
            final over = total() - max;
            if (over <= 0) break;
            if (!kept[i] || !parts[i].shrinkable) continue;
            final next = math.max(floorOf(parts[i]), widths[i] - over);
            if (next < widths[i]) {
              widths[i] = next;
              shrunk[i] = true;
            }
          }
          // A line with nothing marked shrinkable still gives way, its parts
          // from the last one back, and the control on the right last of
          // all: its label ellipsizes rather than pushing past the edge.
          // Tappable parts hold their target through the first round; only
          // a line with no room left for it lets them go below, so the line
          // never runs past its edge.
          final trailingFloor = trailing == null ? 0.0 : floorOf(trailing);
          for (final floors in [true, false]) {
            for (var i = parts.length - 1; i >= 0; i--) {
              final over = total() - max;
              if (over <= 0) break;
              if (!kept[i]) continue;
              final floor = floors ? floorOf(parts[i]) : 0.0;
              final next = math.max(floor, widths[i] - over);
              if (next < widths[i]) {
                widths[i] = next;
                shrunk[i] = true;
              }
            }
            final trailingOver = total() - max;
            if (trailing != null && trailingOver > 0) {
              final floor = trailingGap + (floors ? trailingFloor : 0.0);
              final next = math.max(floor, trailingWidth - trailingOver);
              if (next < trailingWidth) {
                trailingWidth = next;
                trailingShrunk = true;
              }
            }
          }

          final children = <Widget>[
            if (leading != null) ...[
              SizedBox(
                width: leadingWidth,
                child: Center(child: leading),
              ),
              const SizedBox(width: leadingGap),
            ],
            for (final (n, i) in [
              for (var i = 0; i < parts.length; i++)
                if (kept[i]) i,
            ].indexed) ...[
              if (n > 0)
                ExcludeSemantics(
                  child: Text(
                    separator,
                    maxLines: 1,
                    softWrap: false,
                    style: separatorStyle(context),
                  ),
                ),
              _PartView(
                part: parts[i],
                pieces: useCompact[i] ? parts[i].compact! : parts[i].pieces,
                width: shrunk[i] ? widths[i] : null,
                minWidth: math.min(floorOf(parts[i]), widths[i]),
                height: height,
              ),
            ],
            if (trailing != null) ...[
              const Spacer(),
              _PartView(
                part: trailing,
                pieces: trailing.pieces,
                width: trailingShrunk ? trailingWidth - trailingGap : null,
                minWidth: math.min(trailingFloor, trailingWidth - trailingGap),
                height: height,
                // Held to the right edge: a short label sits flush right
                // inside its wider target.
                alignment: AlignmentDirectional.centerEnd,
              ),
            ],
          ];
          return Row(children: children);
        },
      ),
    );
  }
}

class _PartView extends StatelessWidget {
  const _PartView({
    required this.part,
    required this.pieces,
    required this.width,
    required this.height,
    this.minWidth = 0,
    this.alignment = AlignmentDirectional.centerStart,
  });

  final FeedHeaderPart part;
  final List<FeedHeaderPiece> pieces;

  /// Set when the part was given less than its natural width; its last text
  /// then ellipsizes.
  final double? width;
  final double height;

  /// The part's least width, its tap target's: text shorter than this sits
  /// at [alignment] inside it.
  final double minWidth;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    var lastText = -1;
    for (var i = 0; i < pieces.length; i++) {
      if (pieces[i].text != null) lastText = i;
    }
    final constrained = width != null;
    Widget pieceView(int i) {
      final piece = pieces[i];
      final text = piece.text;
      if (text == null) {
        final glyph = piece.glyph;
        return SizedBox(
          width: piece.width,
          child: glyph == null ? null : Center(child: glyph),
        );
      }
      final view = _text(context, text, piece.tone);
      return constrained && i == lastText ? Flexible(child: view) : view;
    }

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [for (var i = 0; i < pieces.length; i++) pieceView(i)],
    );
    // A shrunk part is capped at [width], not held to it: it hugs its
    // ellipsized text, so the next separator sits one even gap after the
    // ellipsis instead of past a blank stretch.
    final cap = width;
    Widget child = ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: minWidth,
        maxWidth: cap == null ? double.infinity : math.max(cap, minWidth),
      ),
      child: SizedBox(
        height: height,
        child: Align(alignment: alignment, widthFactor: 1, child: row),
      ),
    );
    final label = part.semanticsLabel;
    final onTap = part.onTap;
    if (onTap == null) {
      child = label == null
          ? child
          : Semantics(
              container: true,
              label: label,
              excludeSemantics: true,
              child: child,
            );
    } else {
      child = _PressDim(
        onTap: onTap,
        semanticsLabel: label ?? _plain(pieces),
        child: child,
      );
    }
    final id = part.id;
    return id == null
        ? child
        : KeyedSubtree(key: ValueKey('feed_header_$id'), child: child);
  }

  static String _plain(List<FeedHeaderPiece> pieces) =>
      pieces.map((p) => p.text ?? '').join().trim();

  Widget _text(BuildContext context, String text, FeedHeaderTone tone) => Text(
    text,
    maxLines: 1,
    softWrap: false,
    overflow: TextOverflow.ellipsis,
    // Sized to the ellipsized line, not the width it was offered.
    textWidthBasis: TextWidthBasis.longestLine,
    style: FeedPostHeader.styleFor(context, tone),
  );
}

/// A tappable header part: it dims a step while pressed, on a snappy spring
/// (no dim animation with reduced motion). Nothing moves or changes size, so
/// the line never shifts under the finger.
class _PressDim extends StatefulWidget {
  const _PressDim({
    required this.onTap,
    required this.semanticsLabel,
    required this.child,
  });

  final VoidCallback onTap;
  final String semanticsLabel;
  final Widget child;

  @override
  State<_PressDim> createState() => _PressDimState();
}

class _PressDimState extends State<_PressDim> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      container: true,
      button: true,
      label: widget.semanticsLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapCancel: () => _set(false),
        onTapUp: (_) => _set(false),
        onTap: widget.onTap,
        child: reduceMotion
            ? Opacity(opacity: _pressed ? 0.6 : 1, child: widget.child)
            : SingleMotionBuilder(
                value: _pressed ? 0.6 : 1.0,
                motion: const CupertinoMotion.snappy(),
                child: widget.child,
                builder: (context, opacity, child) =>
                    Opacity(opacity: opacity.clamp(0.0, 1.0), child: child),
              ),
      ),
    );
  }
}
