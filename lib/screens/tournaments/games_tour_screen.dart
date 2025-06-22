import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';

class GamesTourScreen extends StatelessWidget {
  const GamesTourScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: SizedBox(),
          ),
          SizedBox(height: MediaQuery.of(context).viewPadding.bottom),
        ],
      ),
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
    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Column(
            children: [
              Text(
                playerName,
                style: AppTypography.textXsMedium.copyWith(color: kBlackColor),
              ),
              Row(
                children: [
                  // Text(CountryService().findByName(countryName)),
                  Text(
                    playerRank,
                    style: AppTypography.textXsMedium.copyWith(
                      color: kBlack2Color,
                    ),
                  ),
                ],
              ),
            ],
          ),
          _ProgressWidget(),
          Column(children: []),
        ],
      ),
    );
  }
}

class _ProgressWidget extends StatelessWidget {
  const _ProgressWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}
