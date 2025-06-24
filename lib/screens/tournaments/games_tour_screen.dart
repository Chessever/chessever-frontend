import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/screens/tournaments/providers/games_tour_screen_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/generic_loading_widget.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GamesTourScreen extends ConsumerWidget {
  const GamesTourScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 12),
        ref
            .watch(gamesTourScreenProvider)
            .when(
              data: (data) {
                if (data.isEmpty) {
                  return _NoGamesFoundWidget();
                }
                return ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: data.length,
                  itemBuilder: (cxt, index) {
                    return _GameCard(gamesTourModel: data[index]);
                  },
                );
              },
              error: (error, _) {
                return GenericErrorWidget();
              },
              loading: () {
                return GenericLoadingWidget();
              },
            ),
        SizedBox(height: MediaQuery.of(context).viewPadding.bottom),
      ],
    );
  }
}

class _NoGamesFoundWidget extends StatelessWidget {
  const _NoGamesFoundWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgWidget(SvgAsset.infoIcon, height: 24, width: 24),
        SizedBox(height: 12),
        Text(
          "No games available yet. Check back soon or set a\nreminder for updates.",
          style: AppTypography.textXsRegular.copyWith(color: kWhiteColor70),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.gamesTourModel, super.key});

  final GamesTourModel gamesTourModel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 60,
          padding: EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: kWhiteColor70,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(12.0),
              topRight: Radius.circular(12.0),
            ),
          ),
          child: Row(
            children: [
              _GamesRound(
                playerName: 'Player 1',
                playerRank: 'Rank 1',
                countryName: 'Country 1',
              ),
              Spacer(),
              _ProgressWidget(progress: 0.5),
              Spacer(),
              _GamesRound(
                playerName: 'Player 2',
                playerRank: 'Rank 2',
                countryName: 'Country 2',
              ),
            ],
          ),
        ),
        Container(
          height: 24,
          padding: EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: kBlack2Color,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(12.0),
              bottomRight: Radius.circular(12.0),
            ),
          ),
          child: Row(
            children: [
              _TimerWidget(turn: true, time: '00 : 40'),
              Spacer(),
              _TimerWidget(turn: false, time: '1 : 40'),
            ],
          ),
        ),
      ],
    );
  }
}

class _GamesRound extends StatelessWidget {
  const _GamesRound({
    required this.playerName,
    required this.playerRank,
    required this.countryName,
    super.key,
  });

  final String playerName;
  final String playerRank;
  final String countryName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          playerName,
          style: AppTypography.textXsMedium.copyWith(color: kBlackColor),
        ),
        Text(
          playerRank,
          style: AppTypography.textXsMedium.copyWith(color: kBlack2Color),
        ),
      ],
    );
  }
}

class _ProgressWidget extends StatelessWidget {
  const _ProgressWidget({required this.progress, super.key});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 12,
      child: Stack(
        children: [
          // Background container
          Container(
            width: 48,
            height: 12.0,
            decoration: BoxDecoration(
              color: kBlack2Color,
              borderRadius: BorderRadius.all(Radius.circular(4)),
            ),
          ),
          // Progress container
          Container(
            width: 48 * progress, // 0.5 is the progress value
            height: 12.0,
            decoration: BoxDecoration(
              color: kWhiteColor,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(4),
                bottomLeft: Radius.circular(4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimerWidget extends StatelessWidget {
  const _TimerWidget({required this.turn, required this.time, super.key});

  final bool turn;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Text(
      time,
      style: AppTypography.textXsMedium.copyWith(
        color: turn ? kLightBlue : kWhiteColor,
      ),
    );
  }
}
