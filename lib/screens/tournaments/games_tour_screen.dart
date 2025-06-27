import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/screens/tournaments/providers/games_tour_screen_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/generic_loading_widget.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GamesTourScreen extends ConsumerWidget {
  const GamesTourScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(gamesTourScreenProvider)
        .when(
          data: (data) {
            if (data.isEmpty) {
              return EmptyWidget(
                title:
                    "No games available yet. Check back soon or set a\nreminder for updates.",
              );
            }
            return Expanded(
              child: ListView.builder(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 12,
                  bottom: MediaQuery.of(context).viewPadding.bottom,
                ),
                shrinkWrap: true,
                itemCount: data.length,
                itemBuilder: (cxt, index) {
                  return Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: _GameCard(gamesTourModel: data[index]),
                  );
                },
              ),
            );
          },
          error: (error, _) {
            return GenericErrorWidget();
          },
          loading: () {
            return GenericLoadingWidget();
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
        SvgWidget(SvgAsset.infoIcon, height: 24, width: 24),
        SizedBox(height: 12),
        Text(
          title,
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
                playerName: gamesTourModel.whitePlayer.name,
                playerRank: gamesTourModel.whitePlayer.displayTitle,
                countryCode: gamesTourModel.whitePlayer.countryCode,
              ),
              Spacer(),
              _ProgressWidget(progress: gamesTourModel.gameStatus.index / 100),
              Spacer(),
              _GamesRound(
                playerName: gamesTourModel.blackPlayer.name,
                playerRank: gamesTourModel.blackPlayer.displayTitle,
                countryCode: gamesTourModel.blackPlayer.countryCode,
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
              _TimerWidget(turn: true, time: gamesTourModel.whiteTimeDisplay),
              Spacer(),
              _TimerWidget(turn: false, time: gamesTourModel.blackTimeDisplay),
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
    required this.countryCode,
    super.key,
  });

  final String playerName;
  final String playerRank;
  final String countryCode;

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
        Row(
          children: [
            CountryFlag.fromCountryCode(countryCode, height: 12, width: 16),
            SizedBox(width: 4),
            Text(
              playerRank,
              style: AppTypography.textXsMedium.copyWith(color: kBlack2Color),
            ),
          ],
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
