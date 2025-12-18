import 'dart:math' as math;

import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/library/providers/library_combined_search_provider.dart';
import 'package:chessever2/utils/chess_title_utils.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/federation_flag.dart';
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
            _buildSectionHeader('Games'),
            ...result.games.take(6).map((g) => _buildGameTile(g)),
            SizedBox(height: 8.h),
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
    final title = ChessTitleUtils.normalize(player.title);
    final subtitleParts = <String>[
      if (player.fed.trim().isNotEmpty) player.fed.trim(),
      if (player.highestRating != null && player.highestRating! > 0)
        'Elo ${player.highestRating}',
    ];

    return _PlayerResultTile(
      onTap: () => onPlayerTap(player),
      title: player.displayName,
      subtitle: subtitleParts.join(' • '),
      titlePrefix: title,
      federation: player.fed,
    );
  }

  Widget _buildGameTile(Map<String, dynamic> row) {
    final white =
        row['white']?.toString() ??
        row['whiteName']?.toString() ??
        row['White']?.toString() ??
        'White';
    final black =
        row['black']?.toString() ??
        row['blackName']?.toString() ??
        row['Black']?.toString() ??
        'Black';

    final whiteFed =
        row['whiteFed']?.toString() ??
        row['white_player']?['fed']?.toString() ??
        '';
    final blackFed =
        row['blackFed']?.toString() ??
        row['black_player']?['fed']?.toString() ??
        '';

    final whiteTitle = ChessTitleUtils.normalize(
      row['whiteTitle']?.toString() ?? row['white_player']?['title']?.toString(),
    );
    final blackTitle = ChessTitleUtils.normalize(
      row['blackTitle']?.toString() ?? row['black_player']?['title']?.toString(),
    );

    int parseRating(Object? value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    final whiteRating = parseRating(row['whiteRating']);
    final blackRating = parseRating(row['blackRating']);

    final eco = row['eco']?.toString() ?? row['ECO']?.toString() ?? '';
    final event =
        row['event']?.toString() ??
        row['Event']?.toString() ??
        row['tourId']?.toString() ??
        '';

    DateTime? date;
    final rawDate = row['date']?.toString();
    if (rawDate != null && rawDate.isNotEmpty) {
      date = DateTime.tryParse(rawDate);
    }

    final subtitleParts = <String>[
      if (eco.trim().isNotEmpty) eco.trim(),
      if (event.trim().isNotEmpty) event.trim(),
      if (date != null)
        '${date.year.toString().padLeft(4, '0')}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}',
    ];

    return _GameResultTile(
      onTap: () => onGameTap(row),
      whiteName: white,
      blackName: black,
      whiteFederation: whiteFed,
      blackFederation: blackFed,
      whiteTitle: whiteTitle,
      blackTitle: blackTitle,
      whiteRating: whiteRating,
      blackRating: blackRating,
      subtitle:
          subtitleParts.isNotEmpty ? subtitleParts.join(' • ') : 'Gamebase',
    );
  }

  Widget _buildLoadingState(double h) {
    return SizedBox(
      height: math.min(h, 160.h),
      child: const Center(child: CircularProgressIndicator(color: kWhiteColor)),
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

class _PlayerResultTile extends StatefulWidget {
  const _PlayerResultTile({
    required this.onTap,
    required this.title,
    required this.subtitle,
    required this.federation,
    this.titlePrefix,
  });

  final VoidCallback onTap;
  final String title;
  final String subtitle;
  final String federation;
  final String? titlePrefix;

  @override
  State<_PlayerResultTile> createState() => _PlayerResultTileState();
}

class _PlayerResultTileState extends State<_PlayerResultTile> {
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
                color: const Color(0xFF18181B),
                borderRadius: BorderRadius.circular(8.br),
                border: Border.all(color: const Color(0xFF27272A)),
              ),
              alignment: Alignment.center,
              child: FederationFlag(
                federation: widget.federation,
                width: 18.sp,
                height: 13.sp,
                borderRadius: BorderRadius.circular(2.br),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if ((widget.titlePrefix ?? '').trim().isNotEmpty) ...[
                        Text(
                          widget.titlePrefix!.trim(),
                          style: AppTypography.textSmBold.copyWith(
                            color: const Color(0xFFFAFAFA),
                          ),
                        ),
                        SizedBox(width: 6.w),
                      ],
                      Expanded(
                        child: Text(
                          widget.title,
                          style: AppTypography.textSmMedium.copyWith(
                            color: const Color(0xFFFAFAFA),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
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

class _GameResultTile extends StatefulWidget {
  const _GameResultTile({
    required this.onTap,
    required this.whiteName,
    required this.blackName,
    required this.whiteFederation,
    required this.blackFederation,
    required this.whiteTitle,
    required this.blackTitle,
    required this.whiteRating,
    required this.blackRating,
    required this.subtitle,
  });

  final VoidCallback onTap;
  final String whiteName;
  final String blackName;
  final String whiteFederation;
  final String blackFederation;
  final String whiteTitle;
  final String blackTitle;
  final int whiteRating;
  final int blackRating;
  final String subtitle;

  @override
  State<_GameResultTile> createState() => _GameResultTileState();
}

class _GameResultTileState extends State<_GameResultTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final leftMeta = [
      if (widget.whiteTitle.trim().isNotEmpty) widget.whiteTitle.trim(),
      if (widget.whiteRating > 0) widget.whiteRating.toString(),
    ].join(' ');

    final rightMeta = [
      if (widget.blackTitle.trim().isNotEmpty) widget.blackTitle.trim(),
      if (widget.blackRating > 0) widget.blackRating.toString(),
    ].join(' ');

    final metaLine = [
      if (leftMeta.isNotEmpty) leftMeta,
      if (rightMeta.isNotEmpty) rightMeta,
    ].join(' • ');

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
                color: const Color(0xFF18181B),
                borderRadius: BorderRadius.circular(8.br),
                border: Border.all(color: const Color(0xFF27272A)),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FederationFlag(
                    federation: widget.whiteFederation,
                    width: 18.sp,
                    height: 11.sp,
                    borderRadius: BorderRadius.circular(2.br),
                  ),
                  SizedBox(height: 2.h),
                  FederationFlag(
                    federation: widget.blackFederation,
                    width: 18.sp,
                    height: 11.sp,
                    borderRadius: BorderRadius.circular(2.br),
                  ),
                ],
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.whiteName} vs ${widget.blackName}',
                    style: AppTypography.textSmMedium.copyWith(
                      color: const Color(0xFFFAFAFA),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    metaLine.isNotEmpty ? metaLine : widget.subtitle,
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
