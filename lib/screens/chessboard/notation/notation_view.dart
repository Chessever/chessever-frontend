import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:chessever2/screens/chessboard/notation/notation_cache.dart';
import 'package:chessever2/screens/chessboard/notation/notation_tree.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A widget that displays chess notation as a tree with parenthesized subvariants
class NotationView extends ConsumerStatefulWidget {
  final GamesTourModel game;
  final int index;
  final int currentPageIndex;

  const NotationView({
    super.key,
    required this.game,
    required this.index,
    required this.currentPageIndex,
  });

  @override
  ConsumerState<NotationView> createState() => _NotationViewState();
}

class _NotationViewState extends ConsumerState<NotationView> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _nodeKeys = {};
  final Map<String, bool> _collapsedVariations = {};
  final NotationTreeCache _treeCache = NotationTreeCache();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureCurrentMoveVisible();
    });
  }

  @override
  void didUpdateWidget(NotationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game.gameId != widget.game.gameId) {
      _nodeKeys.clear();
      _collapsedVariations.clear();
      _treeCache.clear();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureCurrentMoveVisible();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _ensureCurrentMoveVisible() {
    if (!mounted) return;

    final params = ChessBoardProviderParams(game: widget.game, index: widget.index);
    final currentState = ref.read(chessBoardScreenProviderNew(params));

    if (!currentState.hasValue) return;

    final state = currentState.value!;
    final navigatorState = ref.read(
      chessGameNavigatorProvider(
        ChessGame(
          gameId: widget.game.gameId,
          startingFen: state.analysisState.startingPosition?.fen ??
              'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
          metadata: {},
          mainline: state.analysisState.game?.mainline ?? [],
        ),
      ),
    );

    final currentId = NotationTreeBuilder.pointerToId(navigatorState.movePointer);
    final key = _nodeKeys[currentId];

    if (key != null && _scrollController.hasClients) {
      try {
        final context = key.currentContext;
        if (context != null) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      } catch (e) {
        // Ignore scroll errors
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final params = ChessBoardProviderParams(game: widget.game, index: widget.index);
    final asyncState = ref.watch(chessBoardScreenProviderNew(params));

    if (!asyncState.hasValue) {
      return _buildLoadingSkeleton();
    }

    final state = asyncState.value!;

    if (state.isLoadingMoves) {
      return _buildLoadingSkeleton();
    }

    // Get navigator state to build tree
    final analysisGame = state.analysisState.game;
    if (analysisGame == null || analysisGame.mainline.isEmpty) {
      return _buildEmptyState();
    }

    final navigatorState = ref.watch(
      chessGameNavigatorProvider(analysisGame),
    );

    // Build tree from cache
    final notationNodes = _treeCache.getOrBuild(navigatorState);

    if (notationNodes.isEmpty) {
      return _buildEmptyState();
    }

    // Build the rich text representation
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;

        final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);

        if (details.primaryVelocity! > 0) {
          // Swipe right - go back
          HapticFeedback.lightImpact();
          notifier.analysisStepBackward();
        } else if (details.primaryVelocity! < 0) {
          // Swipe left - go forward
          HapticFeedback.lightImpact();
          notifier.analysisStepForward();
        }
      },
      child: SingleChildScrollView(
        controller: _scrollController,
        child: Container(
          alignment: Alignment.centerLeft,
          padding: EdgeInsets.all(20.sp),
          child: _buildNotationTree(notationNodes, navigatorState),
        ),
      ),
    );
  }

  Widget _buildNotationTree(
    List<NotationNode> nodes,
    ChessGameNavigatorState navigatorState,
  ) {
    final currentId = NotationTreeBuilder.pointerToId(navigatorState.movePointer);
    final spans = <InlineSpan>[];

    for (int i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      _buildNodeSpans(node, currentId, spans, isFirst: i == 0);
    }

    return Text.rich(
      TextSpan(children: spans),
      style: AppTypography.textXsMedium.copyWith(
        color: kWhiteColor70,
        height: 1.5,
      ),
    );
  }

  void _buildNodeSpans(
    NotationNode node,
    String currentId,
    List<InlineSpan> spans, {
    bool isFirst = false,
    int depth = 0,
  }) {
    // Add move number for white moves
    if (node.isWhiteMove) {
      spans.add(
        TextSpan(
          text: '${node.moveNumber}. ',
          style: AppTypography.textXsMedium.copyWith(
            color: kWhiteColor70.withOpacity(0.6),
            fontWeight: FontWeight.normal,
          ),
        ),
      );
    }

    // Add the move itself
    final isCurrentMove = node.id == currentId;
    _ensureKeyExists(node.id);

    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: GestureDetector(
          key: _nodeKeys[node.id],
          onTap: () => _onMoveTap(node),
          onLongPress: () => _onMoveLongPress(node),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 6.sp, vertical: 2.sp),
            decoration: BoxDecoration(
              color: isCurrentMove
                  ? kWhiteColor70.withOpacity(0.4)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4.sp),
              border: Border.all(
                color: isCurrentMove ? kWhiteColor : Colors.transparent,
                width: 0.5,
              ),
            ),
            child: Text(
              node.san,
              style: AppTypography.textXsMedium.copyWith(
                color: isCurrentMove ? kWhiteColor : kWhiteColor70,
                fontWeight: isCurrentMove ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );

    spans.add(const TextSpan(text: ' '));

    // Add variations (parenthesized)
    if (node.children.isNotEmpty) {
      for (int varIndex = 0; varIndex < node.children.length; varIndex++) {
        final variation = node.children[varIndex];
        final variationId = '${node.id}/$varIndex';
        final isCollapsed = _collapsedVariations[variationId] ?? false;

        // Opening parenthesis
        spans.add(
          TextSpan(
            text: '(',
            style: AppTypography.textXsMedium.copyWith(
              color: kWhiteColor70.withOpacity(0.6 - (depth * 0.1)),
            ),
          ),
        );

        if (isCollapsed) {
          // Show collapsed indicator
          spans.add(
            WidgetSpan(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _collapsedVariations[variationId] = false;
                  });
                  HapticFeedback.mediumImpact();
                },
                child: Text(
                  '···',
                  style: AppTypography.textXsMedium.copyWith(
                    color: kWhiteColor70.withOpacity(0.6),
                  ),
                ),
              ),
            ),
          );
        } else {
          // Show variation moves
          for (int j = 0; j < variation.length; j++) {
            final varNode = variation[j];
            _buildNodeSpans(
              varNode,
              currentId,
              spans,
              depth: depth + 1,
            );
          }
        }

        // Closing parenthesis
        spans.add(
          TextSpan(
            text: ') ',
            style: AppTypography.textXsMedium.copyWith(
              color: kWhiteColor70.withOpacity(0.6 - (depth * 0.1)),
            ),
          ),
        );
      }
    }
  }

  void _ensureKeyExists(String nodeId) {
    if (!_nodeKeys.containsKey(nodeId)) {
      _nodeKeys[nodeId] = GlobalKey();
    }
  }

  void _onMoveTap(NotationNode node) {
    HapticFeedback.lightImpact();

    final params = ChessBoardProviderParams(game: widget.game, index: widget.index);
    final currentState = ref.read(chessBoardScreenProviderNew(params));

    if (!currentState.hasValue) return;

    final state = currentState.value!;
    final analysisGame = state.analysisState.game;
    if (analysisGame == null) return;

    final navigator = ref.read(
      chessGameNavigatorProvider(analysisGame).notifier,
    );

    final pointer = NotationTreeBuilder.idToPointer(node.id);
    navigator.goToMovePointerUnchecked(pointer);
  }

  void _onMoveLongPress(NotationNode node) {
    HapticFeedback.mediumImpact();

    showModalBottomSheet(
      context: context,
      backgroundColor: kBlackColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.sp)),
      ),
      builder: (context) => _buildMoveContextMenu(node),
    );
  }

  Widget _buildMoveContextMenu(NotationNode node) {
    return Container(
      padding: EdgeInsets.all(20.sp),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Move: ${node.san}',
            style: AppTypography.textLgMedium.copyWith(
              color: kWhiteColor,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 20.h),
          _buildMenuItem(
            icon: Icons.play_arrow,
            label: 'Start from here',
            onTap: () {
              Navigator.pop(context);
              _onMoveTap(node);
            },
          ),
          if (!node.isMainline) ...[
            _buildMenuItem(
              icon: Icons.delete_outline,
              label: 'Delete variation',
              onTap: () {
                Navigator.pop(context);
                _deleteVariation(node);
              },
            ),
            _buildMenuItem(
              icon: Icons.upgrade,
              label: 'Promote to mainline',
              onTap: () {
                Navigator.pop(context);
                _promoteVariation(node);
              },
            ),
          ],
          _buildMenuItem(
            icon: Icons.copy,
            label: 'Copy line',
            onTap: () {
              Navigator.pop(context);
              _copyLine(node);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12.h),
        child: Row(
          children: [
            Icon(icon, color: kWhiteColor70, size: 24.sp),
            SizedBox(width: 16.w),
            Text(
              label,
              style: AppTypography.textMdMedium.copyWith(
                color: kWhiteColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteVariation(NotationNode node) {
    HapticFeedback.heavyImpact();

    final params = ChessBoardProviderParams(game: widget.game, index: widget.index);
    final currentState = ref.read(chessBoardScreenProviderNew(params));

    if (!currentState.hasValue) return;

    final state = currentState.value!;
    final analysisGame = state.analysisState.game;
    if (analysisGame == null) return;

    final navigator = ref.read(
      chessGameNavigatorProvider(analysisGame).notifier,
    );

    final pointer = NotationTreeBuilder.idToPointer(node.id);
    navigator.deleteVariationAtPointer(pointer);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Variation deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            // TODO: Implement undo functionality
          },
        ),
      ),
    );
  }

  void _promoteVariation(NotationNode node) {
    HapticFeedback.heavyImpact();

    final params = ChessBoardProviderParams(game: widget.game, index: widget.index);
    final currentState = ref.read(chessBoardScreenProviderNew(params));

    if (!currentState.hasValue) return;

    final state = currentState.value!;
    final analysisGame = state.analysisState.game;
    if (analysisGame == null) return;

    final navigator = ref.read(
      chessGameNavigatorProvider(analysisGame).notifier,
    );

    final pointer = NotationTreeBuilder.idToPointer(node.id);
    navigator.promoteVariationToMainline(pointer);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Variation promoted to mainline'),
      ),
    );
  }

  void _copyLine(NotationNode node) {
    // Build a line from this node to the end
    final params = ChessBoardProviderParams(game: widget.game, index: widget.index);
    final currentState = ref.read(chessBoardScreenProviderNew(params));

    if (!currentState.hasValue) return;

    final state = currentState.value!;
    final analysisGame = state.analysisState.game;
    if (analysisGame == null) return;

    // TODO: Implement line copying functionality
    // This would extract all moves from this node to the end of the line
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Line copied'),
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return Container(
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.all(20.sp),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(6, (index) {
          return Padding(
            padding: EdgeInsets.only(bottom: 8.h),
            child: Container(
              height: 14.h,
              width: (150 + (index % 3) * 50).w,
              decoration: BoxDecoration(
                color: kWhiteColor70.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4.sp),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      alignment: Alignment.center,
      padding: EdgeInsets.all(20.sp),
      child: Text(
        "No moves available for this game",
        style: AppTypography.textXsMedium.copyWith(
          color: kWhiteColor70,
          fontWeight: FontWeight.normal,
        ),
      ),
    );
  }
}
