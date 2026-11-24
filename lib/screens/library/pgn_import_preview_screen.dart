import 'package:chessever2/widgets/paywall/pgn_import_access.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/library/widgets/import_pgn_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/library_game_card.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/services/pgn_file_intake_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/dismiss_keyboard.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/widgets/search/search_cancel_button.dart';
import 'package:chessever2/widgets/search/search_clear_button.dart';
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

bool _pgnImportGameMatches(ChessGame game, String query) {
  if (query.isEmpty) return true;
  final metadata = game.metadata;
  final fields = [
    metadata['White']?.toString() ?? '',
    metadata['Black']?.toString() ?? '',
    metadata['Event']?.toString() ?? '',
    metadata['Site']?.toString() ?? '',
    metadata['Opening']?.toString() ?? '',
    metadata['ECO']?.toString() ?? '',
  ];
  return fields.any((field) => field.toLowerCase().contains(query));
}

@visibleForTesting
List<ChessGame> filterPgnImportGames(List<ChessGame> games, String rawQuery) {
  final query = rawQuery.trim().toLowerCase();
  return games
      .where((game) => _pgnImportGameMatches(game, query))
      .toList(growable: false);
}

@visibleForTesting
({List<GamesTourModel> games, int selectedIndex})
buildPgnImportBoardNavigation({
  required List<ChessGame> visibleGames,
  required int selectedIndex,
}) {
  return (
    games: visibleGames
        .map(chessGameToImportedGamesTourModel)
        .toList(growable: false),
    selectedIndex: selectedIndex,
  );
}

class _PgnImportPreviewScreenState
    extends ConsumerState<PgnImportPreviewScreen> {
  late final TextEditingController _searchController;
  final FocusNode _searchFocusNode = FocusNode();

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
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// The clear button: the words go, the cursor stays.
  void _clearSearch() {
    HapticFeedbackService.light();
    _searchController.clear();
    if (!_searchFocusNode.hasFocus) _searchFocusNode.requestFocus();
  }

  /// Cancel: the words go and the keyboard with them.
  void _cancelSearch() {
    _searchController.clear();
    dismissSoftwareKeyboard(focusNode: _searchFocusNode);
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

  Future<void> _openGame(List<ChessGame> visibleGames, int index) async {
    if (!await ensurePgnImportAccess(context) || !mounted) return;
    HapticFeedbackService.cardTap();
    // Build a minimal GamesTourModel per game, embedding the full PGN so
    // ChessBoardScreenNew can render it without a Supabase lookup.
    final navigation = buildPgnImportBoardNavigation(
      visibleGames: visibleGames,
      selectedIndex: index,
    );

    ref.read(chessboardViewFromProviderNew.notifier).state =
        ChessboardView.tour;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => ChessBoardScreenNew(
              currentIndex: navigation.selectedIndex,
              games: navigation.games,
              viewSource: ChessboardView.tour,
              showGamebaseButton: false,
              disableGamebaseOverlayByDefault: true,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = filterPgnImportGames(widget.games, query);

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
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            context.colors.background,
            context.colors.background.withValues(alpha: 0),
          ],
        ),
      ),
      child: Column(children: [_buildHeader(context), _buildSearchBar()]),
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
              tooltip: 'Save to folder',
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
                    color: context.textInk(0.5),
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

  /// The search row, in X's order: the field (the clear button in it while
  /// it holds words), then Cancel while the field has the cursor or holds
  /// words.
  Widget _buildSearchBar() {
    final height = 38.h;
    final inset = 12.w;
    final magnifier = 18.sp;
    final field = Container(
      height: height,
      decoration: BoxDecoration(
        color: context.colors.textPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10.br),
      ),
      child: Row(
        children: [
          SizedBox(width: inset),
          Icon(
            Icons.search_rounded,
            size: magnifier,
            color: context.isLightTheme
                ? context.colors.iconSecondary
                : const Color(0xFFA1A1AA),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Search games...',
                // The field is ink-tinted; tertiary drops under AA there.
                hintStyle: AppTypography.textSmRegular.copyWith(
                  color: context.isLightTheme
                      ? context.colors.textSecondary
                      : const Color(0xFFA1A1AA),
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
            ),
          ),
          // Part of the field: pressing it keeps the keyboard up. Tinted as
          // the magnifier is, so the two marks frame the words alike.
          SearchClearButton(
            controller: _searchController,
            focusNode: _searchFocusNode,
            color: context.isLightTheme
                ? context.colors.iconSecondary
                : const Color(0xFFA1A1AA),
            onTap: _clearSearch,
          ),
          // The clear glyph's centre as far in from the end as the
          // magnifier's is from the start, so the two frame the words.
          SizedBox(
            width:
                inset +
                magnifier / 2 -
                SearchClearButton.endInset -
                SearchClearButton.glyph / 2,
          ),
        ],
      ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      // As tall as the field: Cancel's taller tap never moves the list.
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            Expanded(child: field),
            SearchCancelButton(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onCancel: _cancelSearch,
              cancelKey: const ValueKey('pgn_import_search_cancel'),
              // The word at the field's own size, as X sets it.
              textStyle: AppTypography.textSmRegular,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<ChessGame> filtered, String query) {
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
        final game = filtered[index];
        final tourModel = chessGameToImportedGamesTourModel(game);
        final md = game.metadata;
        final eventName = _eventNameFromMetadata(md);

        return Padding(
          padding: EdgeInsets.only(bottom: 12.h),
          child: LibraryGameCard(
            game: tourModel,
            eventName: eventName,
            onTap: () => _openGame(filtered, index),
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
