import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/library/providers/gamebase_player_games_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GamebasePlayerGamesScreen extends ConsumerStatefulWidget {
  final GamebasePlayer player;

  const GamebasePlayerGamesScreen({super.key, required this.player});

  @override
  ConsumerState<GamebasePlayerGamesScreen> createState() =>
      _GamebasePlayerGamesScreenState();
}

class _GamebasePlayerGamesScreenState
    extends ConsumerState<GamebasePlayerGamesScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref
          .read(gamebasePlayerGamesProvider(widget.player).notifier)
          .loadMoreGames();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gamebasePlayerGamesProvider(widget.player));

    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        backgroundColor: kBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: kWhiteColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.player.title != null &&
                    widget.player.title!.isNotEmpty) ...[
                  Text(
                    widget.player.title!,
                    style: AppTypography.textSmBold.copyWith(
                      color: const Color(0xFFA1A1AA), // Zinc 400
                    ),
                  ),
                  SizedBox(width: 6.w),
                ],
                Flexible(
                  child: Text(
                    widget.player.name,
                    style: AppTypography.textMdBold.copyWith(
                      color: kWhiteColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (widget.player.fed != null) ...[
              SizedBox(height: 2.h),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CountryFlag.fromCountryCode(
                    widget.player.fed!,
                    width: 16.w,
                    height: 12.h,
                  ),
                  SizedBox(width: 6.w),
                  Text(
                    widget.player.fed!,
                    style: AppTypography.textXsRegular.copyWith(
                      color: const Color(0xFFA1A1AA),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        centerTitle: false,
      ),
      body: _buildBody(state),
    );
  }

  Widget _buildBody(GamebasePlayerGamesState state) {
    if (state.isLoading && state.groupedGames.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: kWhiteColor),
      );
    }

    if (state.error != null && state.groupedGames.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: kRedColor, size: 48.sp),
            SizedBox(height: 16.h),
            Text(
              'Failed to load games',
              style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
            ),
            SizedBox(height: 8.h),
            TextButton(
              onPressed: () => ref
                  .read(gamebasePlayerGamesProvider(widget.player).notifier)
                  .refreshGames(),
              child: Text(
                'Retry',
                style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
              ),
            ),
          ],
        ),
      );
    }

    if (state.groupedGames.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.sports_esports_outlined,
              color: const Color(0xFFA1A1AA),
              size: 48.sp,
            ),
            SizedBox(height: 16.h),
            Text(
              'No games found',
              style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
            ),
            SizedBox(height: 4.h),
            Text(
              'This player has no recorded games',
              style: AppTypography.textSmRegular.copyWith(
                color: const Color(0xFFA1A1AA),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref
          .read(gamebasePlayerGamesProvider(widget.player).notifier)
          .refreshGames(),
      color: kWhiteColor,
      backgroundColor: kBlack2Color,
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        itemCount: state.groupedGames.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.groupedGames.length) {
            return Padding(
              padding: EdgeInsets.symmetric(vertical: 24.h),
              child: const Center(
                child: CircularProgressIndicator(color: kWhiteColor),
              ),
            );
          }

          final group = state.groupedGames[index];
          return _TournamentGamesSection(
            group: group,
            allGames: state.allGames,
            onGameTap: _onGameTap,
          );
        },
      ),
    );
  }

  void _onGameTap(GamesTourModel game, List<GamesTourModel> allGames) {
    final index = allGames.indexWhere((g) => g.gameId == game.gameId);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChessBoardScreenNew(
          games: allGames,
          currentIndex: index >= 0 ? index : 0,
          showGamebaseButton: true,
        ),
      ),
    );
  }
}

class _TournamentGamesSection extends StatelessWidget {
  final TournamentGamesGroup group;
  final List<GamesTourModel> allGames;
  final Function(GamesTourModel, List<GamesTourModel>) onGameTap;

  const _TournamentGamesSection({
    required this.group,
    required this.allGames,
    required this.onGameTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 16.h, bottom: 12.h),
          child: Row(
            children: [
              Icon(
                Icons.emoji_events_outlined,
                color: const Color(0xFFA1A1AA), // Zinc 400
                size: 18.sp,
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  group.tourName,
                  style: AppTypography.textSmBold.copyWith(color: kWhiteColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: const Color(0xFF27272A),
                  borderRadius: BorderRadius.circular(12.br),
                ),
                child: Text(
                  '${group.games.length}',
                  style: AppTypography.textXsMedium.copyWith(
                    color: const Color(0xFFA1A1AA),
                  ),
                ),
              ),
            ],
          ),
        ),
        ...group.games.asMap().entries.map((entry) {
          final game = entry.value;
          return Padding(
            padding: EdgeInsets.only(bottom: 12.h),
            child: _PlayerGameCard(
              game: game,
              onTap: () => onGameTap(game, allGames),
            ),
          );
        }),
      ],
    );
  }
}

