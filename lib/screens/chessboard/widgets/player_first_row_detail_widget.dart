import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';

class PlayerFirstRowDetailWidget extends StatelessWidget {
  final String name;
  final String firstGmRank;
  final String time;
  final String countryCode;

  const PlayerFirstRowDetailWidget({
    super.key,
    required this.name,
    required this.firstGmRank,
    required this.time,
    required this.countryCode,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CountryFlag.fromCountryCode(countryCode, height: 12.h, width: 16.w),
        SizedBox(width: 8.w),
        Expanded(
          child: Text(
            '$name $firstGmRank',
            style: AppTypography.textXsMedium.copyWith(
              color: kWhiteColor70,
              fontSize: 9.f,
            ),
          ),
        ),
        Text(
          time,
          style: AppTypography.textXsMedium.copyWith(
            color: kWhiteColor70,
            fontSize: 9.f,
          ),
        ),
      ],
    );
  }
}
