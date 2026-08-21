import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/search/search_result_model.dart';
import 'package:flutter/material.dart';

class SearchResultTile extends StatefulWidget {
  const SearchResultTile({
    super.key,
    required this.result,
    required this.onTap,
    this.isPlayerResult = false,
    this.isFullWidth = false,
  });

  final SearchResult result;
  final VoidCallback onTap;
  final bool isPlayerResult;
  final bool isFullWidth;

  @override
  State<SearchResultTile> createState() => _SearchResultTileState();
}

class _SearchResultTileState extends State<SearchResultTile>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1,
      end: 1.02,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        MouseRegion(
          onEnter: (_) {
            setState(() => _isHovered = true);
            _controller.forward();
          },
          onExit: (_) {
            setState(() => _isHovered = false);
            _controller.reverse();
          },
          child: AnimatedBuilder(
            animation: _scaleAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: GestureDetector(
                  onTap: widget.onTap,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: EdgeInsets.symmetric(
                      horizontal: 4.w,
                      vertical: 4.h,
                    ),
                    decoration: BoxDecoration(
                      color:
                          _isHovered
                              ? context.colors.surfaceRecessed
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(12.br),
                      border: Border.all(
                        color:
                            _isHovered
                                ? Colors.blue.withValues(alpha: 0.3)
                                : Colors.transparent,
                      ),
                    ),
                    child:
                        widget.isPlayerResult
                            ? _buildPlayerContent()
                            : _buildTournamentContent(),
                  ),
                ),
              );
            },
          ),
        ),
        Container(
          margin: EdgeInsets.symmetric(vertical: 4.h),
          height: 1,
          color: context.colors.divider,
        ),
      ],
    );
  }

  Widget _buildPlayerContent() {
    final player = widget.result.player;
    final title = player?.title;
    final rating = player?.rating;
    final fed = player?.fed;
    final hasTitle = title != null && title.isNotEmpty;
    final hasRating = rating != null && rating > 0;
    final hasFed = fed != null && fed.isNotEmpty;
    final displayName =
        hasTitle
            ? '$title ${player?.name ?? widget.result.matchedText}'
            : (player?.name ?? widget.result.matchedText);
    final subtitleParts = <String>[if (hasRating) '$rating', if (hasFed) fed];
    final subtitle =
        subtitleParts.isNotEmpty ? subtitleParts.join(' • ') : null;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (subtitle != null) ...[
                SizedBox(height: 4.h),
                Text(
                  subtitle,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTournamentContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.result.tournament.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (widget.result.tournament.dates.isNotEmpty) ...[
          SizedBox(height: 8.h),
          Row(
            children: [
              Icon(Icons.calendar_today, size: 12.ic, color: Colors.grey[400]),
              SizedBox(width: 4.w),
              Expanded(
                child: Text(
                  widget.result.tournament.dates,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey[400], fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
