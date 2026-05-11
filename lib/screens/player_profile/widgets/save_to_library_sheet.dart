import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/library/widgets/bulk_add_to_folder_sheet.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/number_format_utils.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/save_to_library_guard.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:chessever2/screens/chessboard/widgets/smooth_sheet_config.dart';

Future<void> showSaveToLibrarySheet({
  required BuildContext context,
  required WidgetRef ref,
  required PlayerProfileKey playerKey,
  required VoidCallback onSelectSpecific,
  int? knownTotalCount,
}) async {
  final route = ChessSheetRoutes.commentEditor(
    context: context,
    builder:
        (_) => _SaveToLibrarySheet(
          playerKey: playerKey,
          onSelectSpecific: onSelectSpecific,
          knownTotalCount: knownTotalCount,
        ),
  );
  await Navigator.of(context).push(route);
}

class _SaveToLibrarySheet extends ConsumerStatefulWidget {
  const _SaveToLibrarySheet({
    required this.playerKey,
    required this.onSelectSpecific,
    this.knownTotalCount,
  });

  final PlayerProfileKey playerKey;
  final VoidCallback onSelectSpecific;
  final int? knownTotalCount;

  @override
  ConsumerState<_SaveToLibrarySheet> createState() =>
      _SaveToLibrarySheetState();
}

class _SaveToLibrarySheetState extends ConsumerState<_SaveToLibrarySheet> {
  bool _isLoadingAll = false;

  int _resolveBulkMaxPages(PlayerProfileGamesState state) {
    const defaultMaxPages = 250;
    const fallbackPageSize = 50;
    final totalCount = state.totalCount;
    if (totalCount == null || totalCount <= 0) return defaultMaxPages;
    final remaining = totalCount - state.allGames.length;
    if (remaining <= 0) return defaultMaxPages;
    final estimatedPages = (remaining / fallbackPageSize).ceil();
    final safeWithBuffer = estimatedPages + 10;
    return safeWithBuffer.clamp(defaultMaxPages, 5000);
  }