class _PlayerGameCard extends StatelessWidget {
  final GamesTourModel game;
  final VoidCallback onTap;

  const _PlayerGameCard({
    required this.game,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF252525),
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(color: kWhiteColor.withValues(alpha: 0.05)),
        ),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(12.sp),
              child: Row(
                children: [
                  // White player
                  Expanded(
                    child: _PlayerInfo(
                      player: game.whitePlayer,
                      isWhite: true,
                    ),
                  ),
                  // Result badge
                  _ResultBadge(status: game.effectiveGameStatus),
                  // Black player
                  Expanded(
                    child: _PlayerInfo(
                      player: game.blackPlayer,
                      isWhite: false,
                    ),
                  ),
                ],
              ),
            ),
            // Meta row
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(12.br),
                  bottomRight: Radius.circular(12.br),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 14.sp,
                    color: const Color(0xFFA1A1AA),
                  ),
                  SizedBox(width: 4.w),
                  Expanded(
                    child: Text(
                      game.tourId,
                      style: AppTypography.textXsRegular.copyWith(
                        color: const Color(0xFFA1A1AA),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (game.lastMoveTime != null) ...[
                    SizedBox(width: 8.w),
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 12.sp,
                      color: const Color(0xFF71717A),
                    ),
                    SizedBox(width: 4.w),
                    Text(
                      _formatDate(game.lastMoveTime!),
                      style: AppTypography.textXsRegular.copyWith(
                        color: const Color(0xFF71717A),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

class _PlayerInfo extends StatelessWidget {
  final PlayerCard player;
  final bool isWhite;

  const _PlayerInfo({
    required this.player,
    required this.isWhite,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          isWhite ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isWhite) ...[
              Container(
                width: 12.sp,
                height: 12.sp,
                decoration: BoxDecoration(
                  color: kWhiteColor,
                  borderRadius: BorderRadius.circular(2.br),
                  border: Border.all(color: const Color(0xFF71717A), width: 0.5),
                ),
              ),
              SizedBox(width: 6.w),
            ],
            if (player.title.isNotEmpty) ...[
              Text(
                player.title,
                style: AppTypography.textXsBold.copyWith(
                  color: const Color(0xFFA1A1AA), // Zinc 400
                ),
              ),
              SizedBox(width: 4.w),
            ],
            Flexible(
              child: Text(
                player.name,
                style: AppTypography.textSmMedium.copyWith(
                  color: kWhiteColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: isWhite ? TextAlign.left : TextAlign.right,
              ),
            ),
            if (!isWhite) ...[
              SizedBox(width: 6.w),
              Container(
                width: 12.sp,
                height: 12.sp,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(2.br),
                  border: Border.all(color: const Color(0xFF71717A), width: 0.5),
                ),
              ),
            ],
          ],
        ),
        SizedBox(height: 4.h),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isWhite && player.countryCode.isNotEmpty) ...[
              CountryFlag.fromCountryCode(
                player.countryCode,
                width: 14.w,
                height: 10.h,
              ),
              SizedBox(width: 4.w),
            ],
            if (player.rating > 0)
              Text(
                '${player.rating}',
                style: AppTypography.textXsRegular.copyWith(
                  color: const Color(0xFFA1A1AA),
                ),
              ),
            if (!isWhite && player.countryCode.isNotEmpty) ...[
              SizedBox(width: 4.w),
              CountryFlag.fromCountryCode(
                player.countryCode,
                width: 14.w,
                height: 10.h,
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _ResultBadge extends StatelessWidget {
  final GameStatus status;

  const _ResultBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 12.w),
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: _getBgColor(),
        borderRadius: BorderRadius.circular(8.br),
      ),
      child: Text(
        _getResultText(),
        style: AppTypography.textXsBold.copyWith(
          color: _getTextColor(),
        ),
      ),
    );
  }

  String _getResultText() {
    switch (status) {
      case GameStatus.whiteWins:
        return '1-0';
      case GameStatus.blackWins:
        return '0-1';
      case GameStatus.draw:
        return '½-½';
      default:
        return '*';
    }
  }

  Color _getBgColor() {
    switch (status) {
      case GameStatus.whiteWins:
        return const Color(0xFF1A3A1A);
      case GameStatus.blackWins:
        return const Color(0xFF3A1A1A);
      case GameStatus.draw:
        return const Color(0xFF2A2A2A);
      default:
        return const Color(0xFF2A2A2A);
    }
  }

  Color _getTextColor() {
    switch (status) {
      case GameStatus.whiteWins:
        return const Color(0xFF4ADE80);
      case GameStatus.blackWins:
        return const Color(0xFFF87171);
      case GameStatus.draw:
        return const Color(0xFFA1A1AA);
      default:
        return const Color(0xFFA1A1AA);
    }
  }
}
