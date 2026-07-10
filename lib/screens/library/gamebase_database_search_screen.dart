import 'package:chessever2/repository/library/library_game_event.dart';
import 'package:chessever2/screens/library/providers/gamebase_database_search_provider.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/library/widgets/add_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/gamebase_search_game_card.dart';
import 'package:chessever2/screens/library/widgets/library_gamebase_filters_sheet.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/chess_title_utils.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/number_format_utils.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/liquid_glass/glass_back_button.dart';
import 'package:chessever2/widgets/liquid_glass/glass_full_screen_page.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_top_bar.dart';
import 'package:chessever2/widgets/liquid_glass/glass_island_stack.dart';
import 'package:chessever2/widgets/liquid_glass/glass_title_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

class GamebaseDatabaseSearchScreen extends ConsumerStatefulWidget {
  const GamebaseDatabaseSearchScreen({super.key});

  @override
  ConsumerState<GamebaseDatabaseSearchScreen> createState() =>
      _GamebaseDatabaseSearchScreenState();
}

class _GamebaseDatabaseSearchScreenState
    extends ConsumerState<GamebaseDatabaseSearchScreen> {
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _queryFocusNode = FocusNode();

  @override
  void dispose() {
    _queryController.dispose();
    _queryFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchAsync = ref.watch(gamebaseDatabaseSearchProvider);
    final state = searchAsync.valueOrNull;

    return GlassFullScreenPage(
      backgroundColor: context.colors.background,
      includeContentSafeArea: false,
      contentPadding: EdgeInsets.only(
        top: state == null ? 72 : 132,
        bottom: state == null ? 24 : 76,
      ),
      topOverlayPadding: const EdgeInsets.only(top: 4),
      bottomOverlayPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      topOverlay: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: GlassIslandStack(
            includeStatusBar: false,
            gap: 4,
            children: [
              GlassIslandTopBar(
                topPadding: 0,
                height: 48,
                leading: GlassBackButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(context).pop();
                  },
                ),
                title: const GlassTitleChip(label: 'ChessEver Database'),
              ),
              if (state != null)
                _SearchBar(
                  controller: _queryController,
                  focusNode: _queryFocusNode,
                  query: state.query,
                  hasActiveFilters: state.hasActiveFilters,
                  onChanged:
                      (value) => ref
                          .read(gamebaseDatabaseSearchProvider.notifier)
                          .setQuery(value),
                  onClear: () {
                    HapticFeedbackService.light();
                    _queryController.clear();
                    ref
                        .read(gamebaseDatabaseSearchProvider.notifier)
                        .setQuery('');
                    _queryFocusNode.unfocus();
                    setState(() {});
                  },
                  onFilterTap: _openFilters,
                ),
            ],
          ),
        ),
      ),
      bottomOverlay:
          state == null
              ? null
              : _PaginationBar(
                canGoPrev: state.canGoPrev,
                canGoNext: state.canGoNext,
                pageNumber: state.pagination.pageNumber,
                pageSize: state.pagination.pageSize,
                totalCount: state.pagination.totalCount,
                onPrev:
                    () =>
                        ref
                            .read(gamebaseDatabaseSearchProvider.notifier)
                            .prevPage(),
                onNext:
                    () =>
                        ref
                            .read(gamebaseDatabaseSearchProvider.notifier)
                            .nextPage(),
              ),
      content: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth:
                ResponsiveHelper.isTablet
                    ? ResponsiveHelper.contentMaxWidth
                    : double.infinity,
          ),
          child: searchAsync.when(
            loading:
                () => const Center(
                  child: CircularProgressIndicator(color: kPrimaryColor),
                ),
            error: (error, _) => _ErrorState(message: userFacingError(error)),
            data: (state) {
              return Column(
                children: [
                  _MetaRow(
                    state: state,
                    onRequestExactCount:
                        () =>
                            ref
                                .read(gamebaseDatabaseSearchProvider.notifier)
                                .requestExactCount(),
                  ),
                  Expanded(
                    child: _GamesList(
                      state: state,
                      onAdd: (game) => _showAddToFolderSheet(context, game),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _openFilters() async {
    HapticFeedbackService.buttonPress();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      constraints: ResponsiveHelper.bottomSheetConstraints,
      builder: (_) => const LibraryGamebaseFiltersSheet(),
    );
  }

  void _showAddToFolderSheet(BuildContext context, GamesTourModel game) {
    showAddToFolderSheet(context: context, game: game);
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.query,
    required this.hasActiveFilters,
    required this.onChanged,
    required this.onClear,
    required this.onFilterTap,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String query;
  final bool hasActiveFilters;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onFilterTap;

  @override
  Widget build(BuildContext context) {
    if (controller.text != query) {
      controller.text = query;
      controller.selection = TextSelection.fromPosition(
        TextPosition(offset: controller.text.length),
      );
    }

    final controlExtent = MediaQuery.textScalerOf(context).scale(16) + 32;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: GlassContainer(
        useOwnLayer: true,
        quality: GlassQuality.standard,
        height: controlExtent.clamp(52, 72),
        padding: EdgeInsets.only(left: 14.w),
        shape: LiquidRoundedSuperellipse(
          borderRadius: controlExtent.clamp(52, 72) / 2,
        ),
        child: Row(
          children: [
            Icon(Icons.search, color: context.colors.iconSecondary),
            SizedBox(width: 10.w),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                style: AppTypography.textSmRegular.copyWith(
                  color: context.colors.textPrimary,
                ),
                onChanged: onChanged,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search',
                  hintStyle: AppTypography.textSmRegular.copyWith(
                    color: context.colors.textPrimary.withValues(alpha: 0.5),
                  ),
                  border: InputBorder.none,
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              Semantics(
                button: true,
                label: 'Clear search',
                child: ExcludeSemantics(
                  child: IconButton(
                    onPressed: onClear,
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: 48,
                    ),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: context.colors.iconSecondary,
                    ),
                  ),
                ),
              ),
            Semantics(
              button: true,
              label: hasActiveFilters ? 'Filters active' : 'Filters',
              child: ExcludeSemantics(
                child: IconButton(
                  onPressed: onFilterTap,
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                  icon: Icon(
                    Icons.tune_rounded,
                    size: 20,
                    color:
                        hasActiveFilters
                            ? context.colors.brand
                            : context.colors.iconSecondary,
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

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.state, required this.onRequestExactCount});

  final GamebaseDatabaseSearchState state;
  final VoidCallback onRequestExactCount;

  @override
  Widget build(BuildContext context) {
    final estimated = state.pagination.totalCountIsEstimate;
    final subtitle =
        state.pagination.totalCount != null
            ? '${estimated ? '~' : ''}${formatCompactCount(state.pagination.totalCount!)} results'
            : 'Results';

    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 2.h, 16.w, 10.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  subtitle,
                  style: AppTypography.textSmMedium.copyWith(
                    color: context.colors.textPrimary.withValues(alpha: 0.7),
                  ),
                ),
              ),
              if (state.isQueryLoading)
                SizedBox(
                  width: 18.sp,
                  height: 18.sp,
                  child: const CircularProgressIndicator(
                    color: kPrimaryColor,
                    strokeWidth: 2,
                  ),
                ),
            ],
          ),
          if (estimated) ...[
            SizedBox(height: 4.h),
            GestureDetector(
              onTap: state.isQueryLoading ? null : onRequestExactCount,
              child: Text(
                'Exact count',
                style: AppTypography.textXsRegular.copyWith(
                  color: kPrimaryColor.withValues(
                    alpha: state.isQueryLoading ? 0.6 : 0.9,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GamesList extends ConsumerWidget {
  const _GamesList({required this.state, required this.onAdd});

  final GamebaseDatabaseSearchState state;
  final void Function(GamesTourModel game) onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final games = _rowsToGames(state.rows);

    if (state.lastQueryError != null) {
      return ListView(
        padding: EdgeInsets.fromLTRB(16.w, 48.h, 16.w, 24.h),
        children: [_InlineError(message: state.lastQueryError!)],
      );
    }

    return RefreshIndicator(
      onRefresh:
          () async =>
              ref.read(gamebaseDatabaseSearchProvider.notifier).refresh(),
      color: kPrimaryColor,
      backgroundColor: context.colors.surface,
      child:
          games.isEmpty
              ? ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(16.w, 48.h, 16.w, 24.h),
                children: const [_EmptyState()],
              )
              : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
                itemCount: games.length,
                separatorBuilder: (_, __) => SizedBox(height: 12.h),
                itemBuilder: (context, index) {
                  final game = games[index];
                  return GamebaseSearchGameCard(
                    game: game,
                    allGames: games,
                    gameIndex: index,
                    animationIndex: index,
                    onAdd: () => onAdd(game),
                    hideEventInfo: true,
                  );
                },
              ),
    );
  }

  static List<GamesTourModel> _rowsToGames(List<Map<String, dynamic>> rows) {
    return rows
        .map((row) {
          final id = (row['id']?.toString().trim());
          final safeId = (id != null && id.isNotEmpty) ? id : 'unknown';
          final result = row['result']?.toString() ?? '*';
          final timeControl = row['timeControl']?.toString();
          final date = _parseDate(row['date']);
          final eco = row['eco']?.toString() ?? '';
          final opening = row['opening']?.toString() ?? '';
          final variation = row['variation']?.toString() ?? '';
          final event = row['event']?.toString() ?? 'Gamebase';
          final site = row['site']?.toString();

          final whiteName =
              (row['white']?.toString() ?? row['whiteName']?.toString() ?? '')
                  .trim();
          final blackName =
              (row['black']?.toString() ?? row['blackName']?.toString() ?? '')
                  .trim();

          final pgn = buildHeaderOnlyPgn(
            whiteName: whiteName.isNotEmpty ? whiteName : 'White',
            blackName: blackName.isNotEmpty ? blackName : 'Black',
            result: result,
            event: event,
            site: site,
            date: date,
            eco: eco,
            opening: opening,
            variation: variation,
          );

          final whiteElo = (row['whiteElo'] as num?)?.toInt() ?? 0;
          final blackElo = (row['blackElo'] as num?)?.toInt() ?? 0;
          final whiteFed = row['whiteFed']?.toString() ?? '';
          final blackFed = row['blackFed']?.toString() ?? '';
          final whiteTitle = ChessTitleUtils.normalize(
            row['whiteTitle']?.toString(),
          );
          final blackTitle = ChessTitleUtils.normalize(
            row['blackTitle']?.toString(),
          );
          final whitePlayerId = row['whitePlayerId']?.toString().trim();
          final blackPlayerId = row['blackPlayerId']?.toString().trim();
          final whiteFideId = int.tryParse(
            row['whiteFideId']?.toString() ?? '',
          );
          final blackFideId = int.tryParse(
            row['blackFideId']?.toString() ?? '',
          );

          final whiteCard = PlayerCard(
            name: whiteName.isNotEmpty ? whiteName : 'White',
            federation: '',
            title: whiteTitle,
            rating: whiteElo,
            countryCode: whiteFed,
            team: null,
            fideId: whiteFideId,
            gamebasePlayerId:
                (whitePlayerId != null && whitePlayerId.isNotEmpty)
                    ? whitePlayerId
                    : null,
          );

          final blackCard = PlayerCard(
            name: blackName.isNotEmpty ? blackName : 'Black',
            federation: '',
            title: blackTitle,
            rating: blackElo,
            countryCode: blackFed,
            team: null,
            fideId: blackFideId,
            gamebasePlayerId:
                (blackPlayerId != null && blackPlayerId.isNotEmpty)
                    ? blackPlayerId
                    : null,
          );

          final rawTourId =
              (row['tour_id']?.toString() ??
                      row['tournament_id']?.toString() ??
                      '')
                  .trim();
          // Resolve the real tournament from the Site URL so broadcast
          // round/pairing Event headers never surface as the event label.
          final tourId = resolveGamebaseEventName(
            event: event,
            site: site,
            tourId: rawTourId.isNotEmpty ? rawTourId : null,
            whiteName: whiteName,
            blackName: blackName,
          );

          return GamesTourModel(
            gameId: safeId,
            source: GameSource.gamebase,
            whitePlayer: whiteCard,
            blackPlayer: blackCard,
            whiteTimeDisplay: '--:--',
            blackTimeDisplay: '--:--',
            whiteClockCentiseconds: 0,
            blackClockCentiseconds: 0,
            gameStatus: GameStatus.fromString(result),
            roundId: 'gamebase_search',
            roundSlug: eco.trim().isNotEmpty ? eco.trim() : timeControl,
            tourId: tourId.isNotEmpty ? tourId : 'Gamebase',
            timeControl: timeControl,
            pgn: pgn,
            lastMoveTime: date,
          );
        })
        .toList(growable: false);
  }

  static DateTime? _parseDate(Object? raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.canGoPrev,
    required this.canGoNext,
    required this.pageNumber,
    required this.pageSize,
    required this.totalCount,
    required this.onPrev,
    required this.onNext,
  });

  final bool canGoPrev;
  final bool canGoNext;
  final int pageNumber;
  final int pageSize;
  final int? totalCount;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final rightText =
        totalCount == null
            ? 'Page $pageNumber'
            : 'Page $pageNumber • $pageSize / ${formatCompactCount(totalCount!)}';

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: GlassContainer(
          useOwnLayer: true,
          quality: GlassQuality.standard,
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4),
          shape: const LiquidRoundedSuperellipse(borderRadius: 28),
          child: Row(
            children: [
              _IconPillButton(
                semanticLabel: 'Previous page',
                icon: Icons.chevron_left_rounded,
                onTap: canGoPrev ? onPrev : null,
              ),
              SizedBox(width: 4.w),
              _IconPillButton(
                semanticLabel: 'Next page',
                icon: Icons.chevron_right_rounded,
                onTap: canGoNext ? onNext : null,
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  rightText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textXsRegular.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconPillButton extends StatelessWidget {
  const _IconPillButton({
    required this.semanticLabel,
    required this.icon,
    required this.onTap,
  });

  final String semanticLabel;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: IconButton(
          onPressed: onTap,
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          icon: Icon(
            icon,
            color:
                enabled
                    ? context.colors.iconPrimary
                    : context.colors.iconSecondary.withValues(alpha: 0.45),
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 28.h),
        child: Column(
          children: [
            Icon(
              Icons.search_off_outlined,
              size: 56.sp,
              color: context.colors.textPrimary.withValues(alpha: 0.4),
            ),
            SizedBox(height: 12.h),
            Text(
              'No games found',
              style: AppTypography.textMdMedium.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.85),
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              'Try another query or filters.',
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.55),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(12.sp),
      decoration: BoxDecoration(
        color: kRedColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: kRedColor.withValues(alpha: 0.25)),
      ),
      child: Text(
        message,
        style: AppTypography.textSmRegular.copyWith(
          color: context.colors.textPrimary,
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.sp),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 56.sp,
              color: kRedColor.withValues(alpha: 0.85),
            ),
            SizedBox(height: 12.h),
            Text(
              'Something went wrong',
              style: AppTypography.textMdMedium.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              message,
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textPrimary.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
