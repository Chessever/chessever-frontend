import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';

class TourLoadingWidget extends StatelessWidget {
  const TourLoadingWidget({super.key});

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
      roundId: 'roundId',
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
