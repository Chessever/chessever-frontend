import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/library/widgets/import_pgn_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/library_game_card.dart';
import 'package:chessever2/services/pgn_file_intake_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Middle-step UI shown when the user pastes a blob containing multiple PGNs.
/// Lists each parsed game as a card (players, result, ECO, opening) and
/// provides a save icon in the top bar that opens the folder-picker sheet.
class PgnImportPreviewScreen extends ConsumerStatefulWidget {
  const PgnImportPreviewScreen({
    super.key,
    required this.games,
    this.initialFolderId,
    this.sourceLabel,
  });

  final List<ChessGame> games;
  final String? initialFolderId;
  final String? sourceLabel;

  @override
  ConsumerState<PgnImportPreviewScreen> createState() =>
      _PgnImportPreviewScreenState();
}

class _PgnImportPreviewScreenState
    extends ConsumerState<PgnImportPreviewScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController =
        TextEditingController()..addListener(() {
          setState(() {});
        });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    HapticFeedbackService.light();
    _searchController.clear();
  }

  Future<void> _handleSave() async {
    HapticFeedbackService.medium();
    final saved = await showImportPgnToFolderSheet(
      context: context,
      games: widget.games,
      initialFolderId: widget.initialFolderId,
      sourceLabel: widget.sourceLabel,
    );
    if (saved && mounted) {
      Navigator.of(context).pop();
    }
  }

  void _openGame(int index) {
    HapticFeedbackService.cardTap();
    // Build a minimal GamesTourModel per game, embedding the full PGN so
    // ChessBoardScreenNew can render it without a Supabase lookup.
    final games =
        widget.games.map(chessGameToImportedGamesTourModel).toList();

    ref.read(chessboardViewFromProviderNew.notifier).state =
        ChessboardView.tour;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => ChessBoardScreenNew(
              currentIndex: index,
              games: games,
              showGamebaseButton: false,
              disableGamebaseOverlayByDefault: true,
            ),
      ),
    );
  }

  bool _matches(ChessGame game, String query) {
    if (query.isEmpty) return true;
    final md = game.metadata;
    final fields = [
      md['White']?.toString() ?? '',
      md['Black']?.toString() ?? '',
      md['Event']?.toString() ?? '',
      md['Site']?.toString() ?? '',
      md['Opening']?.toString() ?? '',
      md['ECO']?.toString() ?? '',
    ];
    return fields.any((f) => f.toLowerCase().contains(query));
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = <({ChessGame game, int originalIndex})>[];
    for (var i = 0; i < widget.games.length; i++) {
      if (_matches(widget.games[i], query)) {
        filtered.add((game: widget.games[i], originalIndex: i));
      }
    }

    return Scaffold(
      backgroundColor: context.colors.background,
      body: ScreenWrapper(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth:
                  ResponsiveHelper.isTablet
                      ? ResponsiveHelper.contentMaxWidth
                      : double.infinity,
            ),
            child: Column(
              children: [
                _buildTopArea(context),
                Expanded(child: _buildList(filtered, query)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopArea(BuildContext context) {
    final topPadding = MediaQuery.of(context).viewPadding.top;
    return Container(
      padding: EdgeInsets.only(top: topPadding + 8.h, bottom: 6.h),
      decoration:  BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            context.colors.background,
            context.colors.background.withValues(alpha: 0),
          ],
        ),
      ),
      child: Column(
        children: [_buildHeader(context), _buildSearchBar()],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 8.w,
      tablet: 16.w,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        0,
        horizontalPadding,
        8.h,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: () {
                HapticFeedbackService.light();
                Navigator.of(context).pop();
              },
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: context.colors.textPrimary,
                size: 20.ic,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              onPressed: _handleSave,
              tooltip: 'Save to database',
              icon: Icon(
                Icons.save_rounded,
                color: context.colors.textPrimary,
                size: 26.ic,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 56.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Import PGN',
                  style: AppTypography.textLgBold.copyWith(
                    color: context.colors.textPrimary,
                    height: 1.1,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  widget.games.length == 1
                      ? '1 game'
                      : '${widget.games.length} games',
                  style: AppTypography.textXsRegular.copyWith(
                    color: context.colors.textPrimary.withValues(alpha: 0.5),
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      child: Container(
        height: 38.h,
        decoration: BoxDecoration(
          color: context.colors.textPrimary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10.br),
        ),
        child: Row(
          children: [
            SizedBox(width: 12.w),
            Icon(
              Icons.search_rounded,
              size: 18.sp,
              color: const Color(0xFFA1A1AA),
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: TextField(
                controller: _searchController,
                style: AppTypography.textSmRegular.copyWith(color: context.colors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search games...',
                  hintStyle: AppTypography.textSmRegular.copyWith(
                    color: const Color(0xFFA1A1AA),
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
              ),
            ),
            if (_searchController.text.isNotEmpty) ...[
              GestureDetector(
                onTap: _clearSearch,
                child: Icon(
                  Icons.close,
                  size: 20.sp,
                  color: const Color(0xFFA1A1AA),
                ),
              ),
              SizedBox(width: 8.w),
            ],
            SizedBox(width: 8.w),
          ],
        ),
      ),
    );
  }

  Widget _buildList(
    List<({ChessGame game, int originalIndex})> filtered,
    String query,
  ) {
    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              query.isEmpty
                  ? Icons.inbox_outlined
                  : Icons.search_off_rounded,
              size: 64.sp,
              color: context.colors.textPrimary.withValues(alpha: 0.1),
            ),
            SizedBox(height: 16.h),
            Text(
              query.isEmpty ? 'No games to import' : 'No matches found',
              style: AppTypography.textMdMedium.copyWith(color: context.colors.textPrimary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final entry = filtered[index];
        final tourModel = chessGameToImportedGamesTourModel(entry.game);
        final md = entry.game.metadata;
        final eventName = _eventNameFromMetadata(md);

        return Padding(
          padding: EdgeInsets.only(bottom: 12.h),
          child: LibraryGameCard(
            game: tourModel,
            eventName: eventName,
            onTap: () => _openGame(entry.originalIndex),
          ),
        ).animate().fadeIn(duration: 150.ms);
      },
    );
  }

  String _eventNameFromMetadata(Map<String, dynamic> md) {
    final raw = md['Event']?.toString().trim() ?? '';
    if (raw.isNotEmpty) return raw;
    final site = md['Site']?.toString().trim() ?? '';
    if (site.isNotEmpty) return site;
    return 'Imported';
  }
}
