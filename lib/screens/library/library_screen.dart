import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/library/folder_contents_screen.dart';
import 'package:chessever2/screens/my_likes/my_likes_screen.dart';
import 'package:chessever2/screens/gamebase/gamebase_explorer_screen.dart';
import 'package:chessever2/screens/library/miniatures_screen.dart';
import 'package:chessever2/screens/library/pgn_import_preview_screen.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/library/twic_contents_screen.dart';
import 'package:chessever2/screens/library/widgets/add_to_library_sheet.dart';
import 'package:chessever2/screens/library/widgets/create_folder_dialog.dart';
import 'package:chessever2/screens/library/widgets/folder_card.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/services/pgn_file_intake_service.dart';
import 'package:chessever2/utils/library_utils.dart';
import 'package:chessever2/utils/logger/logger.dart';
import 'package:chessever2/utils/pgn_multi_parser.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:file_picker/file_picker.dart';
import 'package:chessever2/widgets/board_navigation_icon.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/simple_search_bar.dart';
import 'package:chessever2/widgets/search/search_motion.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();

    // Ensure default folders for new users
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(libraryRepositoryProvider).ensureDefaultFolders();
    });
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _navigateToBoard() {
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
      } catch (e2, st2) {
        talker.handle(e2, st2);
        if (!mounted) return;
        showAppSnack(
          context,
          userFacingError(e2, fallback: 'Could not open the file picker. Please try again.'),
          tone: AppSnackTone.danger,
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
      showAppSnack(context, 'Clipboard is empty. Copy a PGN first.');
      return;
    }

    final parsed = parsePgnsToChessGames(text);
    if (parsed.isEmpty) {
      if (!mounted) return;
      showAppSnack(
        context,
        'Clipboard does not contain a valid PGN',
        tone: AppSnackTone.danger,
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
          folders
              .where(
                (f) => !f.isSubscribed && f.id != kTwicBookId && f.isDatabase,
              )
              .length;
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
        nodeType: data.nodeType,
      );

      // Force refresh folders provider to ensure immediate UI update
      // (Supabase streams may have slight delay)
      ref.invalidate(libraryFoldersStreamProvider);
      ref.invalidate(subscribedBooksProvider);

      if (mounted) {
        HapticFeedback.mediumImpact();
        showAppSnack(
          context,
          '${data.nodeType == LibraryFolder.nodeTypeFolder ? 'Folder' : 'Database'} "${data.name}" created',
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
    } catch (e, st) {
      talker.handle(e, st);
      if (mounted) {
        HapticFeedback.lightImpact();
        showAppSnack(
          context,
          userFacingError(e, fallback: 'Could not create this item. Please try again.'),
          tone: AppSnackTone.danger,
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

    if (folder.id == kMiniaturesBookId) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const MiniaturesScreen()));
      return;
    }

    if (folder.isLikedGames) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const MyLikesScreen()));
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
    ref.listen<BottomNavBarReTapRequest>(bottomNavBarReTapRequestProvider, (
      previous,
      next,
    ) {
      if (next.item == BottomNavBarItem.library) {
        _scrollToTop();
      }
    });

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

  /// The home bar every main tab wears (see [HomeTopBar]): the avatar and
  /// the search field in the same place at the same size as on Events, with
  /// Library's own Board and Add tiles after the field. Focusing the field
  /// hands it the whole row; the avatar and the tiles squeeze out on the
  /// field's spring. The bar listens to the focus node itself, so the
  /// keyboard coming up never rebuilds this screen.
  Widget _buildTopBar() {
    // The sidebar (and the calendar inside it) must be reachable from every
    // main section. Library is mounted under the home Scaffold, so the avatar
    // opens the same drawer as the Events / For You headers. Outside that
    // shell there is no drawer to open, so the avatar is not offered at all
    // rather than shown as a dead control.
    final canOpenSidebar = Scaffold.maybeOf(context)?.hasDrawer ?? false;

    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: HomeTopBar(
        onOpenSidebar:
            canOpenSidebar
                ? () => Scaffold.maybeOf(context)?.openDrawer()
                : null,
        focusNode: _searchFocusNode,
        content: _buildSearchField(),
        // One canonical Board entry plus Add, on the avatar's centre line.
        trailing: [
          SizedBox(width: 8.w),
          KeyedSubtree(
            key: e2eKey(E2eIds.libraryBoardButton),
            child: _BoardButton(onTap: _navigateToBoard),
          ),
          SizedBox(width: 8.w),
          KeyedSubtree(
            key: e2eKey(E2eIds.libraryCreateFolderButton),
            child: _PlusButton(onTap: _handlePlusButton),
          ),
        ],
      ),
    );
  }

  /// The same field as the Events bar: its surface, its height, its type.
  /// Only the behaviour is Library's, filtering folders by name as you type.
  Widget _buildSearchField() {
    return TextFieldTapRegion(
      onTapOutside: (_) => _searchFocusNode.unfocus(),
      child: ListenableBuilder(
        listenable: _searchFocusNode,
        // Built once; focus only repaints the surface around it.
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: HomeTopBarMetrics.fieldHeight,
          ),
          child: SimpleSearchBar(
            textFieldKey: e2eKey(E2eIds.librarySearchField),
            hintText: 'Search',
            controller: _searchController,
            focusNode: _searchFocusNode,
            onOpenFilter: null,
            onChanged: _onSearchChanged,
            onCloseTap: _clearSearch,
          ),
        ),
        builder:
            (context, child) => ParkedMotionBuilder(
              value: _searchFocusNode.hasFocus ? 1.0 : 0.0,
              motion: SearchMotion.morph,
              child: child,
              builder:
                  (context, lift, child) => HomeSearchFieldSurface(
                    lift: lift,
                    child: RepaintBoundary(child: child),
                  ),
            ),
      ),
    );
  }

  void _onSearchChanged(String query) {
    final next = query.trim().toLowerCase();
    if (next == _searchQuery) return;
    setState(() => _searchQuery = next);
  }

  /// The field's clear button: empties the query and lets go of the field.
  /// `TextField.onChanged` does not fire for a programmatic clear, so the
  /// filter is reset here.
  void _clearSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    _onSearchChanged('');
  }

  Widget _buildContent() {
    final ownedFoldersAsync = ref.watch(libraryFoldersStreamProvider);
    final subscribedFoldersAsync = ref.watch(subscribedBooksProvider);
    final contentState = _resolveContentState(
      ownedFoldersAsync: ownedFoldersAsync,
      subscribedFoldersAsync: subscribedFoldersAsync,
    );

    return RefreshIndicator(
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
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: 4.h)),
          if (contentState.isLoading)
            _buildLoadingSliver()
          else if (contentState.hasError)
            _buildErrorSliver(userFacingError(contentState.error))
          else
            _buildFoldersSliver(contentState.folders),
          SliverToBoxAdapter(child: SizedBox(height: 24.h)),
          // The ghosted decoration lives BELOW the last card, in whatever
          // space the list leaves free. It used to be a Positioned.fill layer
          // behind the list, where the 8dp gaps between cards sliced its
          // headline into glyph fragments. It never extends the scroll: when
          // the free space is shorter than the decoration it is not drawn.
          if (contentState.hasFolders && _searchQuery.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              fillOverscroll: false,
              child: _FitOrHide(child: _LibraryBackgroundDecoration()),
            ),
        ],
      ),
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
    // Pin the permanent collections at the top: real per-user Liked Games
    // folder first (auto-created via ensureDefaultFolders), then TWIC, then
    // the rest in normal order.
    final likedIdx = folders.indexWhere((f) => f.isLikedGames);
    final rest =
        likedIdx == -1
            ? folders
            : (List<LibraryFolder>.from(folders)..removeAt(likedIdx));
    final allFolders = <LibraryFolder>[
      if (likedIdx != -1) folders[likedIdx],
      kTwicFolder,
      kMiniaturesFolder,
      ...rest,
    ];
    final filteredFolders = _filterFolders(allFolders);

    if (filteredFolders.isEmpty) {
      return _buildSearchEmptyState('No results match your search');
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
              isFeatured: filteredFolders[index].id == kTwicBookId ||
                  filteredFolders[index].id == kMiniaturesBookId ||
                  filteredFolders[index].isLikedGames,
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
              isFeatured: filteredFolders[index].id == kTwicBookId ||
                  filteredFolders[index].id == kMiniaturesBookId ||
                  filteredFolders[index].isLikedGames,
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
              color: context.textInk(0.4),
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
              color:
                  context.isLightTheme
                      ? context.colors.danger
                      : kRedColor.withValues(alpha: 0.7),
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

/// The one header action tile. Board and Add both render through this so the
/// two sit on the same surface, radius and square — a bare icon beside a
/// filled tile reads as an unfinished pair.
/// CSS: 36x36, bg #262626, radius 10px.
class _HeaderIconButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget icon;
  final String? tooltip;

  const _HeaderIconButton({
    required this.onTap,
    required this.icon,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36.h,
        height: 36.h,
        decoration: BoxDecoration(
          color: context.colors.surfaceRecessed,
          borderRadius: BorderRadius.circular(10.br),
        ),
        child: Center(child: icon),
      ),
    );

    final message = tooltip;
    if (message == null) return button;
    return Tooltip(message: message, child: button);
  }
}

