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
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        leading: IconButton(
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop();
          },
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: context.colors.textPrimary,
          ),
        ),
        title: Text(
          'ChessEver Database',
          style: AppTypography.textLgBold.copyWith(color: context.colors.textPrimary),
        ),
      ),
      body: Center(
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
                  _PaginationBar(
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

    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 6.h),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(color: context.colors.textPrimary.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Icon(Icons.search, color: context.colors.textPrimary.withValues(alpha: 0.7)),
            SizedBox(width: 10.w),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                style: AppTypography.textSmRegular.copyWith(color: context.colors.textPrimary),
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
              GestureDetector(
                onTap: onClear,
                child: Container(
                  padding: EdgeInsets.all(6.sp),
                  decoration: BoxDecoration(
                    color: context.colors.textPrimary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.close,
                    size: 14.sp,
                    color: context.colors.textPrimary.withValues(alpha: 0.7),
                  ),
                ),
              ),
            SizedBox(width: 10.w),
            GestureDetector(
              onTap: onFilterTap,
              child: Container(
                padding: EdgeInsets.all(8.sp),
                decoration: BoxDecoration(
                  color:
                      hasActiveFilters
                          ? kPrimaryColor.withValues(alpha: 0.2)
                          : context.colors.textPrimary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10.br),
                  border: Border.all(
                    color:
                        hasActiveFilters
                            ? kPrimaryColor.withValues(alpha: 0.55)
                            : context.colors.textPrimary.withValues(alpha: 0.08),
                  ),
                ),
                child: Icon(
                  Icons.tune_rounded,
                  size: 18.ic,
                  color: hasActiveFilters ? kPrimaryColor : context.colors.textPrimary,
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

    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 10.h),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(
          top: BorderSide(color: context.colors.textPrimary.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          _IconPillButton(
            icon: Icons.chevron_left_rounded,
            onTap: canGoPrev ? onPrev : null,
          ),
          SizedBox(width: 10.w),
          _IconPillButton(
            icon: Icons.chevron_right_rounded,
            onTap: canGoNext ? onNext : null,
          ),
          const Spacer(),
          Text(
            rightText,
            style: AppTypography.textXsRegular.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconPillButton extends StatelessWidget {
  const _IconPillButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44.w,
        height: 36.h,
        decoration: BoxDecoration(
          color: context.colors.surfaceRecessed,
          borderRadius: BorderRadius.circular(10.br),
          border: Border.all(
            color:
                enabled
                    ? context.colors.textPrimary.withValues(alpha: 0.12)
                    : context.colors.textPrimary.withValues(alpha: 0.06),
          ),
        ),
        child: Icon(
          icon,
          color:
              enabled
                  ? context.colors.textPrimary.withValues(alpha: 0.9)
                  : context.colors.textPrimary.withValues(alpha: 0.35),
          size: 22.ic,
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
        style: AppTypography.textSmRegular.copyWith(color: context.colors.textPrimary),
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
              style: AppTypography.textMdMedium.copyWith(color: context.colors.textPrimary),
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
