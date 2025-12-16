import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/library/utils/gamebase_game_to_games_tour_model.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/library/widgets/create_folder_dialog.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:uuid/uuid.dart';

class AddToFolderSheet extends ConsumerWidget {
  final GamesTourModel game;

  const AddToFolderSheet({super.key, required this.game});

  Future<void> _handleAddToFolder(
    BuildContext context,
    WidgetRef ref,
    LibraryFolder folder,
  ) async {
    try {
      HapticFeedbackService.light(); // Fixed method name
      // Optimistically pop first
      Navigator.pop(context);

      final gameRepository = ref.read(gameRepositoryProvider);
      final gamebaseRepository = ref.read(gamebaseRepositoryProvider);

      // Fetch PGN if missing
      String? pgn = game.pgn;
      if (pgn == null || pgn.isEmpty) {
        try {
          pgn = await gameRepository.getGamePgn(game.gameId);
        } catch (_) {
          // Ignore and fall back to Gamebase fetch below.
        }

        if (pgn == null || pgn.trim().isEmpty) {
          final fullGame = await gamebaseRepository.getGameById(game.gameId);
          pgn = fullGame != null ? mapGamebaseGameToGamesTourModel(fullGame).pgn : null;
        }

        if (pgn == null || pgn.trim().isEmpty) throw Exception('Game PGN not found');
      }

      final chessGame = ChessGame.fromPgn(game.gameId, pgn);
      // Ensure metadata has names
      final meta = Map<String, dynamic>.from(chessGame.metadata);
      if (!meta.containsKey('White')) meta['White'] = game.whitePlayer.name;
      if (!meta.containsKey('Black')) meta['Black'] = game.blackPlayer.name;

      final userId =
          ref.read(libraryRepositoryProvider).supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final analysis = SavedAnalysis(
        id: const Uuid().v4(),
        userId: userId,
        folderId: folder.id,
        title: '${game.whitePlayer.name} vs ${game.blackPlayer.name}',
        sourceGameId: game.gameId,
        sourceTournamentId: game.tourId,
        chessGame: chessGame.copyWith(metadata: meta),
        analysisState: const {},
        variationComments: const {},
        lastViewedPosition: -1,
        tags: const [],
        notes: null,
        isFavorite: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await ref.read(libraryRepositoryProvider).createSavedAnalysis(analysis);

      ref.invalidate(libraryFoldersStreamProvider);

      if (context.mounted) {
        HapticFeedbackService.success();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Added to ${folder.name}',
              style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
            ),
            backgroundColor: kBlack2Color,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
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
      }
    }
  }

  Future<void> _handleCreateNewFolder(
    BuildContext context,
    WidgetRef ref,
  ) async {
    Navigator.pop(context); // Close sheet first

    // Delay slightly to allow sheet to close
    await Future.delayed(const Duration(milliseconds: 200));

    if (!context.mounted) return;

    final folderName = await showCreateFolderDialog(context);

    if (folderName != null && folderName.isNotEmpty && context.mounted) {
      try {
        // Create the folder
        final newFolder = await ref
            .read(libraryRepositoryProvider)
            .createFolder(name: folderName);
        // Automatically add to this new folder
        if (context.mounted) {
          await _handleAddToFolder(context, ref, newFolder);
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to create folder: $e',
                style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
              ),
              backgroundColor: kRedColor,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(libraryFoldersStreamProvider);

    return Container(
      decoration: BoxDecoration(
        color: kBackgroundColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.br)),
      ),
      padding: EdgeInsets.symmetric(vertical: 20.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: Text(
              'Add to Book',
              style: AppTypography.textLgBold.copyWith(color: kWhiteColor),
            ),
          ),
          SizedBox(height: 16.h),
          Flexible(
            child: foldersAsync.when(
              data: (folders) {
                if (folders.isEmpty) {
                  return Padding(
                    padding: EdgeInsets.all(20.sp),
                    child: Text(
                      'No books yet.',
                      style: AppTypography.textSmRegular.copyWith(
                        color: kWhiteColor.withOpacity(0.5),
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
                      onTap: () => _handleAddToFolder(context, ref, folder),
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
                      'Error loading folders',
                      style: TextStyle(color: kRedColor),
                    ),
                  ),
            ),
          ),
          SizedBox(height: 16.h),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: GestureDetector(
              onTap: () => _handleCreateNewFolder(context, ref),
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 14.h),
                decoration: BoxDecoration(
                  color: kWhiteColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12.br),
                  border: Border.all(color: kWhiteColor.withValues(alpha: 0.14)),
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
                      'Create New Book',
                      style: AppTypography.textSmMedium.copyWith(
                        color: kWhiteColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 10.h),
        ],
      ),
    );
  }
}

class _FolderSelectionTile extends StatelessWidget {
  final LibraryFolder folder;
  final VoidCallback onTap;

  const _FolderSelectionTile({required this.folder, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(16.sp),
        decoration: BoxDecoration(
          color: const Color(0xFF27272A),
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(color: kWhiteColor.withOpacity(0.05)),
        ),
        child: Row(
          children: [
            Icon(Icons.folder_rounded, color: kWhiteColor, size: 24.sp),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    folder.name,
                    style: AppTypography.textSmMedium.copyWith(
                      color: kWhiteColor,
                    ),
                  ),
                  // Removed gameCount assumption since it caused lint, assume it's not present or I don't need it.
                ],
              ),
            ),
            Icon(
              Icons.add_circle_outline_rounded,
              color: kWhiteColor.withOpacity(0.3),
              size: 20.sp,
            ),
          ],
        ),
      ),
    );
  }
}
