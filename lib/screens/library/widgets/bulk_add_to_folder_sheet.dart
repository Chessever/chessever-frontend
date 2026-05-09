import 'dart:math' as math;

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
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

Future<void> showBulkAddToFolderSheet({
  required BuildContext context,
  required List<GamesTourModel> games,
  String? sourceLabel,
}) async {
  if (games.isEmpty) return;
  final allowed = await requirePremiumGuardNoRef(context);
  if (!allowed) return;
  if (!context.mounted) return;

  final route = ChessSheetRoutes.commentEditor(
    context: context,
    builder:
        (_) =>
            _BulkAddToFolderSheetShell(games: games, sourceLabel: sourceLabel),
  );
  await Navigator.of(context).push(route);
}

class _BulkAddToFolderSheetShell extends ConsumerWidget {
  const _BulkAddToFolderSheetShell({
    required this.games,
    required this.sourceLabel,
  });

  final List<GamesTourModel> games;
  final String? sourceLabel;

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
                  (context) => _BulkAddToFolderPage(
                    games: games,
                    sourceLabel: sourceLabel,
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

class _BulkAddToFolderPage extends ConsumerStatefulWidget {
  const _BulkAddToFolderPage({required this.games, required this.sourceLabel});

  final List<GamesTourModel> games;
  final String? sourceLabel;

  @override
  ConsumerState<_BulkAddToFolderPage> createState() =>
      _BulkAddToFolderPageState();
}

class _BulkAddToFolderPageState extends ConsumerState<_BulkAddToFolderPage> {
  final Set<String> _selectedFolderIds = <String>{};
  bool _isSaving = false;
  int _processedGames = 0;
  int _savedEntries = 0;
  int _skippedEntries = 0;
  int _failedGames = 0;

  Future<ChessGame> _resolveChessGame(GamesTourModel game) async {
    final gameRepository = ref.read(gameRepositoryProvider);
    final gamebaseRepository = ref.read(gamebaseRepositoryProvider);

    String? pgn = game.pgn;
    final hasMoves = pgn != null && pgnHasMoves(pgn);

    if (!hasMoves) {
      try {
        final supabasePgn = await gameRepository.getGamePgn(game.gameId);
        if (supabasePgn != null && pgnHasMoves(supabasePgn)) {
          pgn = supabasePgn;
        }
      } catch (_) {
        // Fall through to gamebase fetch.
      }

      if (pgn == null || !pgnHasMoves(pgn)) {
        final fullGame = await gamebaseRepository.getGameWithPgn(game.gameId);
        if (fullGame?.pgn != null && pgnHasMoves(fullGame!.pgn!)) {
          pgn = fullGame.pgn;
        } else if (fullGame?.data != null) {
          final builtPgn = buildPgnFromGamebaseData(fullGame!.data);
          if (builtPgn != null && pgnHasMoves(builtPgn)) {
            pgn = builtPgn;
          }
        }
      }
    }

    if (pgn == null || pgn.trim().isEmpty) {
      throw Exception('PGN not found for game ${game.gameId}');
    }

    final chessGame = ChessGame.fromPgn(game.gameId, pgn);
    final meta = Map<String, dynamic>.from(chessGame.metadata);

    meta['White'] = game.whitePlayer.name;
    meta['Black'] = game.blackPlayer.name;
    final whiteFed =
        game.whitePlayer.countryCode.isNotEmpty
            ? game.whitePlayer.countryCode
            : game.whitePlayer.federation;
    final blackFed =
        game.blackPlayer.countryCode.isNotEmpty
            ? game.blackPlayer.countryCode
            : game.blackPlayer.federation;
    if (whiteFed.isNotEmpty) meta['WhiteFed'] = whiteFed;
    if (blackFed.isNotEmpty) meta['BlackFed'] = blackFed;
    if (game.whitePlayer.title.isNotEmpty) {
      meta['WhiteTitle'] = game.whitePlayer.title;
    }
    if (game.blackPlayer.title.isNotEmpty) {
      meta['BlackTitle'] = game.blackPlayer.title;
    }
    if (game.whitePlayer.rating > 0) {
      meta['WhiteElo'] = game.whitePlayer.rating.toString();
    }
    if (game.blackPlayer.rating > 0) {
      meta['BlackElo'] = game.blackPlayer.rating.toString();
    }
    final resolvedEventName = _resolveEventName(
      metadataEvent: meta['Event']?.toString(),
      tourSlug: game.tourSlug,
      tourId: game.tourId,
    );
    if (resolvedEventName != null) {
      meta['Event'] = resolvedEventName;
    } else if (_looksLikeOpaqueEventId(meta['Event']?.toString())) {
      // Avoid persisting hash/UUID-like placeholders as event names.
      meta.remove('Event');
    }

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

  String? _resolveEventName({
    required String? metadataEvent,
    required String? tourSlug,
    required String? tourId,
  }) {
    final fromMetadata = metadataEvent?.trim() ?? '';
    if (_isReadableEventName(fromMetadata)) return fromMetadata;

    final fromSlug = tourSlug?.trim() ?? '';
    if (_isReadableEventName(fromSlug)) return _humanizeSlug(fromSlug);

    final fromId = tourId?.trim() ?? '';
    if (_isReadableEventName(fromId)) return fromId;

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
    return !_looksLikeOpaqueEventId(value);
  }

  bool _looksLikeOpaqueEventId(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return false;

    final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    );
    if (uuid.hasMatch(text)) return true;

    final objectId = RegExp(r'^[0-9a-f]{24}$', caseSensitive: false);
    if (objectId.hasMatch(text)) return true;

    final longHex = RegExp(r'^[0-9a-f]{12,64}$', caseSensitive: false);
    if (longHex.hasMatch(text)) return true;

    if (text.length >= 16 && !text.contains(RegExp(r'\s'))) {
      final alphaCount = RegExp(r'[A-Za-z]').allMatches(text).length;
      final digitCount = RegExp(r'\d').allMatches(text).length;
      final separatorCount = RegExp(r'[-_]').allMatches(text).length;
      final otherCount = text.length - alphaCount - digitCount - separatorCount;
      if (otherCount == 0 && digitCount >= (alphaCount * 2)) return true;
    }

    return false;
  }

  String _humanizeSlug(String value) {
    if (!value.contains('-') && !value.contains('_')) return value;
    final words = value
        .split(RegExp(r'[-_]+'))
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (words.isEmpty) return value;
    return words.map(_capitalizeWord).join(' ');
  }

  String _capitalizeWord(String word) {
    if (word.isEmpty) return word;
    if (RegExp(r'^\d+$').hasMatch(word)) return word;
    final lower = word.toLowerCase();
    return '${lower[0].toUpperCase()}${lower.substring(1)}';
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
      _processedGames = 0;
      _savedEntries = 0;
      _skippedEntries = 0;
      _failedGames = 0;
    });

    try {
      final repository = ref.read(libraryRepositoryProvider);
      final userId = repository.supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final now = DateTime.now();
      final uniqueGames = widget.games
          .where((g) => g.gameId.trim().isNotEmpty)
          .fold<Map<String, GamesTourModel>>({}, (acc, g) {
            acc[g.gameId] = g;
            return acc;
          })
          .values
          .toList(growable: false);

      final sourceIds = uniqueGames.map((g) => g.gameId).toList();
      final existingByFolder = <String, Set<String>>{};
      for (final folder in selected) {
        existingByFolder[folder.id] = await repository
            .getExistingSourceGameIdsInFolder(
              folderId: folder.id,
              sourceGameIds: sourceIds,
            );
      }

      const gameConcurrency = 4;
      const insertChunkSize = 250;
      var insertBuffer = <SavedAnalysis>[];

      for (var i = 0; i < uniqueGames.length; i += gameConcurrency) {
        final end = math.min(i + gameConcurrency, uniqueGames.length);
        final batch = uniqueGames.sublist(i, end);

        final gamesRequiringResolve = <GamesTourModel>[];
        for (final game in batch) {
          final needsInsert = selected.any(
            (folder) => !existingByFolder[folder.id]!.contains(game.gameId),
          );
          if (needsInsert) {
            gamesRequiringResolve.add(game);
          } else {
            _processedGames += 1;
            _skippedEntries += selected.length;
          }
        }

        if (gamesRequiringResolve.isEmpty) {
          if (mounted) setState(() {});
          continue;
        }

        final resolved = await Future.wait(
          gamesRequiringResolve.map((game) async {
            try {
              final chessGame = await _resolveChessGame(game);
              return (game: game, chessGame: chessGame);
            } catch (_) {
              return null;
            }
          }),
        );

        for (final item in resolved) {
          _processedGames += 1;
          if (item == null) {
            _failedGames += 1;
            continue;
          }

          for (final folder in selected) {
            final existing = existingByFolder[folder.id]!;
            if (existing.contains(item.game.gameId)) {
              _skippedEntries += 1;
              continue;
            }

            insertBuffer.add(
              SavedAnalysis(
                id: '',
                userId: userId,
                folderId: folder.id,
                title:
                    '${item.game.whitePlayer.name} vs ${item.game.blackPlayer.name}',
                sourceGameId: item.game.gameId,
                sourceTournamentId: item.game.tourId,
                chessGame: item.chessGame,
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
            existing.add(item.game.gameId);
          }
        }

        while (insertBuffer.length >= insertChunkSize) {
          final chunk = insertBuffer.sublist(0, insertChunkSize);
          await repository.createSavedAnalysesBulk(chunk);
          _savedEntries += chunk.length;
          insertBuffer = insertBuffer.sublist(insertChunkSize);
        }

        if (mounted) setState(() {});
      }

      if (insertBuffer.isNotEmpty) {
        await repository.createSavedAnalysesBulk(insertBuffer);
        _savedEntries += insertBuffer.length;
      }

      ref.invalidate(libraryFoldersStreamProvider);

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _savedEntries > 0
                ? 'Added $_savedEntries entries to your databases'
                : 'No new games were added',
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
            'Bulk add failed: $e',
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

  /// Sorts folders such that children follow their parents based on parentId.
  List<LibraryFolder> _sortFoldersHierarchically(List<LibraryFolder> folders) {
    final Map<String?, List<LibraryFolder>> groupedByParent = {};
    for (final folder in folders) {
      groupedByParent.putIfAbsent(folder.parentId, () => []).add(folder);
    }

    final List<LibraryFolder> sorted = [];

    void addFolders(String? parentId) {
      final children = groupedByParent[parentId] ?? [];
      // Sort children by orderIndex
      children.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
      for (final folder in children) {
        sorted.add(folder);
        addFolders(folder.id);
      }
    }

    addFolders(null);

    // Handle orphans (shouldn't happen with correct DB state but good for robustness)
    if (sorted.length < folders.length) {
      final sortedIds = sorted.map((f) => f.id).toSet();
      for (final folder in folders) {
        if (!sortedIds.contains(folder.id)) {
          sorted.add(folder);
        }
      }
    }

    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final foldersAsync = ref.watch(libraryFoldersStreamProvider);
    final sourceLabel = widget.sourceLabel ?? 'selection';

    final List<LibraryFolder> selectedFolders =
        foldersAsync.whenOrNull(
          data:
              (folders) =>
                  folders
                      .where((f) => _selectedFolderIds.contains(f.id))
                      .toList(),
        ) ??
        [];

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
                    'Add to My Library',
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
                    if (folders.isEmpty) {
                      return Padding(
                        padding: EdgeInsets.all(20.sp),
                        child: Text(
                          'No databases yet.',
                          style: AppTypography.textSmRegular.copyWith(
                            color: context.colors.textPrimary.withValues(alpha: 0.5),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      );
                    }
                    final sortedFolders = _sortFoldersHierarchically(folders);
                    return ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.symmetric(horizontal: 16.w),
                      itemCount: sortedFolders.length,
                      separatorBuilder: (_, __) => SizedBox(height: 8.h),
                      itemBuilder: (context, index) {
                        final folder = sortedFolders[index];
                        return _BulkFolderSelectionTile(
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
                            widget.games.isEmpty
                                ? null
                                : (_processedGames / widget.games.length).clamp(
                                  0,
                                  1,
                                ),
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      'Processed $_processedGames/${widget.games.length} · Saved $_savedEntries · Skipped $_skippedEntries · Failed $_failedGames',
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
                                    ? 'Add'
                                    : 'Add (${selectedFolders.length})',
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

class _BulkFolderSelectionTile extends StatelessWidget {
  const _BulkFolderSelectionTile({
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
                  : const Color(0xFF27272A),
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
