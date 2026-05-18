import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/screens/library/folder_contents_screen.dart';
import 'package:chessever2/screens/gamebase/gamebase_explorer_screen.dart';
import 'package:chessever2/screens/library/pgn_import_preview_screen.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/board_editor/board_editor_screen.dart';
import 'package:chessever2/screens/library/twic_contents_screen.dart';
import 'package:chessever2/screens/library/widgets/add_to_library_sheet.dart';
import 'package:chessever2/screens/library/widgets/create_folder_dialog.dart';
import 'package:chessever2/screens/library/widgets/folder_card.dart';
import 'package:chessever2/screens/library/widgets/library_search_bar.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/services/pgn_file_intake_service.dart';
import 'package:chessever2/utils/library_utils.dart';
import 'package:chessever2/utils/pgn_multi_parser.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  bool _isSearchFocused = false;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onSearchFocusChange);

    // Ensure default folders for new users
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(libraryRepositoryProvider).ensureDefaultFolders();
    });
  }

  void _onSearchFocusChange() {
    setState(() {
      _isSearchFocused = _searchFocusNode.hasFocus;
    });
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_onSearchFocusChange);
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _navigateToEmptyBoard() {
    HapticFeedback.mediumImpact();
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const BoardEditorScreen()));
  }

  void _navigateToOpeningExplorer() {
    HapticFeedback.mediumImpact();
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => GamebaseExplorerScreen.scoped()));
  }

  List<LibraryFolder> _filterFolders(List<LibraryFolder> folders) {
    if (_searchQuery.isEmpty) return folders;
    return folders
        .where((folder) => folder.name.toLowerCase().contains(_searchQuery))
        .toList();
  }

  Future<void> _handlePlusButton() async {
    HapticFeedback.mediumImpact();
    final choice = await showAddToLibrarySheet(context);
    if (choice == null || !mounted) return;

    switch (choice) {
      case AddToLibraryChoice.createDatabase:
        await _handleCreateFolder();
      case AddToLibraryChoice.importPgn:
        await _handleImportPgnFromClipboard();
      case AddToLibraryChoice.pickPgnFile:
        await _handlePickPgnFile();
    }
  }

  Future<void> _handlePickPgnFile() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pgn'],
        withData: false,
      );
    } catch (e) {
      // Some platforms reject custom extensions — fall back to any-file picker.
      try {
        result = await FilePicker.platform.pickFiles(type: FileType.any);
      } catch (e2) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not open file picker: $e2',
              style:  TextStyle(color: context.colors.textPrimary),
            ),
            backgroundColor: kRedColor.withValues(alpha: 0.9),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    final path = result?.files.singleOrNull?.path;
    if (path == null || path.isEmpty) return;
    if (!mounted) return;
    await PgnFileIntakeService.instance.ingestPgnFileFromContext(
      context: context,
      path: path,
      sourceLabel: 'device file',
    );
  }

  Future<void> _handleImportPgnFromClipboard() async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboard?.text?.trim();
    if (text == null || text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Clipboard is empty. Copy a PGN first.',
            style: TextStyle(color: context.colors.textPrimary),
          ),
          backgroundColor: context.colors.surface.withValues(alpha: 0.95),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final parsed = parsePgnsToChessGames(text);
    if (parsed.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Clipboard does not contain a valid PGN',
            style: TextStyle(color: context.colors.textPrimary),
          ),
          backgroundColor: kRedColor.withValues(alpha: 0.9),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => PgnImportPreviewScreen(
              games: parsed.map((e) => e.chessGame).toList(),
              sourceLabel: 'clipboard',
            ),
      ),
    );
  }

  Future<void> _handleCreateFolder() async {
    final isPremium = ref.read(subscriptionProvider).isSubscribed;
    if (!isPremium) {
      final folders = await ref.read(libraryFoldersStreamProvider.future);
      final ownedBookCount =
          folders.where((f) => !f.isSubscribed && f.id != kTwicBookId).length;
      if (ownedBookCount >= kFreeBookCreationLimit) {
        if (!mounted) return;
        await showPremiumPaywallSheet(context: context);
        return;
      }
    }

    if (!mounted) return;
    final data = await showCreateFolderDialog(context);
    if (data == null || data.name.isEmpty) return;

    try {
      final repository = ref.read(libraryRepositoryProvider);
      final newFolder = await repository.createFolder(
        name: data.name,
        parentId: data.parentId,
      );

      // Force refresh folders provider to ensure immediate UI update
      // (Supabase streams may have slight delay)
      ref.invalidate(libraryFoldersStreamProvider);
      ref.invalidate(subscribedBooksProvider);

      if (mounted) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Database "${data.name}" created',
              style: TextStyle(color: context.colors.textPrimary),
            ),
            backgroundColor: context.colors.surface.withValues(alpha: 0.95),
            behavior: SnackBarBehavior.floating,
          ),
        );

        // Redirect to the book games list view after creation.
        final shouldFocusSearch = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => FolderContentsScreen(folder: newFolder),
          ),
        );
        if (shouldFocusSearch == true && mounted) {
          _searchFocusNode.requestFocus();
        }
      }
    } catch (e) {
      if (mounted) {
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to create database: $e',
              style: TextStyle(color: context.colors.textPrimary),
            ),
            backgroundColor: kRedColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _navigateToFolder(LibraryFolder folder) async {
    HapticFeedback.mediumImpact();

    if (folder.id == kTwicBookId) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const TwicContentsScreen()));
      return;
    }

    final shouldFocusSearch = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => FolderContentsScreen(folder: folder)),
    );
    if (shouldFocusSearch == true && mounted) {
      _searchFocusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenWrapper(
      child: KeyedSubtree(
        key: e2eKey(E2eIds.libraryRoot),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveHelper.contentMaxWidth,
            ),
            child: Column(
              children: [_buildTopBar(), Expanded(child: _buildContent())],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final topPadding = MediaQuery.of(context).viewPadding.top;

    // CSS: padding: 12px 16px
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, topPadding + 12.h, 16.w, 12.h),
      child: SingleMotionBuilder(
        motion: CupertinoMotion.snappy(),
        value: _isSearchFocused ? 1.0 : 0.0,
        builder: (context, value, child) {
          final clamped = value.clamp(0.0, 1.0);
          // CSS: explorer=32, board=32, plus=36, gaps=8+8, total ~116px + 8px gap
          final buttonsMaxWidth = (116.w + 8.w) * (1 - clamped);
          final gapWidth = (8.w * (1 - clamped)).clamp(0.0, 8.w);
          final opacity = (1 - clamped).clamp(0.0, 1.0);

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: _buildSearchField()),

              // Buttons group
              SizedBox(width: gapWidth),
              ClipRect(
                child: Opacity(
                  opacity: opacity,
                  child: SizedBox(
                    width: buttonsMaxWidth.clamp(0.0, double.infinity),
                    child:
                        buttonsMaxWidth > 1
                            ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Opening explorer: 32x32
                                KeyedSubtree(
                                  key: e2eKey(
                                    E2eIds.libraryOpeningExplorerButton,
                                  ),
                                  child: _OpeningExplorerButton(
                                    onTap: _navigateToOpeningExplorer,
                                  ),
                                ),
                                SizedBox(width: 8.w),
                                // CSS: 32x32, bg #1D1D1D, border 0.1px #444444, radius 4px
                                KeyedSubtree(
                                  key: e2eKey(E2eIds.libraryBoardEditorButton),
                                  child: _BoardSettingsButton(
                                    onTap: _navigateToEmptyBoard,
                                  ),
                                ),
                                SizedBox(width: 8.w),
                                // CSS: 36x36, bg #262626, radius 10px
                                KeyedSubtree(
                                  key: e2eKey(E2eIds.libraryCreateFolderButton),
                                  child: _PlusButton(
                                    onTap: _handlePlusButton,
                                  ),
                                ),
                              ],
                            )
                            : const SizedBox.shrink(),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchField() {
    return LibrarySearchBar(
      controller: _searchController,
      focusNode: _searchFocusNode,
      textFieldKey: e2eKey(E2eIds.librarySearchField),
      enableOverlay: false,
      showFilterIcon: false,
      hintText: 'Search',
      onChanged: (query) {
        setState(() => _searchQuery = query.trim().toLowerCase());
      },
    );
  }

  Widget _buildContent() {
    final ownedFoldersAsync = ref.watch(libraryFoldersStreamProvider);
    final subscribedFoldersAsync = ref.watch(subscribedBooksProvider);
    final contentState = _resolveContentState(
      ownedFoldersAsync: ownedFoldersAsync,
      subscribedFoldersAsync: subscribedFoldersAsync,
    );

    return Stack(
      children: [
        // Subtle background decoration - only when user has personal folders
        if (contentState.hasFolders)
          const Positioned.fill(child: _LibraryBackgroundDecoration()),
        // Main content
        RefreshIndicator(
          onRefresh: () async {
            HapticFeedbackService.medium();
            ref.invalidate(libraryFoldersStreamProvider);
            ref.invalidate(subscribedBooksProvider);
            ref.invalidate(folderAnalysisCountProvider);
            // Await the refetch so the spinner stays visible until data
            // actually arrives. Without the await, RefreshIndicator dismisses
            // immediately and the user thinks nothing happened.
            await Future.wait([
              ref.read(libraryFoldersStreamProvider.future),
              ref.read(subscribedBooksProvider.future),
            ]);
          },
          color: context.colors.textPrimary,
          backgroundColor: context.colors.surface,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: 4.h)),
              if (contentState.isLoading)
                _buildLoadingSliver()
              else if (contentState.hasError)
                _buildErrorSliver(contentState.error.toString())
              else
                _buildFoldersSliver(contentState.folders),
              SliverToBoxAdapter(child: SizedBox(height: 24.h)),
            ],
          ),
        ),
      ],
    );
  }

  _ResolvedLibraryContentState _resolveContentState({
    required AsyncValue<List<LibraryFolder>> ownedFoldersAsync,
    required AsyncValue<List<LibraryFolder>> subscribedFoldersAsync,
  }) {
    final ownedFolders =
        ownedFoldersAsync.valueOrNull ?? const <LibraryFolder>[];
    final subscribedFolders =
        subscribedFoldersAsync.valueOrNull ?? const <LibraryFolder>[];

    // Filter logic:
    // 1. If searching, show all matching folders regardless of hierarchy.
    // 2. If not searching, show only root-level folders (parentId == null).
    final combinedFolders =
        <LibraryFolder>[...ownedFolders, ...subscribedFolders].where((f) {
          if (_searchQuery.isNotEmpty) {
            return f.name.toLowerCase().contains(_searchQuery);
          }
          return f.parentId == null;
        }).toList();

    // Keep the page in loading until the initial async surface is truly settled.
    // This prevents brief provider errors from flashing the full-page error UI.
    final waitingForFirstStableResult =
        combinedFolders.isEmpty &&
        ((ownedFoldersAsync.isLoading && !ownedFoldersAsync.hasValue) ||
            (subscribedFoldersAsync.isLoading &&
                !subscribedFoldersAsync.hasValue));

    if (waitingForFirstStableResult) {
      return const _ResolvedLibraryContentState(
        folders: <LibraryFolder>[],
        isLoading: true,
      );
    }

    if (combinedFolders.isNotEmpty) {
      return _ResolvedLibraryContentState(folders: combinedFolders);
    }

    final error =
        ownedFoldersAsync.asError?.error ??
        subscribedFoldersAsync.asError?.error;

    return _ResolvedLibraryContentState(
      folders: const <LibraryFolder>[],
      error: error,
    );
  }

  Widget _buildFoldersSliver(List<LibraryFolder> folders) {
    // Prepend TWIC to the list — always on top
    final allFolders = [kTwicFolder, ...folders];
    final filteredFolders = _filterFolders(allFolders);

    if (filteredFolders.isEmpty) {
      return _buildSearchEmptyState('No databases match your search');
    }

    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );

    // Use grid layout for tablets
    if (ResponsiveHelper.isTablet) {
      final crossAxisCount = ResponsiveHelper.tabletGridColumns.clamp(2, 3);
      return SliverPadding(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: 8.h,
        ),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16.sp,
            mainAxisSpacing: 16.sp,
            childAspectRatio: ResponsiveHelper.isLandscape ? 2.5 : 2.0,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => FolderCard(
              folder: filteredFolders[index],
              isExpanded: true,
              isFeatured: filteredFolders[index].id == kTwicBookId,
              onTap: () => _navigateToFolder(filteredFolders[index]),
            ),
            childCount: filteredFolders.length,
          ),
        ),
      );
    }

    // Phone layout: CSS padding 16px, gap 8px
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => Padding(
            padding: EdgeInsets.only(bottom: 8.h),
            child: FolderCard(
              folder: filteredFolders[index],
              isExpanded: true,
              isFeatured: filteredFolders[index].id == kTwicBookId,
              onTap: () => _navigateToFolder(filteredFolders[index]),
            ),
          ),
          childCount: filteredFolders.length,
        ),
      ),
    );
  }

  Widget _buildSearchEmptyState(String message) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_outlined,
              size: 56.sp,
              color: context.colors.textPrimary.withValues(alpha: 0.4),
            ),
            SizedBox(height: 12.h),
            Text(
              message,
              style: AppTypography.textMdMedium.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingSliver() {
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );

    final loadingCards = List.generate(
      ResponsiveHelper.isTablet ? 6 : 5,
      (index) => _LibraryFolderLoadingCard(isFeatured: index == 0),
    );

    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: 8.h,
        ),
        child: SkeletonWidget(
          child:
              ResponsiveHelper.isTablet
                  ? GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: ResponsiveHelper.tabletGridColumns.clamp(
                        2,
                        3,
                      ),
                      crossAxisSpacing: 16.sp,
                      mainAxisSpacing: 16.sp,
                      childAspectRatio:
                          ResponsiveHelper.isLandscape ? 2.5 : 2.0,
                    ),
                    itemCount: loadingCards.length,
                    itemBuilder: (context, index) => loadingCards[index],
                  )
                  : Column(
                    children: [
                      for (final card in loadingCards) ...[
                        card,
                        SizedBox(height: 8.h),
                      ],
                    ],
                  ),
        ),
      ),
    );
  }

  Widget _buildErrorSliver(String error) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64.sp,
              color: kRedColor.withValues(alpha: 0.7),
            ),
            SizedBox(height: 16.h),
            Text(
              'Failed to load library',
              style: AppTypography.textLgMedium.copyWith(
                color: context.colors.textPrimary, // Zinc 50
              ),
            ),
            SizedBox(height: 8.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 40.w),
              child: Text(
                error,
                style: AppTypography.textSmRegular.copyWith(
                  color: context.colors.textSecondary, // Zinc 400
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// CSS: 32x32, bg #1D1D1D, border 0.1px #444444, radius 4px
/// Opening explorer button
class _OpeningExplorerButton extends StatelessWidget {
  final VoidCallback onTap;

  const _OpeningExplorerButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32.h,
        height: 32.h,
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(4.br),
          border: Border.all(color: context.colors.divider, width: 0.1),
        ),
        child: Center(
          child: Icon(
            Icons.explore_outlined,
            size: 20.sp,
            color: context.colors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// CSS: 32x32, bg #1D1D1D, border 0.1px #444444, radius 4px
/// Contains a 2x2 mini chessboard icon (20x20)
class _BoardSettingsButton extends StatelessWidget {
  final VoidCallback onTap;

  const _BoardSettingsButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32.h,
        height: 32.h,
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(4.br),
          border: Border.all(color: context.colors.divider, width: 0.1),
        ),
        child: Center(
          child: SvgWidget(
            SvgAsset.boardSettings,
            width: 20.sp,
            height: 20.sp,
            // Multi-colour (black + white squares) — keep baked colours so
            // the icon doesn't collapse into a single solid blob.
            preserveOriginalColors: true,
          ),
        ),
      ),
    );
  }
}

