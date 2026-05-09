import 'dart:math' as math;

import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/widgets/smooth_sheet_config.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/library/widgets/create_folder_dialog.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/library_utils.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

/// Shows a folder-selection sheet for saving a list of already-parsed
/// `ChessGame` entries (e.g. from a multi-PGN paste).
///
/// Unlike `BulkAddToFolderSheet`, no network resolution is needed: the
/// caller has the full game tree in hand.
///
/// [initialFolderId] pre-selects the given folder (useful when the user
/// entered this flow from a specific database's screen).
///
/// Resolves to `true` if at least one game was saved, `false` otherwise.
Future<bool> showImportPgnToFolderSheet({
  required BuildContext context,
  required List<ChessGame> games,
  String? initialFolderId,
  String? sourceLabel,
}) async {
  if (games.isEmpty) return false;
  final allowed = await requirePremiumGuardNoRef(context);
  if (!allowed) return false;
  if (!context.mounted) return false;

  // `ChessSheetRoutes.commentEditor` is typed `SpringModalSheetRoute<void>`,
  // so we track the save outcome out-of-band via a shared flag rather than
  // the route's return value.
  final result = _ImportSheetResult();

  final route = ChessSheetRoutes.commentEditor(
    context: context,
    builder:
        (_) => _ImportPgnToFolderSheetShell(
          games: games,
          sourceLabel: sourceLabel,
          initialFolderId: initialFolderId,
          result: result,
        ),
  );
  await Navigator.of(context).push(route);
  return result.saved;
}

/// Mutable flag shared between the sheet and its caller to signal whether
/// at least one game was successfully saved before the sheet was dismissed.
class _ImportSheetResult {
  bool saved = false;
}

class _ImportPgnToFolderSheetShell extends ConsumerWidget {
  const _ImportPgnToFolderSheetShell({
    required this.games,
    required this.sourceLabel,
    required this.initialFolderId,
    required this.result,
  });

  final List<ChessGame> games;
  final String? sourceLabel;
  final String? initialFolderId;
  final _ImportSheetResult result;

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
                  SheetOffset.proportionalToViewport(0.9),
                ],
                minFlingSpeed: 600.0,
              ),
              builder:
                  (context) => _ImportPgnToFolderPage(
                    games: games,
                    sourceLabel: sourceLabel,
                    initialFolderId: initialFolderId,
                    result: result,
                  ),
            ),
          ],
    );

    return SheetKeyboardDismissible(
      dismissBehavior: const DragDownSheetKeyboardDismissBehavior(
        isContentScrollAware: true,
      ),
      child: PagedSheet(
        decoration: ChessSheetDecoration.dark(alpha: 0.97, borderRadius: 28.sp),
        shrinkChildToAvoidDynamicOverlap: true,
        navigator: navigator,
      ),
    );
  }
}

class _ImportPgnToFolderPage extends ConsumerStatefulWidget {
  const _ImportPgnToFolderPage({
    required this.games,
    required this.sourceLabel,
    required this.initialFolderId,
    required this.result,
  });

  final List<ChessGame> games;
  final String? sourceLabel;
  final String? initialFolderId;
  final _ImportSheetResult result;

  @override
  ConsumerState<_ImportPgnToFolderPage> createState() =>
      _ImportPgnToFolderPageState();
}

