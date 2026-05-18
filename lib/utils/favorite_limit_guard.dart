import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/favorite_constants.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  // Fresh server-side count. Reading the realtime AsyncNotifier's cached
  // length lags after a just-completed INSERT and let users slip in extra
  // favorites without the paywall firing — same race that affected the
  // saved-games guard. The onboarding path passes currentSelectedCount
  // (local) and bypasses this query.
  final int currentCount;
  if (currentSelectedCount != null) {
    currentCount = currentSelectedCount;
  } else {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return false;
    currentCount = await supabase
        .from('user_favorite_players')
        .count(CountOption.exact)
        .eq('user_id', userId);
  }

  if (currentCount < kFreeFavoriteLimit) return true;

  if (!context.mounted) return false;
  return await showPremiumPaywallSheet(context: context);
}
