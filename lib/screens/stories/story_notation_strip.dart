import 'package:chessever2/screens/chessboard/widgets/nag_display.dart';
import 'package:chessever2/screens/stories/story_notation.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// One line of moves with a route back to the parent when viewing a branch.
class StoryNotationStrip extends StatefulWidget {
  const StoryNotationStrip({
    super.key,
    required this.moves,
    required this.selected,
    required this.selectedStyle,
    required this.glyphInk,
    required this.onMove,
    required this.onVariation,
    required this.onRead,
    this.onParent,
    this.headline = true,
  });

  final List<StoryNotationMove> moves;
  final int selected;
  final TextStyle selectedStyle;
  final Color Function(BuildContext, NagDisplay) glyphInk;
  final ValueChanged<int> onMove;
  final void Function(int index, StoryNotationVariation variation) onVariation;
  final VoidCallback onRead;
  final VoidCallback? onParent;
  final bool headline;

  @override
  State<StoryNotationStrip> createState() => _StoryNotationStripState();
}

class _StoryNotationStripState extends State<StoryNotationStrip> {
  final _scroll = ItemScrollController();
  final _positions = ItemPositionsListener.create();

  static double _alignment(int index) => index == 0 ? 0 : 0.35;

  @override
  void didUpdateWidget(covariant StoryNotationStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.moves, widget.moves) ||
        oldWidget.selected == widget.selected) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.isAttached) return;
      final index = widget.selected;
      final visible = _positions.itemPositions.value.any(
        (item) =>
            item.index == index &&
            item.itemLeadingEdge >= 0 &&
            item.itemTrailingEdge <= 1,
      );
      if (!visible) _scroll.jumpTo(index: index, alignment: _alignment(index));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Row(
        children: [
          if (widget.onParent case final parent?)
            IconButton(
              key: const ValueKey('story_notation_parent'),
              tooltip: 'Back to parent line',
              onPressed: parent,
              icon: const BackButtonIcon(),
              iconSize: 18,
            ),
          Expanded(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: ScrollablePositionedList.builder(
                key: ObjectKey(widget.moves),
                itemCount: widget.moves.length,
                itemScrollController: _scroll,
                itemPositionsListener: _positions,
                initialScrollIndex: widget.selected,
                initialAlignment: _alignment(widget.selected),
                scrollDirection: Axis.horizontal,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                itemBuilder: _move,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _move(BuildContext context, int index) {
    final move = widget.moves[index];
    final selected = index == widget.selected;
    final colors = context.colors;
    final style = selected
        ? widget.selectedStyle
        : widget.selectedStyle.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: colors.textSecondary,
          );
    final showNumber = selected || index == 0 || move.ply.mover == Side.white;
    final variations = move.variations;
    final label = '${move.number} ${move.ply.san}';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          selected: selected,
          label: label,
          excludeSemantics: true,
          onTap: () => widget.onMove(index),
          child: InkWell(
            key: ValueKey('story_notation_move_$index'),
            onTap: () => widget.onMove(index),
            child: Container(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Text.rich(
                TextSpan(
                  style: style,
                  children: [
                    if (showNumber)
                      TextSpan(
                        text: '${move.number} ',
                        style: style.copyWith(fontWeight: FontWeight.w500),
                      ),
                    TextSpan(text: move.ply.san),
                    if (selected)
                      for (final nag in move.ply.nags)
                        if (nagShownAsText(nag))
                          if (getNagDisplay(nag) case final display?)
                            TextSpan(
                              text: display.isQuality
                                  ? display.symbol
                                  : ' ${display.symbol}',
                              style: style.copyWith(
                                color: widget.glyphInk(context, display),
                              ),
                            ),
                  ],
                ),
                key: selected && widget.headline
                    ? const ValueKey('story_move')
                    : null,
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
        ),
        if (variations.length == 1)
          IconButton(
            key: ValueKey('story_notation_variation_$index'),
            tooltip: 'Variation for $label',
            color: colors.textSecondary,
            iconSize: 16,
            onPressed: () => widget.onVariation(index, variations.single),
            icon: const Icon(Icons.alt_route_rounded),
          )
        else if (variations.isNotEmpty)
          PopupMenuButton<StoryNotationVariation>(
            key: ValueKey('story_notation_variation_$index'),
            tooltip: '${variations.length} variations for $label',
            icon: Icon(Icons.alt_route_rounded, color: colors.textSecondary),
            iconSize: 16,
            onOpened: widget.onRead,
            onSelected: (variation) => widget.onVariation(index, variation),
            itemBuilder: (context) => [
              for (final variation in variations)
                PopupMenuItem(
                  value: variation,
                  child: Text('${move.number} ${variation.san}'),
                ),
            ],
          ),
      ],
    );
  }
}