/// CSS: 36x36, bg #262626, radius 10px, white plus icon
class _PlusButton extends StatelessWidget {
  final VoidCallback onTap;

  const _PlusButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36.h,
        height: 36.h,
        decoration: BoxDecoration(
          color: context.colors.surfaceRecessed,
          borderRadius: BorderRadius.circular(10.br),
        ),
        child: Center(
          child: Icon(Icons.add, size: 20.sp, color: context.colors.textPrimary),
        ),
      ),
    );
  }
}

/// Subtle background decoration shown behind folder cards
/// Displays a ghosted version of the empty state messaging
class _LibraryBackgroundDecoration extends StatelessWidget {
  const _LibraryBackgroundDecoration();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: 0.25,
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Decorative chess pattern - larger for background presence
                _buildChessPatternVisual(context),
                SizedBox(height: 32.h),

                // Main headline
                Text(
                  'Millions of games',
                  style: AppTypography.displayXsMedium.copyWith(
                    color: context.colors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  'at your fingertips',
                  style: AppTypography.displayXsMedium.copyWith(
                    color: context.colors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),

                SizedBox(height: 20.h),

                // Description
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.w),
                  child: Text(
                    'Search any player, opening, or tournament. Save games to your personal databases for study.',
                    style: AppTypography.textSmRegular.copyWith(
                      color: context.colors.textPrimary,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChessPatternVisual(BuildContext context) {
    const gridSize = 4;
    final squareSize = 28.w;
    final totalSize = squareSize * gridSize;

    return SizedBox(
      width: totalSize,
      height: totalSize,
      child: Stack(
        children: [
          for (int row = 0; row < gridSize; row++)
            for (int col = 0; col < gridSize; col++)
              Positioned(
                left: col * squareSize,
                top: row * squareSize,
                child: _buildSquare(
                  context: context,
                  row: row,
                  col: col,
                  size: squareSize,
                  gridSize: gridSize,
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildSquare({
    required BuildContext context,
    required int row,
    required int col,
    required double size,
    required int gridSize,
  }) {
    final isLight = (row + col) % 2 == 0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isLight ? context.colors.divider : context.colors.surfaceRecessed,
        borderRadius: _getCornerRadius(row, col, gridSize, 6.br),
      ),
    );
  }

  BorderRadius _getCornerRadius(int row, int col, int gridSize, double radius) {
    final isTopLeft = row == 0 && col == 0;
    final isTopRight = row == 0 && col == gridSize - 1;
    final isBottomLeft = row == gridSize - 1 && col == 0;
    final isBottomRight = row == gridSize - 1 && col == gridSize - 1;

    return BorderRadius.only(
      topLeft: isTopLeft ? Radius.circular(radius) : Radius.zero,
      topRight: isTopRight ? Radius.circular(radius) : Radius.zero,
      bottomLeft: isBottomLeft ? Radius.circular(radius) : Radius.zero,
      bottomRight: isBottomRight ? Radius.circular(radius) : Radius.zero,
    );
  }
}

class _ResolvedLibraryContentState {
  const _ResolvedLibraryContentState({
    required this.folders,
    this.isLoading = false,
    this.error,
  });

  final List<LibraryFolder> folders;
  final bool isLoading;
  final Object? error;

  bool get hasFolders => folders.isNotEmpty;
  bool get hasError => error != null;
}

class _LibraryFolderLoadingCard extends StatelessWidget {
  const _LibraryFolderLoadingCard({required this.isFeatured});

  final bool isFeatured;

  @override
  Widget build(BuildContext context) {
    final iconSize = isFeatured ? 64.0.h : 36.0.h;
    final iconRadius = isFeatured ? 17.78.br : 10.0.br;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.h),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12.br),
      ),
      child: Row(
        children: [
          Container(
            width: iconSize,
            height: iconSize,
            decoration: BoxDecoration(
              color: context.colors.surfaceRecessed,
              borderRadius: BorderRadius.circular(iconRadius),
            ),
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isFeatured ? 'TWIC Database' : 'Opening Preparation',
                  style: AppTypography.textSmMedium.copyWith(
                    color: context.colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4.h),
                Text(
                  isFeatured ? 'Master games' : '124 saved games',
                  style: AppTypography.textXsRegular.copyWith(
                    color: const Color(0xFFA1A1A1),
                    height: 16 / 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

