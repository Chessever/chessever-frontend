import 'package:chessever2/screens/chessboard/chess_board_screen.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_fen_model.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_widget.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/screens/tournaments/providers/chess_board_visibility_provider.dart';
import 'package:chessever2/screens/tournaments/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tournaments/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tournaments/widget/game_card.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GamesTourScreen extends ConsumerWidget {
  const GamesTourScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isChessBoardVisible = ref.watch(chessBoardVisibilityProvider);
    return GestureDetector(
      onTap: FocusScope.of(context).unfocus,
      child: RefreshIndicator(
        onRefresh: () async {
          FocusScope.of(context).unfocus();
          await ref.read(gamesTourScreenProvider.notifier).refreshGames();
        },
        color: kWhiteColor70,
        backgroundColor: kDarkGreyColor,
        displacement: 60.h,
        strokeWidth: 3.w,
        child: ref
            .watch(gamesAppBarProvider)
            .when(
              data: (_) {
                return ref
                    .watch(gamesTourScreenProvider)
                    .when(
                      data: (data) {
                        if (data.gamesTourModels.isEmpty) {
                          return EmptyWidget(
                            title:
                                "No games available yet. Check back soon or set a\nreminder for updates.",
                          );
                        }

                        return Column(
                          children: [
                            if (isChessBoardVisible)
                              Expanded(
                                child: ListView.builder(
                                  padding: EdgeInsets.only(
                                    left: 20.sp,
                                    right: 20.sp,
                                    top: 12.sp,
                                    bottom:
                                        MediaQuery.of(
                                          context,
                                        ).viewPadding.bottom,
                                  ),
                                  itemCount: data.gamesTourModels.length,
                                  itemBuilder: (cxt, index) {
                                    return ChessBoardFromFEN(
                                      chessBoardFenModel:
                                          ChessBoardFenModel.fromGamesTourModel(
                                            data.gamesTourModels[index],
                                          ),
                                    );
                                  },
                                ),
                              )
                            else
                              Expanded(
                                child: ListView.builder(
                                  padding: EdgeInsets.only(
                                    left: 20.sp,
                                    right: 20.sp,
                                    top: 12.sp,
                                    bottom:
                                        MediaQuery.of(
                                          context,
                                        ).viewPadding.bottom,
                                  ),
                                  itemCount: data.gamesTourModels.length,
                                  itemBuilder: (cxt, index) {
                                    final game = data.gamesTourModels[index];
                                    return Padding(
                                      padding: EdgeInsets.only(bottom: 12.sp),
                                      child: GameCard(
                                        onTap: () {
                                          if (data
                                                  .gamesTourModels[index]
                                                  .gameStatus
                                                  .displayText !=
                                              '*') {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder:
                                                    (_) => ChessBoardScreen(
                                                      data.gamesTourModels,
                                                      currentIndex: index,
                                                    ),
                                              ),
                                            );
                                          } else {
                                            showDialog(
                                              context: context,
                                              builder:
                                                  (_) => AlertDialog(
                                                    title: const Text(
                                                      "No PGN Data",
                                                    ),
                                                    content: const Text(
                                                      "This game has no PGN data available.",
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed:
                                                            () => Navigator.pop(
                                                              context,
                                                            ),
                                                        child: const Text("OK"),
                                                      ),
                                                    ],
                                                  ),
                                            );
                                          }
                                        },
                                        gamesTourModel: game,
                                        pinnedIds: data.pinnedGamedIs,
                                        onPinToggle: (gamesTourModel) async {
                                          await ref
                                              .read(
                                                gamesTourScreenProvider
                                                    .notifier,
                                              )
                                              .togglePinGame(
                                                gamesTourModel.gameId,
                                              );
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
                          ],
                        );
                      },
                      error: (_, __) => GenericErrorWidget(),
                      loading: () => _TourLoadingWidget(),
                    );
              },
              error: (_, __) => GenericErrorWidget(),
              loading: () => _TourLoadingWidget(),
            ),
      ),
    );
  }
}

class _TourLoadingWidget extends StatelessWidget {
  const _TourLoadingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final mockPlayer = PlayerCard(
      name: 'name',
      federation: 'federation',
      title: 'title',
      rating: 0,
      countryCode: 'USA',
    );
    final gamesTourModel = GamesTourModel(
      gameId: 'gameId',
      whitePlayer: mockPlayer,
      blackPlayer: mockPlayer,
      whiteTimeDisplay: 'whiteTimeDisplay',
      blackTimeDisplay: 'blackTimeDisplay',
      gameStatus: GameStatus.whiteWins,
    );

    final gamesTourModelList = List.generate(8, (_) => gamesTourModel);

    return ListView.builder(
      scrollDirection: Axis.vertical,
      padding: EdgeInsets.only(
        left: 20.sp,
        right: 20.sp,
        top: 12.sp,
        bottom: MediaQuery.of(context).viewPadding.bottom,
      ),
      shrinkWrap: true,
      itemCount: gamesTourModelList.length,
      itemBuilder: (cxt, index) {
        return SkeletonWidget(
          ignoreContainers: true,
          child: Padding(
            padding: EdgeInsets.only(bottom: 12.sp),
            child: GameCard(
              onTap: () {},
              gamesTourModel: gamesTourModelList[index],
              onPinToggle: (game) {},
              pinnedIds: [],
            ),
          ),
        );
      },
    );
  }
}

class EmptyWidget extends StatelessWidget {
  const EmptyWidget({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgWidget(SvgAsset.infoIcon, height: 24.h, width: 24.w),
        SizedBox(height: 12.h),
        Text(
          title,
          style: AppTypography.textXsRegular.copyWith(color: kWhiteColor70),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