  Future<void> _handleSaveAll() async {
    if (_isLoadingAll) return;
    HapticFeedbackService.light();

    final initialState = ref.read(
      playerProfileGamesKeyProvider(widget.playerKey),
    );
    final totalCount =
        initialState.totalCount ?? initialState.filteredGames.length;
    final allowed = await canSaveMoreGames(context, gamesToAdd: totalCount);
    if (!allowed || !mounted) return;

    setState(() => _isLoadingAll = true);
    try {
      final notifier = ref.read(
        playerProfileGamesKeyProvider(widget.playerKey).notifier,
      );

      if (widget.playerKey.source == PlayerProfileDataSource.twic &&
          initialState.hasMorePages) {
        await notifier.loadAllRemainingPages(
          maxPages: _resolveBulkMaxPages(initialState),
        );
      }

      final refreshed = ref.read(
        playerProfileGamesKeyProvider(widget.playerKey),
      );
      final allGames = refreshed.filteredGames;

      if (!mounted) return;
      Navigator.of(context).pop();

      if (allGames.isNotEmpty) {
        showBulkAddToFolderSheet(
          context: context,
          games: allGames,
          sourceLabel: widget.playerKey.playerName,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No games found to save.'),
            backgroundColor: context.colors.surface.withValues(alpha: 0.95),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load all games: $e'),
          backgroundColor: kRedColor,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoadingAll = false);
    }
  }

  Future<void> _handleSelectSpecific() async {
    HapticFeedbackService.light();
    Navigator.of(context).pop();
    widget.onSelectSpecific();
  }

  String _buildSaveAllTitle(PlayerProfileGamesState state) {
    return state.hasActiveFilters ? 'Add all filtered games' : 'Add all games';
  }

  String _buildSaveAllSubtitle(PlayerProfileGamesState state) {
    final loaded = state.allGames.length;
    final isTwic = state.playerKey.source == PlayerProfileDataSource.twic;

    if (_isLoadingAll) {
      final total = state.totalCount ?? widget.knownTotalCount;
      if (total != null && total > loaded) {
        return 'Loading ${formatCompactCount(loaded)} of ${formatCompactCount(total)} games...';
      }
    }

    // When filters are active, use client-side filteredGames count — the
    // server totalCount doesn't reflect client-side filters like rating range.
    if (state.hasActiveFilters) {
      final filteredCount = state.filteredGames.length;
      if (isTwic && state.hasMorePages) {
        return '${formatCompactCount(filteredCount)}+ filtered games to a database';
      }
      return 'Add all ${formatCompactCount(filteredCount)} games to a database';
    }

    // No filters active — use server total for TWIC (most accurate)
    if (isTwic) {
      final total = state.totalCount ?? widget.knownTotalCount;
      if (total != null && total > 0) {
        return 'Add all ${formatCompactCount(total)} games to a database';
      }
    }

    final count = state.filteredGames.length;
    return 'Add all ${formatCompactCount(count)} games to a database';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerProfileGamesKeyProvider(widget.playerKey));

    return SheetKeyboardDismissible(
      dismissBehavior: const DragDownSheetKeyboardDismissBehavior(),
      child: PagedSheet(
        decoration: ChessSheetDecoration.dark(context, alpha: 0.97, borderRadius: 28.sp),
        shrinkChildToAvoidDynamicOverlap: true,
        navigator: Navigator(
          onGenerateInitialRoutes:
              (_, __) => [
                SpringPagedSheetRoute(
                  scrollConfiguration: const SheetScrollConfiguration(),
                  dragConfiguration: ChessSheetConfigs.commentEditor,
                  initialOffset: const SheetOffset.proportionalToViewport(0.55),
                  snapGrid: SheetSnapGrid(
                    snaps: const [SheetOffset.proportionalToViewport(0.55)],
                    minFlingSpeed: 600.0,
                  ),
                  builder:
                      (context) => Material(
                        type: MaterialType.transparency,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: 24.h,
                            horizontal: 20.w,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Save to Library',
                                style: AppTypography.textLgBold.copyWith(
                                  color: context.colors.textPrimary,
                                ),
                              ),
                              SizedBox(height: 6.h),
                              Text(
                                'Choose how you want to save ${widget.playerKey.playerName}\'s games.',
                                style: AppTypography.textSmRegular.copyWith(
                                  color: context.colors.textPrimary.withValues(alpha: 0.7),
                                ),
                              ),
                              SizedBox(height: 24.h),
                              _ActionTile(
                                icon: Icons.all_inclusive_rounded,
                                title: _buildSaveAllTitle(state),
                                subtitle: _buildSaveAllSubtitle(state),
                                isLoading: _isLoadingAll,
                                onTap: _handleSaveAll,
                              ),
                              SizedBox(height: 12.h),
                              _ActionTile(
                                icon: Icons.checklist_rounded,
                                title: 'Choose games manually',
                                subtitle: 'Open selection mode in Games tab',
                                onTap: _handleSelectSpecific,
                              ),
                              SizedBox(
                                height:
                                    MediaQuery.of(context).viewPadding.bottom +
                                    10.h,
                              ),
                            ],
                          ),
                        ),
                      ),
                ),
              ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isLoading;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Opacity(
        opacity: isLoading ? 0.6 : 1.0,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
          decoration: BoxDecoration(
            color: context.colors.textPrimary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12.br),
            border: Border.all(color: context.colors.textPrimary.withValues(alpha: 0.12)),
          ),
          child: Row(
            children: [
              Container(
                width: 40.w,
                height: 40.h,
                decoration: BoxDecoration(
                  color: kPrimaryColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child:
                    isLoading
                        ? Padding(
                          padding: EdgeInsets.all(12.sp),
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                            color: kPrimaryColor,
                          ),
                        )
                        : Icon(icon, color: kPrimaryColor, size: 20.sp),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.textSmMedium.copyWith(
                        color: context.colors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      subtitle,
                      style: AppTypography.textXsRegular.copyWith(
                        color: context.colors.textPrimary.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: context.colors.textPrimary.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
