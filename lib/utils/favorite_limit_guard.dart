import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/favorite_constants.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Checks whether the user can add another favorite player.
///
/// For premium users (or debug mode), always returns `true`.
/// For free users at or above [kFreeFavoriteLimit]:
///   - [isOnboarding] = true  → shows a toast and returns `false`
///   - [isOnboarding] = false → shows the premium paywall and returns `false`
///
/// When [currentSelectedCount] is provided (e.g. during onboarding where
/// selections are local), it is used instead of the provider count.
Future<bool> canAddMoreFavorites(
  BuildContext context,
  WidgetRef ref, {
  bool isOnboarding = false,
  int? currentSelectedCount,
}) async {
  final isSubscribed = ref.read(subscriptionProvider).isSubscribed;

  if (isSubscribed) return true;

  final currentCount =
      currentSelectedCount ??
      (ref.read(favoritePlayersProviderNew).valueOrNull?.length ?? 0);

  if (currentCount < kFreeFavoriteLimit) return true;

  // At limit — block the add
  if (isOnboarding) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Subscribe to choose more favorites',
            style: AppTypography.textSmRegular.copyWith(color: kWhiteColor),
          ),
          backgroundColor: kBlack2Color.withValues(alpha: 0.95),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return false;
  }

  // Non-onboarding: show paywall
  if (!context.mounted) return false;
  return await showPremiumPaywallSheet(context: context);
}
