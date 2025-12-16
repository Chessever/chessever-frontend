import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/library/widgets/book_saved_game_card.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  @override
  Widget build(BuildContext context) {
    final analysesAsync = ref.watch(_folderAnalysesProvider(widget.folder.id));
    final query = _searchController.text.trim().toLowerCase();

    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: ScreenWrapper(
        child: Column(
          children: [
            _buildTopArea(context),
            Expanded(child: _buildSavedGames(analysesAsync, query)),
          ],
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
      child: Column(
        children: [_buildHeader(context), _buildSearchBar()],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 0, 8.w, 8.h),
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
            child: Text(
              widget.folder.name,
              style: AppTypography.textLgBold.copyWith(color: kWhiteColor),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 8.h),
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
    return RefreshIndicator(
      onRefresh: () async {
        HapticFeedbackService.medium();
        ref.invalidate(_folderAnalysesProvider(widget.folder.id));
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
                final white =
                    (md['White'] ?? '').toString().toLowerCase();
                final black =
                    (md['Black'] ?? '').toString().toLowerCase();
                final event =
                    (md['Event'] ?? '').toString().toLowerCase();
                return title.contains(query) ||
                    white.contains(query) ||
                    black.contains(query) ||
                    event.contains(query);
              }).toList();

          if (analyses.isEmpty) return _buildEmptySavedState();
          if (filtered.isEmpty) return _buildEmptySearchState();

          return ListView.separated(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => SizedBox(height: 12.h),
            itemBuilder: (context, index) {
              return BookSavedGameCard(analysis: filtered[index]);
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
