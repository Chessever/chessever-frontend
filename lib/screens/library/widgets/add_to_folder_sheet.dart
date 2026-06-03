import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/widgets/smooth_sheet_config.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/library/widgets/create_folder_dialog.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/library_utils.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/save_to_library_guard.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

/// Shows the Add to Folder sheet with smooth spring animations.
Future<void> showAddToFolderSheet({
  required BuildContext context,
  required GamesTourModel game,
}) async {
  final allowed = await canSaveMoreGames(context);
  if (!allowed) return;
  if (!context.mounted) return;

  final route = ChessSheetRoutes.commentEditor(
    context: context,
    builder: (_) => _AddToFolderSheetShell(game: game),
  );
  await Navigator.of(context).push(route);
}

/// Outer shell widget - sets up PagedSheet with Navigator
class _AddToFolderSheetShell extends ConsumerWidget {
  const _AddToFolderSheetShell({required this.game});

  final GamesTourModel game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigator = Navigator(
      onGenerateInitialRoutes:
          (_, __) => [
            SpringPagedSheetRoute(
              scrollConfiguration: const SheetScrollConfiguration(),
              dragConfiguration: ChessSheetConfigs.commentEditor,
              initialOffset: const SheetOffset.proportionalToViewport(0.65),
              snapGrid: SheetSnapGrid(
                snaps: const [
                  SheetOffset.proportionalToViewport(0.65),
                  SheetOffset.proportionalToViewport(0.85),
                ],
                minFlingSpeed: 600.0,
              ),
              builder: (context) => _AddToFolderPage(game: game),
            ),
          ],
    );

    return SheetKeyboardDismissible(
      dismissBehavior: const DragDownSheetKeyboardDismissBehavior(
        isContentScrollAware: true,
      ),
      child: PagedSheet(
        decoration: ChessSheetDecoration.dark(
          context,
          alpha: 0.97,
          borderRadius: 28.sp,
        ),
        shrinkChildToAvoidDynamicOverlap: true,
        navigator: navigator,
      ),
    );
  }
}

/// Inner page widget - contains all the stateful content
class _AddToFolderPage extends ConsumerStatefulWidget {
  const _AddToFolderPage({required this.game});

  final GamesTourModel game;

  @override
  ConsumerState<_AddToFolderPage> createState() => _AddToFolderPageState();
}

class _AddToFolderPageState extends ConsumerState<_AddToFolderPage> {
  final Set<String> _selectedFolderIds = <String>{};
  final Set<String> _expandedFolderIds = <String>{};
  bool _isSaving = false;

  Future<ChessGame> _resolveChessGame() async {
    final gameRepository = ref.read(gameRepositoryProvider);
    final gamebaseRepository = ref.read(gamebaseRepositoryProvider);

    String? pgn = widget.game.pgn;
    final hasMoves = pgn != null && pgnHasMoves(pgn);

    if (!hasMoves) {
      try {
        final supabasePgn = await gameRepository.getGamePgn(widget.game.gameId);
        if (supabasePgn != null && pgnHasMoves(supabasePgn)) {
          pgn = supabasePgn;
        }
      } catch (_) {}

      if (pgn == null || !pgnHasMoves(pgn)) {
        final fullGame = await gamebaseRepository.getGameWithPgn(
          widget.game.gameId,
        );
        if (fullGame != null) {
          if (fullGame.pgn != null && pgnHasMoves(fullGame.pgn!)) {
            pgn = fullGame.pgn;
          } else if (fullGame.data != null) {
            final builtPgn = buildPgnFromGamebaseData(fullGame.data);
            if (builtPgn != null && pgnHasMoves(builtPgn)) {
              pgn = builtPgn;
            }
          }
        }
      }
    }

    if (pgn == null || pgn.trim().isEmpty) {
      throw Exception('Game PGN not found');
    }

    final chessGame = ChessGame.fromPgn(widget.game.gameId, pgn);
    final meta = Map<String, dynamic>.from(chessGame.metadata);

    meta['White'] = widget.game.whitePlayer.name;
    meta['Black'] = widget.game.blackPlayer.name;

    final whiteFed =
        widget.game.whitePlayer.countryCode.isNotEmpty
            ? widget.game.whitePlayer.countryCode
            : widget.game.whitePlayer.federation;
    final blackFed =
        widget.game.blackPlayer.countryCode.isNotEmpty
            ? widget.game.blackPlayer.countryCode
            : widget.game.blackPlayer.federation;
    if (whiteFed.isNotEmpty) meta['WhiteFed'] = whiteFed;
    if (blackFed.isNotEmpty) meta['BlackFed'] = blackFed;

    if (widget.game.whitePlayer.title.isNotEmpty) {
      meta['WhiteTitle'] = widget.game.whitePlayer.title;
    }
    if (widget.game.blackPlayer.title.isNotEmpty) {
      meta['BlackTitle'] = widget.game.blackPlayer.title;
    }
    if (widget.game.whitePlayer.rating > 0) {
      meta['WhiteElo'] = widget.game.whitePlayer.rating.toString();
    }
    if (widget.game.blackPlayer.rating > 0) {
      meta['BlackElo'] = widget.game.blackPlayer.rating.toString();
    }

    final resolvedEventName = _resolveEventName(
      metadataEvent: meta['Event']?.toString(),
      tourSlug: widget.game.tourSlug,
      tourId: widget.game.tourId,
    );
    if (resolvedEventName != null) {
      meta['Event'] = resolvedEventName;
    }

    return chessGame.copyWith(metadata: meta);
  }

