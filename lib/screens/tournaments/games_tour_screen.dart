import 'package:chessever2/screens/chessboard/chess_board_screen.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_widget.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/screens/tournaments/providers/chess_board_visibility_provider.dart';
import 'package:chessever2/screens/tournaments/providers/game_fen_stream_provider.dart';
import 'package:chessever2/screens/tournaments/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tournaments/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tournaments/widget/empty_widget.dart';
import 'package:chessever2/screens/tournaments/widget/game_card.dart';
import 'package:chessever2/screens/tournaments/widget/tour_loading_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
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

                        return ListView.builder(
                          padding: EdgeInsets.only(
                            left: 20.sp,
                            right: 20.sp,
                            top: 12.sp,
                            bottom: MediaQuery.of(context).viewPadding.bottom,
                          ),
                          itemCount: data.gamesTourModels.length,
                          itemBuilder: (context, index) {
                            var gamesTourModel = data.gamesTourModels[index];

                            // Update game with live FEN if ongoing
                            if (gamesTourModel.gameStatus ==
                                GameStatus.ongoing) {
                              ref
                                  .watch(
                                    gameFenStreamProvider(
                                      gamesTourModel.gameId,
                                    ),
                                  )
                                  .whenOrNull(
                                    data: (fen) {
                                      if (fen != null) {
                                        gamesTourModel = gamesTourModel
                                            .copyWith(fen: fen);
                                      }
                                    },
                                  );
                            }

                            return Padding(
                              padding: EdgeInsets.only(bottom: 12.sp),
                              child:
                                  isChessBoardVisible
                                      ? ChessBoardFromFEN(
                                        gamesTourModel: gamesTourModel,
                                        onChanged: () {
                                          ref
                                              .read(
                                                chessboardViewFromProvider
                                                    .notifier,
                                              )
                                              .state = ChessboardView.tour;
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder:
                                                  (_) => ChessBoardScreen(
                                                    games: data.gamesTourModels,
                                                    currentIndex: index,
                                                  ),
                                            ),
                                          );
                                        },
                                      )
                                      : GameCard(
                                        onTap: () {
                                          ref
                                              .read(
                                                chessboardViewFromProvider
                                                    .notifier,
                                              )
                                              .state = ChessboardView.tour;
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder:
                                                  (_) => ChessBoardScreen(
                                                    games: data.gamesTourModels,
                                                    currentIndex: index,
                                                  ),
                                            ),
                                          );
                                        },
                                        gamesTourModel: gamesTourModel,
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
                        );
                      },
                      error: (_, __) => GenericErrorWidget(),
                      loading: () => TourLoadingWidget(),
                    );
              },
              error: (_, __) => GenericErrorWidget(),
              loading: () => TourLoadingWidget(),
            ),
      ),
    );
  }
}
