import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/library/widgets/import_pgn_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/library_game_card.dart';
import 'package:chessever2/services/pgn_file_intake_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/liquid_glass/glass_kit.dart';
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
    final games = widget.games.map(chessGameToImportedGamesTourModel).toList();

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

    return GlassFullScreenPage(
      backgroundColor: context.colors.background,
      contentPadding: const EdgeInsets.only(top: 118),
      topOverlayPadding: const EdgeInsets.only(top: 4),
      topOverlay: _buildTopArea(context),
      content: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth:
                ResponsiveHelper.isTablet
                    ? ResponsiveHelper.contentMaxWidth
                    : double.infinity,
          ),
          child: _buildList(filtered, query),
        ),
      ),
    );
  }

  Widget _buildTopArea(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth:
              ResponsiveHelper.isTablet
                  ? ResponsiveHelper.contentMaxWidth
                  : double.infinity,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [_buildHeader(context), _buildSearchBar()],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 8.w,
      tablet: 16.w,
    );
    final countLabel =
        widget.games.length == 1
            ? 'Import PGN · 1 game'
            : 'Import PGN · ${widget.games.length} games';
    return GlassIslandTopBar(
      horizontalPadding: horizontalPadding,
      topPadding: 0,
      height: 48,
      leading: GlassBackButton(
        onPressed: () {
          HapticFeedbackService.light();
          Navigator.of(context).pop();
        },
      ),
      title: GlassTitleChip(label: countLabel, maxWidth: 220.w),
      trailing: [
        Semantics(
          label: 'Save games to a folder',
          button: true,
          onTap: _handleSave,
          child: ExcludeSemantics(
            child: Tooltip(
              message: 'Save to folder',
              child: GlassIconButton(
                icon: Icon(
                  Icons.save_rounded,
                  color: context.colors.iconPrimary,
                ),
                onPressed: _handleSave,
                size: 48,
                iconSize: 20,
                useOwnLayer: true,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 2.h, 16.w, 8.h),
      child: Semantics(
        textField: true,
        label: 'Search imported games',
        child: GlassSearchBar(
          controller: _searchController,
          placeholder: 'Search games',
          useOwnLayer: true,
          height: 48,
          showsCancelButton: false,
          searchIconColor: context.colors.iconSecondary,
          clearIconColor: context.colors.iconSecondary,
          textStyle: AppTypography.textSmRegular.copyWith(
            color: context.colors.textPrimary,
          ),
          placeholderStyle: AppTypography.textSmRegular.copyWith(
            color: context.colors.textSecondary,
          ),
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
              query.isEmpty ? Icons.inbox_outlined : Icons.search_off_rounded,
              size: 64.sp,
              color: context.colors.textPrimary.withValues(alpha: 0.1),
            ),
            SizedBox(height: 16.h),
            Text(
              query.isEmpty ? 'No games to import' : 'No matches found',
              style: AppTypography.textMdMedium.copyWith(
                color: context.colors.textPrimary,
              ),
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

        final card = Padding(
          padding: EdgeInsets.only(bottom: 12.h),
          child: LibraryGameCard(
            game: tourModel,
            eventName: eventName,
            onTap: () => _openGame(entry.originalIndex),
          ),
        );
        if (GlassMotion.reduceMotion(context)) return card;
        return card.animate().fadeIn(duration: 150.ms);
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
