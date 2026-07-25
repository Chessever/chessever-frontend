import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/chessboard/widgets/smooth_sheet_config.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/logger/logger.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

/// Moves one saved game into another database the user owns.
///
/// Picking is the whole interaction — a tap on a row commits the move and
/// closes the sheet, so there is no confirm button to hunt for. [onMoved] runs
/// after a successful move so the host list can refresh.
Future<void> showMoveGameToDatabaseSheet({
  required BuildContext context,
  required SavedAnalysis analysis,
  VoidCallback? onMoved,
}) async {
  final route = ChessSheetRoutes.actionMenu(
    context: context,
    builder: (_) => _MoveGameSheetShell(analysis: analysis, onMoved: onMoved),
  );
  await Navigator.of(context).push(route);
}

class _MoveGameSheetShell extends ConsumerWidget {
  const _MoveGameSheetShell({required this.analysis, required this.onMoved});

  final SavedAnalysis analysis;
  final VoidCallback? onMoved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigator = Navigator(
      onGenerateInitialRoutes:
          (_, __) => [
            SpringPagedSheetRoute(
              scrollConfiguration: const SheetScrollConfiguration(),
              dragConfiguration: ChessSheetConfigs.actionMenu,
              initialOffset: const SheetOffset.proportionalToViewport(0.55),
              snapGrid: SheetSnapGrid(
                snaps: const [
                  SheetOffset.proportionalToViewport(0.55),
                  SheetOffset.proportionalToViewport(0.85),
                ],
                minFlingSpeed: 800.0,
              ),
              builder:
                  (context) =>
                      _MoveGamePage(analysis: analysis, onMoved: onMoved),
            ),
          ],
    );

    return PagedSheet(
      decoration: ChessSheetDecoration.dark(
        context,
        alpha: 0.97,
        borderRadius: 28.sp,
      ),
      shrinkChildToAvoidDynamicOverlap: true,
      navigator: navigator,
    );
  }
}

class _MoveGamePage extends ConsumerStatefulWidget {
  const _MoveGamePage({required this.analysis, required this.onMoved});

  final SavedAnalysis analysis;
  final VoidCallback? onMoved;

  @override
  ConsumerState<_MoveGamePage> createState() => _MoveGamePageState();
}

class _MoveGamePageState extends ConsumerState<_MoveGamePage> {
  /// Id of the database currently being written to — drives the in-row
  /// spinner, so the tapped row is visibly the one doing work.
  String? _movingToId;

  bool get _isMoving => _movingToId != null;

  /// "Openings › Sicilian" — the chain of folder names above a database, so two
  /// databases sharing a name stay tellable apart.
  String _pathFor(LibraryFolder folder, Map<String, LibraryFolder> byId) {
    final parts = <String>[];
    var parentId = folder.parentId;
    var guard = 0;
    while (parentId != null && guard < 8) {
      final parent = byId[parentId];
      if (parent == null) break;
      parts.insert(0, parent.displayName);
      parentId = parent.parentId;
      guard++;
    }
    return parts.join('  ›  ');
  }

