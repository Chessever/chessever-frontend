import 'package:flutter/material.dart';
import 'package:chessever2/screens/chessboard/analysis/move_impact_analyzer.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/app_typography.dart';

/// Widget to display move impact annotation as an overlay on the board
class MoveAnnotationOverlay extends StatelessWidget {
  final MoveImpactType? impactType;
  final bool isVisible;
  final Offset position;

  const MoveAnnotationOverlay({
    Key? key,
    this.impactType,
    this.isVisible = false,
    this.position = Offset.zero,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!isVisible || impactType == null || impactType == MoveImpactType.normal) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: isVisible ? 1.0 : 0.0,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: 6.sp,
              vertical: 3.sp,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(4.sp),
              border: Border.all(
                color: impactType!.color.withOpacity(0.8),
                width: 1.5,
              ),
            ),
            child: Text(
              impactType!.symbol,
              style: AppTypography.textMdBold.copyWith(
                color: impactType!.color,
                fontSize: 16.sp,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Widget that manages displaying move annotations for the current move
class BoardMoveAnnotation extends StatefulWidget {
  final MoveImpactAnalysis? moveImpact;
  final double boardSize;
  final bool isFlipped;
  final String? lastMoveSquare; // e.g., "e4"

  const BoardMoveAnnotation({
    Key? key,
    this.moveImpact,
    required this.boardSize,
    required this.isFlipped,
    this.lastMoveSquare,
  }) : super(key: key);

  @override
  State<BoardMoveAnnotation> createState() => _BoardMoveAnnotationState();
}

class _BoardMoveAnnotationState extends State<BoardMoveAnnotation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    ));

    if (widget.moveImpact != null &&
        widget.moveImpact!.impact != MoveImpactType.normal) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(BoardMoveAnnotation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.moveImpact != oldWidget.moveImpact) {
      if (widget.moveImpact != null &&
          widget.moveImpact!.impact != MoveImpactType.normal) {
        _controller.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Offset _calculatePosition() {
    if (widget.lastMoveSquare == null || widget.lastMoveSquare!.length < 2) {
      return Offset(widget.boardSize - 50.sp, 20.sp);
    }

    // Parse the square (e.g., "e4")
    final file = widget.lastMoveSquare![0].codeUnitAt(0) - 'a'.codeUnitAt(0);
    final rank = int.parse(widget.lastMoveSquare![1]) - 1;

    final squareSize = widget.boardSize / 8;

    // Calculate position based on board orientation
    double x, y;
    if (widget.isFlipped) {
      x = (7 - file) * squareSize + squareSize * 0.6;
      y = rank * squareSize + squareSize * 0.1;
    } else {
      x = file * squareSize + squareSize * 0.6;
      y = (7 - rank) * squareSize + squareSize * 0.1;
    }

    return Offset(x, y);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.moveImpact == null ||
        widget.moveImpact!.impact == MoveImpactType.normal) {
      return const SizedBox.shrink();
    }

    final position = _calculatePosition();

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Opacity(
                opacity: _fadeAnimation.value,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 8.sp,
                    vertical: 4.sp,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(6.sp),
                    border: Border.all(
                      color: widget.moveImpact!.impact.color,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: widget.moveImpact!.impact.color.withOpacity(0.4),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Text(
                    widget.moveImpact!.impact.symbol,
                    style: AppTypography.textLgBold.copyWith(
                      color: widget.moveImpact!.impact.color,
                      fontSize: 18.sp,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}