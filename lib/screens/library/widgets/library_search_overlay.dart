import 'dart:math' as math;

import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/library/providers/library_combined_search_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class LibrarySearchOverlay extends ConsumerWidget {
  final String query;
  final Function(LibraryFolder) onFolderTap;
  final Function(SavedAnalysis) onAnalysisTap;
  final Function(GamebasePlayer) onPlayerTap;
  final Function(Map<String, dynamic>) onGameTap;

  const LibrarySearchOverlay({
    super.key,
    required this.query,
    required this.onFolderTap,
    required this.onAnalysisTap,
    required this.onPlayerTap,
    required this.onGameTap,
  });

  double _computeMaxHeight(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenH = mq.size.height;
    final keyboard = mq.viewInsets.bottom;
    final topSafe = mq.padding.top;
    final reservedAbove = 120.h;
    final available = screenH - topSafe - keyboard - reservedAbove;
    final cap = screenH * 0.60;
    return available.clamp(200.h, cap);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (query.trim().isEmpty) return const SizedBox.shrink();

    final maxH = _computeMaxHeight(context);
    final searchAsync = ref.watch(libraryCombinedSearchProvider(query));

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF09090B), // Zinc 950
        borderRadius: BorderRadius.circular(16.br),
        border: Border.all(color: const Color(0xFF27272A)), // Zinc 800
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16.br),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: searchAsync.when(
            loading: () => _buildLoadingState(maxH),
            error: (e, _) => _buildErrorState(e.toString(), maxH),
            data: (result) {
              if (result.isEmpty) return _buildEmptyState(maxH);
              return _buildResultsList(result);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildResultsList(LibrarySearchResult result) {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (result.folders.isNotEmpty) ...[
            _buildSectionHeader('Books'),
            ...result.folders.map((f) => _buildFolderTile(f)),
            SizedBox(height: 8.h),
          ],
          if (result.analyses.isNotEmpty) ...[
            _buildSectionHeader('Saved Games'),
            ...result.analyses.map((a) => _buildAnalysisTile(a)),
            SizedBox(height: 8.h),
          ],
          if (result.players.isNotEmpty) ...[
            _buildSectionHeader('Players'),
            ...result.players.map((p) => _buildPlayerTile(p)),
            SizedBox(height: 8.h),
          ],
          if (result.games.isNotEmpty) ...[
            _buildSectionHeader('Database Games'),
            ...result.games.map((g) => _buildGameTile(g)),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 8.h),
      child: Text(
        title,
        style: AppTypography.textXsBold.copyWith(
          color: const Color(0xFFA1A1AA), // Zinc 400
          letterSpacing: 0.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildFolderTile(LibraryFolder folder) {
    return _BaseResultTile(
      onTap: () => onFolderTap(folder),
      icon: Icons.folder_open_rounded,
      title: folder.name,
      subtitle: 'Book',
    );
  }

  Widget _buildAnalysisTile(SavedAnalysis analysis) {
    final white = analysis.chessGame.metadata['White'] ?? 'Unknown';
    final black = analysis.chessGame.metadata['Black'] ?? 'Unknown';
    return _BaseResultTile(
      onTap: () => onAnalysisTap(analysis),
      icon: Icons.grid_view_rounded, // Chessboard icon substitute
      title: analysis.title,
      subtitle: '$white vs $black',
    );
  }

  Widget _buildPlayerTile(GamebasePlayer player) {
    return _BaseResultTile(
      onTap: () => onPlayerTap(player),
      icon: Icons.person_outline_rounded,
      title: player.name,
      subtitle: '${player.title ?? ''} • ${player.fed}',
      isRoundedIcon: true,
    );
  }

  Widget _buildGameTile(Map<String, dynamic> game) {
    final white =
        game['white']?.toString() ?? game['whiteName']?.toString() ?? '?';
    final black =
        game['black']?.toString() ?? game['blackName']?.toString() ?? '?';
    final result = game['result']?.toString() ?? '*';
    final date = game['date']?.toString().split('T').first ?? '';

    return _BaseResultTile(
      onTap: () => onGameTap(game),
      icon: Icons.emoji_events_outlined,
      title: '$white vs $black',
      subtitle: '$result • $date',
    );
  }

  Widget _buildLoadingState(double h) {
    return SizedBox(
      height: math.min(h, 160.h),
      child: const Center(
        child: CircularProgressIndicator(color: kWhiteColor),
      ),
    );
  }

  Widget _buildErrorState(String error, double h) {
    return SizedBox(
      height: math.min(h, 160.h),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(16.sp),
          child: Text(
            'Search failed',
            style: AppTypography.textSmMedium.copyWith(color: kRedColor),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(double h) {
    return SizedBox(
      height: math.min(h, 160.h),
      child: Center(
        child: Text(
          'No results found',
          style: AppTypography.textSmRegular.copyWith(
            color: const Color(0xFFA1A1AA),
          ),
        ),
      ),
    );
  }
}

class _BaseResultTile extends StatefulWidget {
  final VoidCallback onTap;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isRoundedIcon;

  const _BaseResultTile({
    required this.onTap,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.isRoundedIcon = false,
  });

  @override
  State<_BaseResultTile> createState() => _BaseResultTileState();
}

class _BaseResultTileState extends State<_BaseResultTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isHovered = true),
      onTapUp: (_) => setState(() => _isHovered = false),
      onTapCancel: () => setState(() => _isHovered = false),
      onTap: widget.onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
        color: _isHovered ? const Color(0xFF27272A) : Colors.transparent,
        child: Row(
          children: [
            Container(
              width: 32.sp,
              height: 32.sp,
              decoration: BoxDecoration(
                color: const Color(0xFF18181B), // Zinc 900
                shape:
                    widget.isRoundedIcon ? BoxShape.circle : BoxShape.rectangle,
                borderRadius:
                    widget.isRoundedIcon ? null : BorderRadius.circular(6.br),
                border: Border.all(color: const Color(0xFF27272A)),
              ),
              child: Icon(
                widget.icon,
                size: 16.sp,
                color: const Color(0xFFA1A1AA), // Zinc 400
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: AppTypography.textSmMedium.copyWith(
                      color: const Color(0xFFFAFAFA),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    widget.subtitle,
                    style: AppTypography.textXsRegular.copyWith(
                      color: const Color(0xFFA1A1AA),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