  Future<void> _move(LibraryFolder target) async {
    if (_isMoving) return;
    setState(() => _movingToId = target.id);
    HapticFeedbackService.medium();

    // One tap commits, so the origin is kept for an undo rather than making the
    // user hunt back through the tree to reverse a mis-tap.
    final origin = widget.analysis.folderId;

    try {
      final repository = ref.read(libraryRepositoryProvider);
      await repository.moveAnalysisToFolder(widget.analysis.id, target.id);

      ref.invalidate(libraryFoldersStreamProvider);
      ref.invalidate(folderAnalysisCountProvider);

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final analysisId = widget.analysis.id;
      final onMoved = widget.onMoved;
      Navigator.of(context, rootNavigator: true).pop();
      onMoved?.call();
      HapticFeedbackService.success();
      showAppSnackOn(
        messenger,
        'Moved to "${target.displayName}"',
        tone: AppSnackTone.success,
        actionLabel: origin == null ? null : 'Undo',
        onAction:
            origin == null
                ? null
                : () async {
                  try {
                    await repository.moveAnalysisToFolder(analysisId, origin);
                    ref.invalidate(libraryFoldersStreamProvider);
                    ref.invalidate(folderAnalysisCountProvider);
                    onMoved?.call();
                    HapticFeedbackService.success();
                  } catch (e, st) {
                    talker.handle(e, st);
                  }
                },
      );
    } catch (e, st) {
      talker.handle(e, st);
      if (!mounted) return;
      HapticFeedbackService.error();
      showAppSnack(
        context,
        userFacingError(e, fallback: 'Could not move this game. Try again.'),
        tone: AppSnackTone.danger,
      );
      setState(() => _movingToId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allFolders =
        ref.watch(combinedLibraryFoldersProvider).valueOrNull ??
        const <LibraryFolder>[];
    final byId = {for (final folder in allFolders) folder.id: folder};

    // Only databases the user owns can receive a game. "My Likes" is excluded
    // because membership there means "liked", not "filed here".
    final targets =
        allFolders
            .where(
              (folder) =>
                  folder.isDatabase &&
                  !folder.isSubscribed &&
                  !folder.isLikedGames,
            )
            .toList()
          ..sort(
            (a, b) => a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            ),
          );

    return Material(
      type: MaterialType.transparency,
      child: IgnorePointer(
        ignoring: _isMoving,
        child: Padding(
          padding: EdgeInsets.only(top: 20.h, bottom: 8.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Text(
                  'Move to database',
                  style: AppTypography.textLgBold.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
              SizedBox(height: 16.h),
              Flexible(
                child:
                    targets.isEmpty
                        ? Padding(
                          padding: EdgeInsets.all(24.sp),
                          child: Text(
                            'You have no other databases yet.',
                            textAlign: TextAlign.center,
                            style: AppTypography.textSmRegular.copyWith(
                              color: context.colors.textSecondary,
                            ),
                          ),
                        )
                        : ListView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.symmetric(horizontal: 12.w),
                          itemCount: targets.length,
                          itemBuilder: (context, index) {
                            final folder = targets[index];
                            return _DatabaseRow(
                              folder: folder,
                              path: _pathFor(folder, byId),
                              isCurrent: folder.id == widget.analysis.folderId,
                              isBusy: folder.id == _movingToId,
                              onTap: () => _move(folder),
                            );
                          },
                        ),
              ),
              SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 8.h),
            ],
          ),
        ),
      ),
    );
  }
}

class _DatabaseRow extends StatelessWidget {
  const _DatabaseRow({
    required this.folder,
    required this.path,
    required this.isCurrent,
    required this.isBusy,
    required this.onTap,
  });

  final LibraryFolder folder;
  final String path;
  final bool isCurrent;
  final bool isBusy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textColor =
        isCurrent ? context.colors.textSecondary : context.colors.textPrimary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isCurrent ? null : onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 12.h),
        child: Row(
          children: [
            Icon(
              Icons.storage_rounded,
              size: 19.sp,
              color:
                  isCurrent
                      ? context.colors.textTertiary
                      : context.colors.iconPrimary,
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    folder.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.textMdMedium.copyWith(
                      color: textColor,
                    ),
                  ),
                  if (path.isNotEmpty) ...[
                    SizedBox(height: 2.h),
                    Text(
                      path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.textXsRegular.copyWith(
                        color: context.colors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isBusy) ...[
              SizedBox(width: 10.w),
              SizedBox(
                width: 16.sp,
                height: 16.sp,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.colors.textPrimary,
                ),
              ),
            ] else if (isCurrent) ...[
              SizedBox(width: 10.w),
              Text(
                'Current',
                style: AppTypography.textXsMedium.copyWith(
                  color: context.colors.textTertiary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
