import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/chess_progress_bar.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:country_flags/country_flags.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';

class GroupEventMatchCard extends ConsumerStatefulWidget {
  final GamesAppBarModel round;
  final List<GamesTourModel> games;
  final GamesScreenModel gamesData;
  final Map<String, int> gameIndexMap;
  final GamesListViewMode gamesListViewMode;
  final void Function(int)? onReturnFromChessboard;

  const GroupEventMatchCard({
    super.key,
    required this.round,
    required this.games,
    required this.gamesData,
    required this.gameIndexMap,
    required this.gamesListViewMode,
    this.onReturnFromChessboard,
  });

  @override
  ConsumerState<GroupEventMatchCard> createState() =>
      _GroupEventMatchCardState();
}

class _GroupEventMatchCardState extends ConsumerState<GroupEventMatchCard>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late AnimationController _animationController;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _rotationAnimation = Tween<double>(begin: 0, end: 0.5).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final firstGame = widget.games.isNotEmpty ? widget.games.first : null;
    final country1Code = firstGame?.whitePlayer.countryCode ?? '';
    final country2Code = firstGame?.blackPlayer.countryCode ?? '';

    final country1Name = firstGame?.whitePlayer.countryCode ?? '';
    final country2Name = firstGame?.blackPlayer.countryCode ?? '';

    final teams = widget.round.name.split(' vs ');
    final team1Name =
        country1Name.isNotEmpty
            ? country1Name
            : (teams.isNotEmpty ? teams[0].trim() : '');
    final team2Name =
        country2Name.isNotEmpty
            ? country2Name
            : (teams.length > 1 ? teams[1].trim() : '');

    return Container(
      margin: EdgeInsets.only(bottom: 12.sp),
      decoration: BoxDecoration(
        color: Color(0xff1A1A1C).withValues(alpha: 0.7),
        borderRadius:
            _isExpanded
                ? BorderRadius.circular(4.0)
                : const BorderRadius.only(
                  topLeft: Radius.circular(4.0),
                  topRight: Radius.circular(4.0),
                ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: _toggleExpand,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 16.sp),
              child: Row(
                children: [
                  _buildCountryFlag(country1Code, team1Name),
                  SizedBox(width: 4.w),

                  Expanded(
                    child: Text(
                      team1Name,
                      style: AppTypography.textXsMedium.copyWith(
                        color: kWhiteColor,
                      ),
                    ),
                  ),

                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12.sp),
                    child: Text(
                      'VS',
                      style: AppTypography.textXsMedium.copyWith(
                        color: kWhiteColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  Expanded(
                    child: Text(
                      team2Name,
                      style: AppTypography.textXsMedium.copyWith(
                        color: kWhiteColor,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),

                  SizedBox(width: 4.w),

                  _buildCountryFlag(country2Code, team2Name),

                  SizedBox(width: 12.sp),

                  RotationTransition(
                    turns: _rotationAnimation,
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: kWhiteColor,
                      size: 20.sp,
                    ),
                  ),
                ],
              ),
            ),
          ),

          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: [
                Container(height: 10, color: Colors.black),
                SizedBox(height: 12.sp),
                _buildGamesList(),
              ],
            ),
            crossFadeState:
                _isExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
          ),
        ],
      ),
    );
  }

  Widget _buildGamesList() {
    switch (widget.gamesListViewMode) {
      case GamesListViewMode.gamesCard:
        return _buildGamesCardView();
      case GamesListViewMode.chessBoardGrid:
        return _buildChessBoardGridView();
      case GamesListViewMode.chessBoard:
        return _buildChessBoardView();
    }
  }

  Widget _buildGamesCardView() {
    return Column(
      children:
          widget.games.asMap().entries.map((entry) {
            final index = entry.key;
            final game = entry.value;

            return Column(
              children: [
                if (index > 0) SizedBox(height: 8.sp),
                _buildGameRow(game),
                Divider(height: 0.5, color: kDarkGreyColor),
              ],
            );
          }).toList(),
    );
  }

  Widget _buildChessBoardGridView() {
    final games = widget.games;
    final rows = <Widget>[];

    for (int i = 0; i < games.length; i += 2) {
      final game1 = games[i];
      final game2 = i + 1 < games.length ? games[i + 1] : null;

      rows.add(
        Padding(
          padding: EdgeInsets.only(bottom: 5.sp),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: _buildGridChessBoard(game1)),
              if (game2 != null) ...[
                SizedBox(width: 8.sp),
                Expanded(child: _buildGridChessBoard(game2)),
              ],
            ],
          ),
        ),
      );
    }

    return Column(children: rows);
  }

  Widget _buildChessBoardView() {
    return Column(
      children:
          widget.games.asMap().entries.map((entry) {
            final game = entry.value;
            final gameIndex = widget.gameIndexMap[game.gameId] ?? 0;

            return GameCardWrapperWidget(
              game: game,
              gamesData: widget.gamesData,
              gameIndex: gameIndex,
              isChessBoardVisible: true,
              onReturnFromChessboard: widget.onReturnFromChessboard,
            );
          }).toList(),
    );
  }

  Widget _buildGameRow(GamesTourModel game) {
    final gameIndex = widget.gameIndexMap[game.gameId] ?? 0;

    return InkWell(
      onTap:
          () => ref
              .read(gameCardWrapperProvider)
              .navigateToChessBoard(
                context: context,
                orderedGames: widget.gamesData.gamesTourModels,
                gameIndex: gameIndex,
                onReturnFromChessboard: widget.onReturnFromChessboard,
              ),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 12.sp),
        child: Row(
          children: [
            Expanded(
              child: Text(
                game.whitePlayer.name,
                style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(width: 12.sp),
            ChessProgressBar(gamesTourModel: game),
            SizedBox(width: 12.sp),
            Expanded(
              child: Text(
                game.blackPlayer.name,
                style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridChessBoard(GamesTourModel game) {
    final gameIndex = widget.gameIndexMap[game.gameId] ?? 0;

    return GridChessBoardFromFENNew(
      key: ValueKey('game_${game.gameId}'),
      gamesTourModel: game,
      onChanged:
          () => ref
              .read(gameCardWrapperProvider)
              .navigateToChessBoard(
                context: context,
                orderedGames: widget.gamesData.gamesTourModels,
                gameIndex: gameIndex,
                onReturnFromChessboard: widget.onReturnFromChessboard,
              ),
      pinnedIds: widget.gamesData.pinnedGamedIs,
      onPinToggle:
          (_) async => await ref
              .read(gamesTourScreenProvider.notifier)
              .togglePinGame(game.gameId),
    );
  }

  Widget _buildCountryFlag(String countryCode, String teamName) {
    final validCountryCode = ref
        .read(locationServiceProvider)
        .getValidCountryCode(countryCode);

    if (countryCode.toUpperCase() == 'FID') {
      return Image.asset(
        PngAsset.fideLogo,
        height: 12.h,
        width: 16.w,
        fit: BoxFit.cover,
        cacheWidth: 48,
        cacheHeight: 36,
      );
    } else {
      return CountryFlag.fromCountryCode(
        validCountryCode,
        height: 12.h,
        width: 16.w,
      );
    }
  }
}
