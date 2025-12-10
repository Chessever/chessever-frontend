import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/premium_games/premium_games_screen.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Premium collection cards displayed at the top of For You tab.
/// Shows "Favorites" and "Countrymen" cards that navigate to premium game lists.
class PremiumCollectionCards extends ConsumerWidget {
  const PremiumCollectionCards({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscriptionState = ref.watch(subscriptionProvider);
    final isPremium = subscriptionState.isSubscribed;

    return Padding(
      padding: EdgeInsets.only(bottom: 20.sp),
      child: Row(
        children: [
          Expanded(
            child: _PremiumCollectionCard(
              type: PremiumGamesType.favorites,
              icon: Icons.star_rounded,
              title: 'Favorites',
              isPremium: isPremium,
            ),
          ),
          SizedBox(width: 12.sp),
          Expanded(
            child: _PremiumCollectionCard(
              type: PremiumGamesType.countrymen,
              icon: Icons.flag_rounded,
              title: 'Countrymen',
              isPremium: isPremium,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.05, end: 0);
  }
}

class _PremiumCollectionCard extends ConsumerWidget {
  const _PremiumCollectionCard({
    required this.type,
    required this.icon,
    required this.title,
    required this.isPremium,
  });

  final PremiumGamesType type;
  final IconData icon;
  final String title;
  final bool isPremium;

  // Distinct accent colors for each card type
  Color get _accentColor {
    return type == PremiumGamesType.favorites
        ? const Color(0xFFFFB800) // Golden amber for favorites
        : const Color(0xFF4CAF50); // Green for countrymen
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Get game count based on type
    final gameCount = _getGameCount(ref);
    final subtitle = _getSubtitle(ref);

    return GestureDetector(
      onTap: () => _handleTap(context, ref),
      child: Container(
        height: 108.sp,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              kBlack2Color,
              kBlack2Color.withValues(alpha: 0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(
            color: isPremium
                ? kPrimaryColor.withValues(alpha: 0.3)
                : kDarkGreyColor.withValues(alpha: 0.4),
            width: 1,
          ),
          boxShadow: isPremium
              ? [
                  BoxShadow(
                    color: kPrimaryColor.withValues(alpha: 0.1),
                    blurRadius: 12,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            // Background glow effect
            if (isPremium)
              Positioned(
                top: -20.sp,
                right: -20.sp,
                child: Container(
                  width: 60.sp,
                  height: 60.sp,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        kPrimaryColor.withValues(alpha: 0.15),
                        kPrimaryColor.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            // Content
            Padding(
              padding: EdgeInsets.all(14.sp),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32.sp,
                        height: 32.sp,
                        decoration: BoxDecoration(
                          color: _accentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8.br),
                        ),
                        child: Icon(
                          icon,
                          size: 18.ic,
                          color: _accentColor,
                        ),
                      ),
                      const Spacer(),
                      if (gameCount > 0)
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8.sp,
                            vertical: 3.sp,
                          ),
                          decoration: BoxDecoration(
                            color: isPremium
                                ? kPrimaryColor.withValues(alpha: 0.2)
                                : kWhiteColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6.br),
                          ),
                          child: Text(
                            '$gameCount',
                            style: AppTypography.textXsBold.copyWith(
                              color: isPremium
                                  ? kPrimaryColor
                                  : kWhiteColor.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTypography.textSmMedium.copyWith(
                          color: kWhiteColor,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: AppTypography.textXsRegular.copyWith(
                            color: kWhiteColor.withValues(alpha: 0.5),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _getGameCount(WidgetRef ref) {
    // This would ideally come from a provider that tracks counts
    // For now, return estimated counts based on data availability
    if (type == PremiumGamesType.favorites) {
      final favorites = ref.watch(favoritePlayersProviderNew).valueOrNull ?? [];
      return favorites.length * 3; // Rough estimate: 3 games per favorite
    } else {
      return 12; // Estimate for countrymen
    }
  }

  String? _getSubtitle(WidgetRef ref) {
    if (type == PremiumGamesType.favorites) {
      final favorites = ref.watch(favoritePlayersProviderNew).valueOrNull ?? [];
      if (favorites.isEmpty) return 'No favorites yet';
      if (favorites.length == 1) return favorites.first.playerName;
      return '${favorites.first.playerName} +${favorites.length - 1}';
    } else {
      final country = ref.watch(countryDropdownProvider).value;
      return country?.name ?? 'Select country';
    }
  }

  Future<void> _handleTap(BuildContext context, WidgetRef ref) async {
    HapticFeedbackService.cardTap();

    final isPremium = ref.read(subscriptionProvider).isSubscribed;

    if (!isPremium) {
      // Show paywall
      final subscribed = await showPremiumPaywallSheet(context: context);
      if (!subscribed) return;
    }

    // Navigate to premium games screen
    if (context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PremiumGamesScreen(type: type),
        ),
      );
    }
  }
}
