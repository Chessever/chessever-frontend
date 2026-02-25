import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/library/utils/load_saved_analysis.dart';
import 'package:chessever2/screens/library/widgets/book_saved_game_card.dart';
import 'package:chessever2/screens/library/widgets/swipe_action_card.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Book (folder) screen.
///
/// Search only filters within the book.
class FolderContentsScreen extends ConsumerStatefulWidget {
  const FolderContentsScreen({super.key, required this.folder});

  final LibraryFolder folder;

  @override
  ConsumerState<FolderContentsScreen> createState() =>
      _FolderContentsScreenState();
}

class _FolderContentsScreenState extends ConsumerState<FolderContentsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final Set<String> _removingIds = {};

  bool get _isSubscribed => widget.folder.isSubscribed;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _clearSearch() {
    HapticFeedback.lightImpact();
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() {});
  }

  Future<void> _removeFromBookSimple(SavedAnalysis analysis) async {
    if (_removingIds.contains(analysis.id)) return;

    HapticFeedbackService.medium();
    _removingIds.add(analysis.id);

    final repository = ref.read(libraryRepositoryProvider);
    try {
      await repository.moveAnalysisToFolder(analysis.id, null);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Removed from "${widget.folder.name}"',
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
          ),
          backgroundColor: kBlack2Color.withValues(alpha: 0.95),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Undo',
            textColor: kPrimaryColor,
            onPressed: () async {
              try {
                await repository.moveAnalysisToFolder(
                  analysis.id,
                  widget.folder.id,
                );
              } catch (_) {
                // Best-effort undo; show nothing if it fails.
              }
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      HapticFeedbackService.light();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to remove: $e',
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
          ),
          backgroundColor: kRedColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      _removingIds.remove(analysis.id);
    }
  }

  Future<void> _unsubscribeFromBook() async {
    try {
      final repo = ref.read(libraryRepositoryProvider);
      await repo.unsubscribeFromBook(widget.folder.id);
      ref.invalidate(subscribedBooksProvider);
      ref.invalidate(combinedLibraryFoldersProvider);

      if (!mounted) return;
      HapticFeedbackService.success();
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      HapticFeedbackService.error();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to unsubscribe: $e',
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
          ),
          backgroundColor: kRedColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Open a shared game in read-only analysis mode (no analysisId → no save-back).
  void _openSharedGame(SavedAnalysis analysis) {
    final md = analysis.chessGame.metadata;
    final whiteName = md['White'] as String? ?? 'White';
    final blackName = md['Black'] as String? ?? 'Black';
    final result = md['Result'] as String? ?? '*';
    final whiteTitle = (md['WhiteTitle'] ?? '').toString().trim();
    final blackTitle = (md['BlackTitle'] ?? '').toString().trim();

    final game = GamesTourModel(
      gameId: 'shared_${analysis.id}',
      whitePlayer: PlayerCard(
        name: whiteName,
        federation: '',
        title: whiteTitle,
        rating: 0,
        countryCode: '',
        team: null,
      ),
      blackPlayer: PlayerCard(
        name: blackName,
        federation: '',
        title: blackTitle,
        rating: 0,
        countryCode: '',
        team: null,
      ),
      whiteTimeDisplay: '--:--',
      blackTimeDisplay: '--:--',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: GameStatus.fromString(result),
      roundId: 'shared',
      tourId: 'library',
      pgn: '',
    );

    // Create SavedAnalysisData WITHOUT analysisId so board won't save back
    final savedData = SavedAnalysisData(
      analysisId: null,
      chessGame: analysis.chessGame,
      variationComments: analysis.variationComments,
      movePointer: null,
      isBoardFlipped: false,
      lastViewedPosition: analysis.lastViewedPosition,
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChessBoardScreenNew(
          currentIndex: 0,
          games: [game],
          savedAnalysisData: savedData,
          showGamebaseButton: false,
          disableGamebaseOverlayByDefault: true,
          showClock: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final analysesAsync = _isSubscribed
        ? ref.watch(subscribedFolderAnalysesProvider(widget.folder.id))
        : ref.watch(_folderAnalysesProvider(widget.folder.id));
    final query = _searchController.text.trim().toLowerCase();

    return Scaffold(
      backgroundColor: kBackgroundColor,
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
                Expanded(child: _buildSavedGames(analysesAsync, query)),
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
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [kBlackColor, kBackgroundColor],
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
                color: kWhiteColor,
                size: 20.ic,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 56.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.folder.name,
                  style: AppTypography.textLgBold.copyWith(color: kWhiteColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                if (_isSubscribed && widget.folder.ownerDisplayName != null)
                  Text(
                    'by ${widget.folder.ownerDisplayName}',
                    style: AppTypography.textXsRegular.copyWith(
                      color: kWhiteColor.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
          // Unsubscribe button for subscribed books
          if (_isSubscribed)
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: _unsubscribeFromBook,
                icon: Icon(
                  Icons.link_off_rounded,
                  color: kWhiteColor.withValues(alpha: 0.7),
                  size: 20.ic,
                ),
                tooltip: 'Unsubscribe',
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        0,
        horizontalPadding,
        8.h,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF09090B), // Zinc 950
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(color: const Color(0xFF27272A)), // Zinc 800
        ),
        child: Row(
          children: [
            SizedBox(width: 12.w),
            Icon(
              Icons.search,
              size: 20.sp,
              color: const Color(0xFFA1A1AA), // Zinc 400
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                style: AppTypography.textSmRegular.copyWith(
                  color: const Color(0xFFFAFAFA), // Zinc 50
                ),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search',
                  hintStyle: AppTypography.textSmRegular.copyWith(
                    color: const Color(0xFFA1A1AA), // Zinc 400
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14.h),
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

  Widget _buildSavedGames(
    AsyncValue<List<SavedAnalysis>> analysesAsync,
    String query,
  ) {
    final providerToInvalidate = _isSubscribed
        ? subscribedFolderAnalysesProvider(widget.folder.id)
        : _folderAnalysesProvider(widget.folder.id);

    return RefreshIndicator(
      onRefresh: () async {
        HapticFeedbackService.medium();
        ref.invalidate(providerToInvalidate);
      },
      color: kWhiteColor,
      backgroundColor: kBlack2Color,
      child: analysesAsync.when(
        data: (analyses) {
          final filtered =
              analyses.where((analysis) {
                if (query.isEmpty) return true;
                final md = analysis.chessGame.metadata;
                final title = analysis.title.toLowerCase();
                final white = (md['White'] ?? '').toString().toLowerCase();
                final black = (md['Black'] ?? '').toString().toLowerCase();
                final event = (md['Event'] ?? '').toString().toLowerCase();
                return title.contains(query) ||
                    white.contains(query) ||
                    black.contains(query) ||
                    event.contains(query);
              }).toList();

          if (analyses.isEmpty) return _buildEmptySavedState();
          if (filtered.isEmpty) return _buildEmptySearchState();

          return ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final analysis = filtered[index];

              // Subscribed: read-only cards (no swipe-to-remove)
              if (_isSubscribed) {
                return Padding(
                  padding: EdgeInsets.only(bottom: 12.h),
                  child: BookSavedGameCard(
                    analysis: analysis,
                    onTap: () async {
                      final allowed =
                          await requirePremiumGuard(context, ref);
                      if (!allowed || !mounted) return;
                      _openSharedGame(analysis);
                    },
                  ).animate()
                      .fadeIn(
                        duration: 200.ms,
                        delay: Duration(milliseconds: (index % 10) * 30),
                      )
                      .slideY(
                        begin: 0.05,
                        end: 0,
                        duration: 200.ms,
                        curve: Curves.easeOut,
                      ),
                );
              }

              // Owned: swipeable cards
              return Padding(
                padding: EdgeInsets.only(bottom: 12.h),
                child: SwipeActionCard(
                  dismissKey: ValueKey(
                    'book_${widget.folder.id}_${analysis.id}',
                  ),
                  icon: Icons.delete_outline_rounded,
                  label: 'Remove',
                  backgroundColor: kRedColor,
                  behavior: SwipeActionBehavior.dismiss,
                  onAction: () => _removeFromBookSimple(analysis),
                  // Show swipe hint only for the first card
                  showSwipeHint: index == 0,
                  swipeHintKey: 'book_remove',
                  child: BookSavedGameCard(
                    analysis: analysis,
                    onTap: () async {
                      final allowed =
                          await requirePremiumGuard(context, ref);
                      if (!allowed || !mounted) return;
                      loadSavedAnalysis(context, analysis);
                    },
                  ).animate()
                      .fadeIn(
                        duration: 200.ms,
                        delay: Duration(milliseconds: (index % 10) * 30),
                      )
                      .slideY(
                        begin: 0.05,
                        end: 0,
                        duration: 200.ms,
                        curve: Curves.easeOut,
                      ),
                ),
              );
            },
          );
        },
        loading:
            () => const Center(
              child: CircularProgressIndicator(color: kWhiteColor),
            ),
        error: (error, _) => _buildErrorState(error.toString()),
      ),
    );
  }

  Widget _buildEmptySavedState() {
    if (_isSubscribed) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(32.sp),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.menu_book_outlined,
                size: 64.sp,
                color: kWhiteColor.withValues(alpha: 0.35),
              ),
              SizedBox(height: 12.h),
              Text(
                'No games yet',
                style: AppTypography.textMdMedium.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.85),
                ),
              ),
              SizedBox(height: 6.h),
              Text(
                'The owner hasn\'t added any games to this book yet.',
                style: AppTypography.textSmRegular.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.55),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.sp),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 64.sp,
              color: kWhiteColor.withValues(alpha: 0.35),
            ),
            SizedBox(height: 12.h),
            Text(
              'No games in this book',
              style: AppTypography.textMdMedium.copyWith(
                color: kWhiteColor.withValues(alpha: 0.85),
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              'Add games from search to build your library.',
              style: AppTypography.textSmRegular.copyWith(
                color: kWhiteColor.withValues(alpha: 0.55),
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 24.h),
            GestureDetector(
              onTap: () {
                HapticFeedbackService.light();
                Navigator.of(context).pop(true); // Signal to focus search
              },
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
                decoration: BoxDecoration(
                  color: kWhiteColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10.br),
                  border: Border.all(color: kWhiteColor.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 18.sp,
                      color: kWhiteColor.withValues(alpha: 0.85),
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      'Search games',
                      style: AppTypography.textSmMedium.copyWith(
                        color: kWhiteColor.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySearchState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.sp),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_outlined,
              size: 56.sp,
              color: kWhiteColor.withValues(alpha: 0.4),
            ),
            SizedBox(height: 12.h),
            Text(
              'No results',
              style: AppTypography.textMdMedium.copyWith(
                color: kWhiteColor.withValues(alpha: 0.85),
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              'Try a different search.',
              style: AppTypography.textSmRegular.copyWith(
                color: kWhiteColor.withValues(alpha: 0.55),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.sp),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 56.sp,
              color: kRedColor.withValues(alpha: 0.85),
            ),
            SizedBox(height: 12.h),
            Text(
              'Something went wrong',
              style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
            ),
            SizedBox(height: 6.h),
            Text(
              error,
              style: AppTypography.textSmRegular.copyWith(
                color: kWhiteColor.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

final _folderAnalysesProvider = StreamProvider.family
    .autoDispose<List<SavedAnalysis>, String>((ref, folderId) {
      return ref
          .watch(libraryRepositoryProvider)
          .subscribeAnalyses(folderId: folderId);
    });