/// Opens the shared Board workspace in its default Explorer view.
class _BoardButton extends StatelessWidget {
  final VoidCallback onTap;

  const _BoardButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _HeaderIconButton(
      onTap: onTap,
      tooltip: 'Open Board',
      icon: BoardNavigationIcon(size: 20.sp, semanticsLabel: 'Open Board'),
    );
  }
}

/// White plus icon on the shared header tile.
class _PlusButton extends StatelessWidget {
  final VoidCallback onTap;

  const _PlusButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _HeaderIconButton(
      onTap: onTap,
      icon: Icon(Icons.add, size: 20.sp, color: context.colors.textPrimary),
    );
  }
}

/// Lays [child] out at its natural height and centers it in the space it is
/// given, or draws nothing when that space is too short to hold it whole.
///
/// Reports zero intrinsic height, so a `SliverFillRemaining(hasScrollBody:
/// false)` parent sizes it to exactly the free space left under the list and
/// never grows the scroll extent to make room for it. The decoration is
/// either whole or absent; it is never cropped by a card or a viewport edge.
class _FitOrHide extends SingleChildRenderObjectWidget {
  const _FitOrHide({required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFitOrHide();
}

class _RenderFitOrHide extends RenderShiftedBox {
  _RenderFitOrHide() : super(null);

  bool _fits = false;

  @override
  double computeMinIntrinsicHeight(double width) => 0;

  @override
  double computeMaxIntrinsicHeight(double width) => 0;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    size = constraints.biggest;
    final child = this.child;
    if (child == null) {
      _fits = false;
      return;
    }
    child.layout(BoxConstraints(maxWidth: size.width), parentUsesSize: true);
    _fits = child.size.height <= size.height;
    (child.parentData! as BoxParentData).offset = Offset(
      (size.width - child.size.width) / 2,
      (size.height - child.size.height) / 2,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_fits) super.paint(context, offset);
  }

  // Purely decorative: never hit-testable, never read by a screen reader.
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      false;

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {}
}

/// Ghosted echo of the empty-state message, drawn in the free space under
/// the folder list (see [_FitOrHide]).
class _LibraryBackgroundDecoration extends StatelessWidget {
  const _LibraryBackgroundDecoration();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: 0.25,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildChessPatternVisual(context),
              SizedBox(height: 32.h),
              Text(
                'Millions of games',
                textAlign: TextAlign.center,
                style: AppTypography.displayXsMedium.copyWith(
                  color: context.colors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                'at your fingertips',
                textAlign: TextAlign.center,
                style: AppTypography.displayXsMedium.copyWith(
                  color: context.colors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              SizedBox(height: 20.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Text(
                  'Search any player, opening, or tournament. Save games to your personal folders for study.',
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
        color:
            isLight ? context.colors.divider : context.colors.surfaceRecessed,
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
                  isFeatured ? 'ChessEver Database' : 'Opening Preparation',
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
                    color: context.colors.textSecondary,
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
