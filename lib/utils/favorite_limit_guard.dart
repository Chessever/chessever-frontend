import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/favorite_constants.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Checks whether the user can add another favorite player.
///
/// Onboarding enforces a hard cap of [kFreeFavoriteLimit] with a friendly
/// "add more after signing in" toast — never a paywall, because there's no
/// account yet. In-app, premium bypasses the cap and free users get the
/// paywall at the limit.
///
/// When [currentSelectedCount] is provided (e.g. during onboarding where
/// selections are local), it is used instead of the provider count.
Future<bool> canAddMoreFavorites(
  BuildContext context,
  WidgetRef ref, {
  bool isOnboarding = false,
  int? currentSelectedCount,
}) async {
  if (isOnboarding) {
    final currentCount = currentSelectedCount ?? 0;
    if (currentCount < kFreeFavoriteLimit) return true;

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You can follow more players after signing in',
            style: AppTypography.textSmRegular.copyWith(color: context.colors.textPrimary),
          ),
          backgroundColor: context.colors.surface.withValues(alpha: 0.95),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return false;
  }

  final isSubscribed = ref.read(subscriptionProvider).isSubscribed;
  if (isSubscribed) return true;

  final currentCount =
      currentSelectedCount ??
      (ref.read(favoritePlayersProviderNew).valueOrNull?.length ?? 0);

  if (currentCount < kFreeFavoriteLimit) return true;

  if (!context.mounted) return false;
  return await showPremiumPaywallSheet(context: context);
}
