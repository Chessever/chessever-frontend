import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:chessever2/screens/chessboard/notation/notation_cache.dart';
import 'package:chessever2/screens/chessboard/notation/notation_pointer.dart';
import 'package:chessever2/screens/chessboard/notation/notation_tree.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class NotationView extends ConsumerStatefulWidget {
  final ChessGame game;
  final EdgeInsets padding;
  const NotationView({super.key, required this.game, this.padding = EdgeInsets.zero});

  @override
  ConsumerState<NotationView> createState() => _NotationViewState();
}

class _NotationViewState extends ConsumerState<NotationView> {
  final _cache = NotationCache();
  final Map<String, bool> _collapsed = {};

  void _onTapMove(NotationId id) {
    final pointer = NotationPointerHelper.toPointer(id);
    ref.read(chessGameNavigatorProvider(widget.game).notifier).goToMovePointerUnchecked(pointer);
    HapticFeedback.selectionClick();
  }

  void _showMenuForHead(NotationId id) async {
    final pointer = NotationPointerHelper.toPointer(id);
    final navigator = ref.read(chessGameNavigatorProvider(widget.game).notifier);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: kBlack2Color,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Delete Variation'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
            ListTile(
              title: const Text('Promote to Mainline'),
              onTap: () => Navigator.pop(context, 'promote'),
            ),
            ListTile(
              title: const Text('Copy Line'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            ListTile(
              title: const Text('Start from here'),
              onTap: () => Navigator.pop(context, 'start'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'delete':
        navigator.deleteVariationAtPointer(pointer);
        HapticFeedback.heavyImpact();
        break;
      case 'promote':
        navigator.promoteVariationToMainline(pointer);
        HapticFeedback.heavyImpact();
        break;
      case 'copy':
        // Build PGN-like SAN line from this variation
        final state = ref.read(chessGameNavigatorProvider(widget.game));
        final lineSans = _collectVariationSans(state, pointer);
        await Clipboard.setData(ClipboardData(text: lineSans.join(' ')));
        HapticFeedback.mediumImpact();
        break;
      case 'start':
        ref.read(chessGameNavigatorProvider(widget.game).notifier).goToMovePointerUnchecked(pointer);
        HapticFeedback.selectionClick();
        break;
    }
  }

  List<String> _collectVariationSans(ChessGameNavigatorState state, List<int> pointer) {
    // Given pointer that points to first move of a variation (ends with ..., varIdx, 0)
    if (pointer.length < 2) return const [];
    // Traverse to the variation list
    List<ChessMove>? currentList = state.game.mainline;
    ChessMove? currentMove;
    for (var i = 0; i < pointer.length - 1; i++) {
      final idx = pointer[i];
      if (i.isEven) {
        currentMove = currentList![idx];
      } else {
        currentList = currentMove!.variations![idx];
      }
    }
    // Last element of pointer is index in that list
    final variationIndex = pointer[pointer.length - 2];
    final varList = currentMove!.variations![variationIndex];
    return varList.map((m) => m.san).toList();
  }

  InlineSpan _buildSpan(List<NotationNode> nodes, NotationId prefix, int start, int end,
      ChessGameNavigatorState navState) {
    final List<InlineSpan> children = [];
    for (int i = start; i < end; i++) {
      final n = nodes[i];
      // Move number display only on white moves
      final moveNum = n.isWhiteMove ? '${n.moveNumber}. ' : '';

      final isCurrent = navState.currentLine != null &&
          navState.currentMove?.uci == n.uci &&
          navState.currentFen == n.fenAfter;

      children.add(
        WidgetSpan(
          baseline: TextBaseline.alphabetic,
          alignment: PlaceholderAlignment.baseline,
          child: GestureDetector(
            onTap: () => _onTapMove(n.id),
            onLongPress: () {
              // If this node has variations, show menu on long press
              if (n.variations.isNotEmpty) _showMenuForHead(n.id);
            },
            child: Container(
              decoration: BoxDecoration(
                color: isCurrent ? kWhiteColor70.withValues(alpha: 0.3) : Colors.transparent,
                borderRadius: BorderRadius.circular(4.sp),
              ),
              padding: EdgeInsets.symmetric(horizontal: 3.sp, vertical: 2.sp),
              margin: EdgeInsets.symmetric(horizontal: 2.sp, vertical: 2.sp),
              child: Text(
                '$moveNum${n.san}',
                style: TextStyle(
                  color: n.isMainline ? kWhiteColor : kWhiteColor70,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12.sp,
                ),
              ),
            ),
          ),
        ),
      );

      // Render variations in parentheses right after this move if any
      if (n.variations.isNotEmpty) {
        final collapsed = _collapsed[n.id] ?? false;
        children.add(TextSpan(
          text: collapsed ? ' (···) ' : ' (',
          style: TextStyle(color: kWhiteColor70, fontSize: 12.sp),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              setState(() => _collapsed[n.id] = !collapsed);
              HapticFeedback.lightImpact();
            },
        ));

        if (!collapsed) {
          for (int v = 0; v < n.variations.length; v++) {
            final varLine = n.variations[v];
            for (int j = 0; j < varLine.length; j++) {
              final vn = varLine[j];
              final isVarHead = j == 0;
              children.add(WidgetSpan(
                baseline: TextBaseline.alphabetic,
                alignment: PlaceholderAlignment.baseline,
                child: GestureDetector(
                  onTap: () => _onTapMove(vn.id),
                  onLongPress: isVarHead ? () => _showMenuForHead(vn.id) : null,
                  child: Container(
                    decoration: BoxDecoration(
                      color: (navState.currentMove?.uci == vn.uci && navState.currentFen == vn.fenAfter)
                          ? kWhiteColor70.withValues(alpha: 0.3)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(4.sp),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: 3.sp, vertical: 2.sp),
                    margin: EdgeInsets.symmetric(horizontal: 2.sp, vertical: 2.sp),
                    child: Text(
                      vn.san,
                      style: TextStyle(
                        color: kWhiteColor70,
                        fontSize: 12.sp,
                        fontWeight: (navState.currentMove?.uci == vn.uci && navState.currentFen == vn.fenAfter)
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ));
            }
            if (v < n.variations.length - 1) {
              children.add(TextSpan(text: ' | ', style: TextStyle(color: kWhiteColor70, fontSize: 12.sp)));
            }
          }
        }

        children.add(TextSpan(text: ') ', style: TextStyle(color: kWhiteColor70, fontSize: 12.sp)));
      }
    }
    return TextSpan(children: children);
  }

  @override
  Widget build(BuildContext context) {
    final navigatorState = ref.watch(chessGameNavigatorProvider(widget.game));
    final nodes = _cache.build(navigatorState);

    return SingleChildScrollView(
      padding: widget.padding,
      child: RichText(
        text: _buildSpan(nodes, '', 0, nodes.length, navigatorState),
      ),
    );
  }
}