class _ImportPgnToFolderPageState
    extends ConsumerState<_ImportPgnToFolderPage> {
  late final Set<String> _selectedFolderIds;
  bool _isSaving = false;
  int _savedEntries = 0;

  @override
  void initState() {
    super.initState();
    _selectedFolderIds = <String>{
      if (widget.initialFolderId != null) widget.initialFolderId!,
    };
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
    if (data == null || data.name.trim().isEmpty) return;

    try {
      final created = await ref
          .read(libraryRepositoryProvider)
          .createFolder(name: data.name, parentId: data.parentId);
      ref.invalidate(libraryFoldersStreamProvider);

      if (!mounted) return;
      setState(() => _selectedFolderIds.add(created.id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Database "${data.name}" created',
            style: AppTypography.textSmMedium.copyWith(color: context.colors.textPrimary),
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
            'Failed to create database: $e',
            style: AppTypography.textSmMedium.copyWith(color: context.colors.textPrimary),
          ),
          backgroundColor: kRedColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _titleForGame(ChessGame game) {
    final white = (game.metadata['White']?.toString().trim() ?? '');
    final black = (game.metadata['Black']?.toString().trim() ?? '');
    final w = white.isEmpty ? 'White' : white;
    final b = black.isEmpty ? 'Black' : black;
    return '$w vs $b';
  }

  Future<void> _handleAddToSelected(List<LibraryFolder> selected) async {
    if (_isSaving) return;
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Select at least one database',
            style: AppTypography.textSmMedium.copyWith(color: context.colors.textPrimary),
          ),
          backgroundColor: context.colors.surface.withValues(alpha: 0.95),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _savedEntries = 0;
    });

    try {
      final repository = ref.read(libraryRepositoryProvider);
      final userId = repository.supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final now = DateTime.now();
      const chunkSize = 250;
      final buffer = <SavedAnalysis>[];

      for (final game in widget.games) {
        for (final folder in selected) {
          buffer.add(
            SavedAnalysis(
              id: '',
              userId: userId,
              folderId: folder.id,
              title: _titleForGame(game),
              sourceGameId: null,
              sourceTournamentId: null,
              chessGame: game,
              analysisState: const {},
              variationComments: const {},
              lastViewedPosition: -1,
              tags: const [],
              notes: null,
              isFavorite: false,
              createdAt: now,
              updatedAt: now,
            ),
          );
        }
      }

      for (var i = 0; i < buffer.length; i += chunkSize) {
        final end = math.min(i + chunkSize, buffer.length);
        final chunk = buffer.sublist(i, end);
        await repository.createSavedAnalysesBulk(chunk);
        if (mounted) setState(() => _savedEntries += chunk.length);
      }

      ref.invalidate(libraryFoldersStreamProvider);

      widget.result.saved = _savedEntries > 0;

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _savedEntries > 0
                ? 'Imported $_savedEntries entries into your databases'
                : 'No games were imported',
            style: AppTypography.textSmMedium.copyWith(color: context.colors.textPrimary),
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
            'Import failed: $e',
            style: AppTypography.textSmMedium.copyWith(color: context.colors.textPrimary),
          ),
          backgroundColor: kRedColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// Sorts folders hierarchically (child follows parent).
  List<LibraryFolder> _sortFoldersHierarchically(List<LibraryFolder> folders) {
    final Map<String?, List<LibraryFolder>> byParent = {};
    for (final f in folders) {
      byParent.putIfAbsent(f.parentId, () => []).add(f);
    }

    final sorted = <LibraryFolder>[];
    void addFolders(String? parentId) {
      final children = byParent[parentId] ?? [];
      children.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      for (final folder in children) {
        sorted.add(folder);
        addFolders(folder.id);
      }
    }

    addFolders(null);

    if (sorted.length < folders.length) {
      final sortedIds = sorted.map((f) => f.id).toSet();
      for (final folder in folders) {
        if (!sortedIds.contains(folder.id)) sorted.add(folder);
      }
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final foldersAsync = ref.watch(libraryFoldersStreamProvider);
    final sourceLabel = widget.sourceLabel ?? 'clipboard';

    final selectedFolders =
        foldersAsync.whenOrNull(
          data:
              (folders) =>
                  folders
                      .where((f) => _selectedFolderIds.contains(f.id))
                      .where((f) => !f.isSubscribed)
                      .toList(),
        ) ??
        [];

    final totalRows = widget.games.length * math.max(selectedFolders.length, 1);

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Import to My Library',
                    style: AppTypography.textLgBold.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 6.h),
                  Text(
                    '${widget.games.length} games from $sourceLabel',
                    style: AppTypography.textSmRegular.copyWith(
                      color: context.colors.textPrimary.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16.h),
            Flexible(
              child: IgnorePointer(
                ignoring: _isSaving,
                child: foldersAsync.when(
                  data: (folders) {
                    // Only owned (not subscribed) folders can receive writes.
                    final writable =
                        folders.where((f) => !f.isSubscribed).toList();
                    if (writable.isEmpty) {
                      return Padding(
                        padding: EdgeInsets.all(20.sp),
                        child: Text(
                          'No databases yet. Create one below.',
                          style: AppTypography.textSmRegular.copyWith(
                            color: context.colors.textPrimary.withValues(alpha: 0.5),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      );
                    }
                    final sortedFolders =
                        _sortFoldersHierarchically(writable);
                    return ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.symmetric(horizontal: 16.w),
                      itemCount: sortedFolders.length,
                      separatorBuilder: (_, __) => SizedBox(height: 8.h),
                      itemBuilder: (context, index) {
                        final folder = sortedFolders[index];
                        return _ImportFolderTile(
                          folder: folder,
                          selected: _selectedFolderIds.contains(folder.id),
                          onTap: () => _toggleFolder(folder),
                        );
                      },
                    );
                  },
                  loading:
                      () =>  Center(
                        child: CircularProgressIndicator(color: context.colors.textPrimary),
                      ),
                  error:
                      (e, _) => Center(
                        child: Text(
                          'Error loading databases',
                          style: AppTypography.textSmRegular.copyWith(
                            color: kRedColor,
                          ),
                        ),
                      ),
                ),
              ),
            ),
            if (_isSaving)
              Padding(
                padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10.br),
                      child: LinearProgressIndicator(
                        minHeight: 8.h,
                        color: kPrimaryColor,
                        backgroundColor: context.colors.textPrimary.withValues(alpha: 0.08),
                        value:
                            totalRows == 0
                                ? null
                                : (_savedEntries / totalRows).clamp(0, 1),
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      'Saved $_savedEntries / $totalRows',
                      style: AppTypography.textXsRegular.copyWith(
                        color: context.colors.textPrimary.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
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
                                'New Database',
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
                      onTap:
                          _isSaving
                              ? null
                              : () => _handleAddToSelected(selectedFolders),
                      child: Opacity(
                        opacity:
                            (_isSaving || selectedFolders.isEmpty) ? 0.6 : 1,
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
                                  Icons.library_add_rounded,
                                  color: context.colors.textPrimary,
                                  size: 20.sp,
                                ),
                                SizedBox(width: 8.w),
                              ],
                              Text(
                                selectedFolders.isEmpty
                                    ? 'Import'
                                    : 'Import (${selectedFolders.length})',
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
            ),
            SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 10.h),
          ],
        ),
      ),
    );
  }
}

class _ImportFolderTile extends StatelessWidget {
  const _ImportFolderTile({
    required this.folder,
    required this.selected,
    required this.onTap,
  });

  final LibraryFolder folder;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isSubdatabase = folder.parentId != null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.only(
          left: 16.w + (isSubdatabase ? 24.w : 0),
          right: 16.w,
          top: 14.h,
          bottom: 14.h,
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
            if (isSubdatabase) ...[
              Icon(
                Icons.subdirectory_arrow_right_rounded,
                size: 16.sp,
                color: context.colors.textPrimary.withValues(alpha: 0.3),
              ),
              SizedBox(width: 8.w),
            ],
            Icon(Icons.folder_rounded, color: context.colors.textPrimary, size: 24.sp),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                folder.name,
                style: AppTypography.textSmMedium.copyWith(color: context.colors.textPrimary),
              ),
            ),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color:
                  selected
                      ? kPrimaryColor
                      : context.colors.textPrimary.withValues(alpha: 0.35),
              size: 20.sp,
            ),
          ],
        ),
      ),
    );
  }
}
