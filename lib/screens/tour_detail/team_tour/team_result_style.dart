import 'package:chessever2/screens/standings/team_standings_builder.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart' show kRedColor;
import 'package:flutter/material.dart';

const Color _drawGrey = Color(0xFF9AA0A6);

/// W/D/L colour induction, shared by the team standings card, the expandable
/// matchups, and the team score card: brand/primary win (matches Games-tab
/// winning scores), grey draw, red loss.
Color teamResultColor(BuildContext context, TeamMatchResult result) =>
    switch (result) {
      TeamMatchResult.win => context.colors.brand,
      TeamMatchResult.draw => _drawGrey,
      TeamMatchResult.loss => kRedColor,
      TeamMatchResult.ongoing => context.colors.textTertiary,
    };

/// Win / positive result color for team UI (W counts, winning match scores).
/// Prefer [context.colors.brand] at call sites that already have a BuildContext.
Color teamWinColor(BuildContext context) => context.colors.brand;

