import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/widgets/smooth_sheet_config.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/library/utils/gamebase_game_to_games_tour_model.dart';
import 'package:chessever2/screens/library/widgets/create_folder_dialog.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

/// Shows the Add to Folder sheet with smooth spring animations.
Future<void> showAddToFolderSheet({
  required BuildContext context,
  required GamesTourModel game,
}) async {
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
      onGenerateInitialRoutes: (_, __) => [
        SpringPagedSheetRoute(
          scrollConfiguration: const SheetScrollConfiguration(),
          dragConfiguration: ChessSheetConfigs.commentEditor,
          initialOffset: const SheetOffset.proportionalToViewport(0.55),
          snapGrid: SheetSnapGrid(
            snaps: const [
              SheetOffset.proportionalToViewport(0.55),
              SheetOffset.proportionalToViewport(0.75),
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
  bool _isSaving = false;

  Future<ChessGame> _resolveChessGame() async {
    final gameRepository = ref.read(gameRepositoryProvider);
    final gamebaseRepository = ref.read(gamebaseRepositoryProvider);

    String? pgn = widget.game.pgn;
    if (pgn == null || pgn.trim().isEmpty) {
      try {
        pgn = await gameRepository.getGamePgn(widget.game.gameId);
      } catch (_) {
        // Ignore and fall back to Gamebase fetch below.
      }

      if (pgn == null || pgn.trim().isEmpty) {
        final fullGame = await gamebaseRepository.getGameById(widget.game.gameId);
        pgn =
            fullGame != null
                ? mapGamebaseGameToGamesTourModel(fullGame).pgn
                : null;
      }
    }

    if (pgn == null || pgn.trim().isEmpty) {
      throw Exception('Game PGN not found');
    }

    final chessGame = ChessGame.fromPgn(widget.game.gameId, pgn);
    final meta = Map<String, dynamic>.from(chessGame.metadata);
    meta.putIfAbsent('White', () => widget.game.whitePlayer.name);
    meta.putIfAbsent('Black', () => widget.game.blackPlayer.name);
    return chessGame.copyWith(metadata: meta);
  }

  void _toggleFolder(LibraryFolder folder) {
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

  Future<void> _handleCreateNewBook() async {
    if (_isSaving) return;

    HapticFeedbackService.light();
    final name = await showCreateFolderDialog(context);
    if (name == null || name.trim().isEmpty) return;

    try {
      final created =
          await ref.read(libraryRepositoryProvider).createFolder(name: name);
      ref.invalidate(libraryFoldersStreamProvider);

      if (!mounted) return;
      setState(() => _selectedFolderIds.add(created.id));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Book "$name" created',
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
          ),
          backgroundColor: kBlack2Color.withValues(alpha: 0.95),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to create book: $e',
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
          ),
          backgroundColor: kRedColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleAddToSelected(List<LibraryFolder> selected) async {
    if (_isSaving) return;
    if (selected.isEmpty) {
      HapticFeedbackService.light();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Select at least one book',
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
          ),
          backgroundColor: kBlack2Color.withValues(alpha: 0.95),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

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

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            successCount == 1
                ? 'Added to 1 book'
                : 'Added to $successCount books',
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
          ),
          backgroundColor: kBlack2Color.withValues(alpha: 0.95),
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
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
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
    final foldersAsync = ref.watch(libraryFoldersStreamProvider);
    final folders = foldersAsync.valueOrNull ?? const <LibraryFolder>[];
    final selectedFolders =
        folders.where((f) => _selectedFolderIds.contains(f.id)).toList();

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
              'Add to Books',
              style: AppTypography.textLgBold.copyWith(color: kWhiteColor),
            ),
          ),
          SizedBox(height: 16.h),
          Flexible(
            child: IgnorePointer(
              ignoring: _isSaving,
              child: foldersAsync.when(
                data: (folders) {
                  if (folders.isEmpty) {
                    return Padding(
                      padding: EdgeInsets.all(20.sp),
                      child: Text(
                        'No books yet.',
                        style: AppTypography.textSmRegular.copyWith(
                          color: kWhiteColor.withValues(alpha: 0.5),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    itemCount: folders.length,
                    separatorBuilder: (_, __) => SizedBox(height: 8.h),
                    itemBuilder: (context, index) {
                      final folder = folders[index];
                      return _FolderSelectionTile(
                        folder: folder,
                        selected: _selectedFolderIds.contains(folder.id),
                        onTap: () => _toggleFolder(folder),
                      );
                    },
                  );
                },
                loading:
                    () => const Center(
                      child: CircularProgressIndicator(color: kWhiteColor),
                    ),
                error:
                    (e, _) => Center(
                      child: Text(
                        'Error loading books',
                        style: AppTypography.textSmRegular.copyWith(
                          color: kRedColor,
                        ),
                      ),
                    ),
              ),
            ),
          ),
          SizedBox(height: 16.h),
          Padding(
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
                          color: kWhiteColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12.br),
                          border: Border.all(
                            color: kWhiteColor.withValues(alpha: 0.14),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.create_new_folder_outlined,
                              color: kWhiteColor,
                              size: 20.sp,
                            ),
                            SizedBox(width: 8.w),
                            Text(
                              'New Book',
                              style: AppTypography.textSmMedium.copyWith(
                                color: kWhiteColor,
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
                    onTap:
                        _isSaving
                            ? null
                            : () => _handleAddToSelected(selectedFolders),
                    child: Opacity(
                      opacity: (_isSaving || selectedFolders.isEmpty) ? 0.6 : 1,
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
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: kWhiteColor,
                                ),
                              ),
                              SizedBox(width: 8.w),
                            ] else ...[
                              Icon(
                                Icons.add_rounded,
                                color: kWhiteColor,
                                size: 20.sp,
                              ),
                              SizedBox(width: 8.w),
                            ],
                            Text(
                              selectedFolders.isEmpty
                                  ? 'Add'
                                  : 'Add (${selectedFolders.length})',
                              style: AppTypography.textSmMedium.copyWith(
                                color: kWhiteColor,
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
          ),
          SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 10.h),
        ],
      ),
    ),
  );
  }
}

class _FolderSelectionTile extends StatelessWidget {
  const _FolderSelectionTile({
    required this.folder,
    required this.selected,
    required this.onTap,
  });

  final LibraryFolder folder;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(16.sp),
        decoration: BoxDecoration(
          color:
              selected
                  ? kPrimaryColor.withValues(alpha: 0.18)
                  : const Color(0xFF27272A),
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(
            color:
                selected
                    ? kPrimaryColor.withValues(alpha: 0.55)
                    : kWhiteColor.withValues(alpha: 0.05),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.folder_rounded, color: kWhiteColor, size: 24.sp),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                folder.name,
                style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
              ),
            ),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color:
                  selected
                      ? kPrimaryColor
                      : kWhiteColor.withValues(alpha: 0.35),
              size: 20.sp,
            ),
          ],
        ),
      ),
    );
  }
}