  void _toggleFolderSelection(LibraryFolder folder) {
    if (_isSaving) return;
    HapticFeedbackService.light();
    setState(() {
      if (_selectedFolderIds.contains(folder.id)) {
        _selectedFolderIds.remove(folder.id);
      } else {
        _selectedFolderIds.add(folder.id);
      }
    });
  }

  void _toggleFolderExpansion(String folderId) {
    HapticFeedbackService.light();
    setState(() {
      if (_expandedFolderIds.contains(folderId)) {
        _expandedFolderIds.remove(folderId);
      } else {
        _expandedFolderIds.add(folderId);
      }
    });
  }

  Future<void> _handleCreateNewBook() async {
    if (_isSaving) return;

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
    HapticFeedbackService.light();
    final data = await showCreateFolderDialog(context);
    if (data == null || data.name.trim().isEmpty) return;

    try {
      final created = await ref
          .read(libraryRepositoryProvider)
          .createFolder(
            name: data.name,
            parentId: data.parentId,
            nodeType: data.nodeType,
          );
      ref.invalidate(libraryFoldersStreamProvider);

      if (!mounted) return;
      if (created.isDatabase) {
        setState(() => _selectedFolderIds.add(created.id));
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${data.nodeType == LibraryFolder.nodeTypeFolder ? 'Database' : 'Folder'} "${data.name}" created',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          backgroundColor: context.colors.surface.withValues(alpha: 0.95),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to create item: $e',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          backgroundColor: kRedColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String? _resolveEventName({
    required String? metadataEvent,
    required String? tourSlug,
    required String? tourId,
  }) {
    final fromMetadata = metadataEvent?.trim() ?? '';
    if (_isReadableEventName(fromMetadata)) return fromMetadata;
    final fromSlug = tourSlug?.trim() ?? '';
    if (_isReadableEventName(fromSlug)) return _humanizeSlug(fromSlug);
    return null;
  }

  bool _isReadableEventName(String value) {
    if (value.isEmpty) return false;
    final lower = value.toLowerCase();
    if (lower == 'library' ||
        lower == 'gamebase' ||
        lower == 'opening_explorer') {
      return false;
    }
    return true;
  }

  String _humanizeSlug(String value) {
    if (!value.contains('-') && !value.contains('_')) return value;
    final words =
        value.split(RegExp(r'[-_]+')).where((s) => s.isNotEmpty).toList();
    if (words.isEmpty) return value;
    return words
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  Future<void> _handleAddToSelected(List<LibraryFolder> selected) async {
    if (_isSaving) return;
    if (selected.isEmpty) {
      HapticFeedbackService.light();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Select at least one folder',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          backgroundColor: context.colors.surface.withValues(alpha: 0.95),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Pre-flight only counted 1 row; one game × N folders = N rows.
    final allowed = await canSaveMoreGames(
      context,
      gamesToAdd: selected.length,
    );
    if (!allowed || !mounted) return;

    setState(() => _isSaving = true);
    try {
      final chessGame = await _resolveChessGame();
      final userId =
          ref.read(libraryRepositoryProvider).supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final repository = ref.read(libraryRepositoryProvider);
      final now = DateTime.now();
      var successCount = 0;

      for (final folder in selected) {
        final analysis = SavedAnalysis(
          id: '',
          userId: userId,
          folderId: folder.id,
          title:
              '${widget.game.whitePlayer.name} vs ${widget.game.blackPlayer.name}',
          sourceGameId: widget.game.gameId,
          sourceTournamentId: widget.game.tourId,
          chessGame: chessGame,
          analysisState: const {},
          variationComments: const {},
          lastViewedPosition: -1,
          tags: const [],
          notes: null,
          isFavorite: false,
          createdAt: now,
          updatedAt: now,
        );

        await repository.createSavedAnalysis(analysis);
        successCount += 1;
      }

      ref.invalidate(libraryFoldersStreamProvider);
      ref.invalidate(folderAnalysisCountProvider);

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context, rootNavigator: true).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            successCount == 1
                ? 'Added to 1 folder'
                : 'Added to $successCount folders',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          backgroundColor: context.colors.surface.withValues(alpha: 0.95),
          behavior: SnackBarBehavior.floating,
        ),
      );
      HapticFeedbackService.success();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to add game: $e',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          backgroundColor: kRedColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recentDatabases = ref.watch(recentDatabasesProvider);
    final rootFolders = ref.watch(rootLibraryFoldersProvider);
    final allFolders =
        ref.watch(combinedLibraryFoldersProvider).valueOrNull ?? [];
    final selectedFolders =
        allFolders
            .where((f) => _selectedFolderIds.contains(f.id) && f.isDatabase)
            .toList();

    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 20.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: Text(
                'Add to Folders',
                style: AppTypography.textLgBold.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ),

            // Recent Databases
            if (recentDatabases.isNotEmpty) ...[
              SizedBox(height: 16.h),
              _buildRecentDatabases(recentDatabases),
            ],

            SizedBox(height: 16.h),

            Flexible(
              child: IgnorePointer(
                ignoring: _isSaving,
                child:
                    rootFolders.isEmpty
                        ? Padding(
                          padding: EdgeInsets.all(24.sp),
                          child: Text(
                            'No folders yet.',
                            style: AppTypography.textSmRegular.copyWith(
                              color: context.colors.textPrimary.withValues(
                                alpha: 0.5,
                              ),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        )
                        : ListView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.symmetric(horizontal: 16.w),
                          itemCount: rootFolders.length,
                          itemBuilder: (context, index) {
                            final folder = rootFolders[index];
                            return _ExpandableFolderTile(
                              folder: folder,
                              isSelected: _selectedFolderIds.contains(
                                folder.id,
                              ),
                              isExpanded: _expandedFolderIds.contains(
                                folder.id,
                              ),
                              selectedIds: _selectedFolderIds,
                              onToggleSelect:
                                  () => _toggleFolderSelection(folder),
                              onToggleExpand:
                                  () => _toggleFolderExpansion(folder.id),
                              onToggleChildSelect: _toggleFolderSelection,
                            );
                          },
                        ),
              ),
            ),

            SizedBox(height: 16.h),
            _buildActionButtons(selectedFolders),
            SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 10.h),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentDatabases(List<LibraryFolder> recent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.w),
          child: Text(
            'RECENT',
            style: AppTypography.textXsBold.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.4),
              letterSpacing: 1.2,
            ),
          ),
        ),
        SizedBox(height: 8.h),
        SizedBox(
          height: 40.h,
          child: ListView.separated(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            scrollDirection: Axis.horizontal,
            itemCount: recent.length,
            separatorBuilder: (_, __) => SizedBox(width: 8.w),
            itemBuilder: (context, index) {
              final folder = recent[index];
              final isSelected = _selectedFolderIds.contains(folder.id);
              return GestureDetector(
                onTap: () => _toggleFolderSelection(folder),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w),
                  decoration: BoxDecoration(
                    color:
                        isSelected
                            ? kPrimaryColor.withValues(alpha: 0.2)
                            : context.colors.textPrimary.withValues(
                              alpha: 0.05,
                            ),
                    borderRadius: BorderRadius.circular(20.br),
                    border: Border.all(
                      color:
                          isSelected
                              ? kPrimaryColor.withValues(alpha: 0.6)
                              : context.colors.textPrimary.withValues(
                                alpha: 0.1,
                              ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.history_rounded,
                        size: 14.sp,
                        color:
                            isSelected
                                ? kPrimaryColor
                                : context.colors.textPrimary.withValues(
                                  alpha: 0.6,
                                ),
                      ),
                      SizedBox(width: 6.w),
                      Text(
                        folder.name,
                        style: AppTypography.textXsMedium.copyWith(
                          color:
                              isSelected
                                  ? context.colors.textPrimary
                                  : context.colors.textPrimary.withValues(
                                    alpha: 0.8,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(List<LibraryFolder> selected) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _isSaving ? null : _handleCreateNewBook,
              child: Opacity(
                opacity: _isSaving ? 0.6 : 1,
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  decoration: BoxDecoration(
                    color: context.colors.textPrimary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12.br),
                    border: Border.all(
                      color: context.colors.textPrimary.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.create_new_folder_outlined,
                        color: context.colors.textPrimary,
                        size: 20.sp,
                      ),
                      SizedBox(width: 8.w),
                      Text(
                        'New Folder',
                        style: AppTypography.textSmMedium.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: GestureDetector(
              onTap: _isSaving ? null : () => _handleAddToSelected(selected),
              child: Opacity(
                opacity: (_isSaving || selected.isEmpty) ? 0.6 : 1,
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  decoration: BoxDecoration(
                    color: kPrimaryColor,
                    borderRadius: BorderRadius.circular(12.br),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isSaving) ...[
                        SizedBox(
                          height: 18.sp,
                          width: 18.sp,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.colors.textPrimary,
                          ),
                        ),
                        SizedBox(width: 8.w),
                      ] else ...[
                        Icon(
                          Icons.add_rounded,
                          color: context.colors.textPrimary,
                          size: 20.sp,
                        ),
                        SizedBox(width: 8.w),
                      ],
                      Text(
                        selected.isEmpty ? 'Add' : 'Add (${selected.length})',
                        style: AppTypography.textSmMedium.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpandableFolderTile extends ConsumerWidget {
  const _ExpandableFolderTile({
    required this.folder,
    required this.isSelected,
    required this.isExpanded,
    required this.selectedIds,
    required this.onToggleSelect,
    required this.onToggleExpand,
    required this.onToggleChildSelect,
  });

  final LibraryFolder folder;
  final bool isSelected;
  final bool isExpanded;
  final Set<String> selectedIds;
  final VoidCallback onToggleSelect;
  final VoidCallback onToggleExpand;
  final Function(LibraryFolder) onToggleChildSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = ref.watch(childLibraryFoldersProvider(folder.id));
    final hasChildren = children.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FolderSelectionTile(
          folder: folder,
          selected: folder.isDatabase && isSelected,
          onTap: folder.isDatabase ? onToggleSelect : onToggleExpand,
          trailing:
              hasChildren
                  ? IconButton(
                    onPressed: onToggleExpand,
                    icon: Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: context.colors.textPrimary.withValues(alpha: 0.5),
                    ),
                  )
                  : null,
        ),
        if (hasChildren && isExpanded) ...[
          SizedBox(height: 4.h),
          ...children.map(
            (child) => Padding(
              padding: EdgeInsets.only(left: 24.w, bottom: 4.h),
              child: _FolderSelectionTile(
                folder: child,
                selected: child.isDatabase && selectedIds.contains(child.id),
                onTap: () {
                  if (child.isDatabase) onToggleChildSelect(child);
                },
                isSmall: true,
              ),
            ),
          ),
        ],
        SizedBox(height: 8.h),
      ],
    );
  }
}

class _FolderSelectionTile extends StatelessWidget {
  const _FolderSelectionTile({
    required this.folder,
    required this.selected,
    required this.onTap,
    this.trailing,
    this.isSmall = false,
  });

  final LibraryFolder folder;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool isSmall;

  @override
  Widget build(BuildContext context) {
    final isChildNode = folder.parentId != null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 16.w,
          vertical: isSmall ? 10.h : 14.h,
        ),
        decoration: BoxDecoration(
          color:
              selected
                  ? kPrimaryColor.withValues(alpha: 0.18)
                  : context.colors.surfaceRecessed,
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(
            color:
                selected
                    ? kPrimaryColor.withValues(alpha: 0.55)
                    : context.colors.textPrimary.withValues(alpha: 0.05),
          ),
        ),
        child: Row(
          children: [
            if (isChildNode) ...[
              Icon(
                Icons.subdirectory_arrow_right_rounded,
                size: 16.sp,
                color: context.colors.textPrimary.withValues(alpha: 0.3),
              ),
              SizedBox(width: 8.w),
            ],
            Icon(
              folder.isLikedGames
                  ? Icons.favorite_rounded
                  : (folder.parentId == null
                      ? Icons.folder_rounded
                      : Icons.folder_open_rounded),
              color: folder.isLikedGames
                  ? context.colors.danger
                  : context.colors.textPrimary
                      .withValues(alpha: isSmall ? 0.6 : 1.0),
              size: isSmall ? 20.sp : 24.sp,
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                folder.name,
                style: (isSmall
                        ? AppTypography.textSmMedium
                        : AppTypography.textSmMedium)
                    .copyWith(
                      color: context.colors.textPrimary.withValues(
                        alpha: isSmall ? 0.8 : 1.0,
                      ),
                    ),
              ),
            ),
            if (trailing != null) trailing!,
            SizedBox(width: 8.w),
            if (folder.isDatabase)
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color:
                    selected
                        ? kPrimaryColor
                        : context.colors.textPrimary.withValues(alpha: 0.35),
                size: isSmall ? 18.sp : 20.sp,
              ),
          ],
        ),
      ),
    );
  }
}
