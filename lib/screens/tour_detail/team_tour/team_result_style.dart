import 'package:chessever2/screens/standings/team_standings_builder.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart' show kGreenColor2, kRedColor;
import 'package:flutter/material.dart';

const Color _drawGrey = Color(0xFF9AA0A6);

/// W/D/L colour induction, shared by the team standings card, the expandable
/// matchups, and the team score card: green win, grey draw, red loss.
Color teamResultColor(BuildContext context, TeamMatchResult result) =>
    switch (result) {
      TeamMatchResult.win => kGreenColor2,
      TeamMatchResult.draw => _drawGrey,
      TeamMatchResult.loss => kRedColor,
      TeamMatchResult.ongoing => context.colors.textTertiary,
    };

