import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/library/widgets/bulk_add_to_folder_sheet.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:chessever2/screens/chessboard/widgets/smooth_sheet_config.dart';

Future<void> showSaveToLibrarySheet({
  required BuildContext context,
  required WidgetRef ref,
  required PlayerProfileKey playerKey,
  required VoidCallback onSelectSpecific,
}) async {
  final route = ChessSheetRoutes.commentEditor(
    context: context,
    builder:
        (_) => _SaveToLibrarySheet(
          playerKey: playerKey,
          onSelectSpecific: onSelectSpecific,
        ),
  );
  await Navigator.of(context).push(route);
}

class _SaveToLibrarySheet extends ConsumerStatefulWidget {
  const _SaveToLibrarySheet({
    required this.playerKey,
    required this.onSelectSpecific,
  });

  final PlayerProfileKey playerKey;
  final VoidCallback onSelectSpecific;

  @override
  ConsumerState<_SaveToLibrarySheet> createState() =>
      _SaveToLibrarySheetState();
}

class _SaveToLibrarySheetState extends ConsumerState<_SaveToLibrarySheet> {
  bool _isLoadingAll = false;

  Future<void> _handleSaveAll() async {
    if (_isLoadingAll) return;
    HapticFeedbackService.light();

    setState(() => _isLoadingAll = true);
    try {
      final state = ref.read(playerProfileGamesKeyProvider(widget.playerKey));
      final notifier = ref.read(
        playerProfileGamesKeyProvider(widget.playerKey).notifier,
      );

      if (widget.playerKey.source == PlayerProfileDataSource.twic &&
          state.hasMorePages) {
        await notifier.loadAllRemainingPages();
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
            backgroundColor: kBlack2Color.withValues(alpha: 0.95),
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

  void _handleSelectSpecific() {
    HapticFeedbackService.light();
    Navigator.of(context).pop();
    widget.onSelectSpecific();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerProfileGamesKeyProvider(widget.playerKey));
    final count = state.totalCount ?? state.filteredGames.length;

    return SheetKeyboardDismissible(
      dismissBehavior: const DragDownSheetKeyboardDismissBehavior(),
      child: PagedSheet(
        decoration: ChessSheetDecoration.dark(alpha: 0.97, borderRadius: 28.sp),
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
                                  color: kWhiteColor,
                                ),
                              ),
                              SizedBox(height: 6.h),
                              Text(
                                'Choose how you want to save ${widget.playerKey.playerName}\'s games.',
                                style: AppTypography.textSmRegular.copyWith(
                                  color: kWhiteColor.withValues(alpha: 0.7),
                                ),
                              ),
                              SizedBox(height: 24.h),
                              _ActionTile(
                                icon: Icons.all_inclusive_rounded,
                                title: 'Save all games',
                                subtitle: 'Add all $count games to a book',
                                isLoading: _isLoadingAll,
                                onTap: _handleSaveAll,
                              ),
                              SizedBox(height: 12.h),
                              _ActionTile(
                                icon: Icons.checklist_rounded,
                                title: 'Select specific games',
                                subtitle: 'Manually choose which games to save',
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
            color: kWhiteColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12.br),
            border: Border.all(color: kWhiteColor.withValues(alpha: 0.12)),
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
                        color: kWhiteColor,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      subtitle,
                      style: AppTypography.textXsRegular.copyWith(
                        color: kWhiteColor.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: kWhiteColor.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
