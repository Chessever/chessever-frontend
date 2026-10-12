import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// The same portrait and three rating columns as the mobile player About tab.
class PrepIdentity extends StatelessWidget {
  const PrepIdentity({
    super.key,
    required this.profile,
    required this.onRating,
    this.chosen,
    this.source,
    this.accountKey,
    this.fideId,
    this.inset = true,
  });
  final PrepProfile profile;
  final PrepSource? source;
  final String? accountKey;
  final String? fideId;
  final bool inset;

  /// The clock the profile is narrowed to, whose column reads as taken.
  final PrepTimeControl? chosen;

  /// A tap on a clock's rating: it takes that clock, or gives it up.
  final ValueChanged<PrepTimeControl>? onRating;

  @override
  Widget build(BuildContext context) {
    final selected = profile.accounts
        .where((a) => a.key == accountKey)
        .firstOrNull;
    final account =
        selected ??
        (source == null
            ? profile.databaseAccount ?? profile.accounts.firstOrNull
            : profile.accounts.where((a) => a.source == source).firstOrNull);
    final online = account?.source.online ?? false;
    final clocks = online
        ? const [
            PrepTimeControl.bullet,
            PrepTimeControl.rapid,
            PrepTimeControl.blitz,
          ]
        : const [
            PrepTimeControl.classical,
            PrepTimeControl.rapid,
            PrepTimeControl.blitz,
          ];
    final gutter = inset
        ? ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w)
        : 0.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 12.h, gutter, 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PrepAvatar(
                name: profile.name,
                size: 110.w,
                fideId: profile.fideId ?? fideId,
                photoUrl: profile.avatarUrl,
                title: profile.title,
                borderRadius: 12.br,
              ),
              SizedBox(width: 16.w),
              Expanded(
                child: Row(
                  children: [
                    for (final (i, clock) in clocks.indexed) ...[
                      if (i > 0) SizedBox(width: 6.w),
                      Expanded(
                        child: _Rating(
                          clock: clock,
                          rating: account?.ratings[clock.name],
                          selected: clock == chosen,
                          // A clock without a rating has nothing to open,
                          // but one already taken can always be given up.
                          onTap:
                              onRating == null ||
                                  (clock != chosen &&
                                      !(account?.ratings.containsKey(
                                            clock.name,
                                          ) ??
                                          false))
                              ? null
                              : () {
                                  HapticFeedbackService.buttonPress();
                                  onRating!(clock);
                                },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A clock's rating. Taken as the choice it settles into the recessed
/// surface under a faint ring, as the rating cards of a player's profile do.
class _Rating extends StatelessWidget {
  const _Rating({
    required this.clock,
    this.rating,
    this.selected = false,
    this.onTap,
  });
  final PrepTimeControl clock;
  final int? rating;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(10.br);
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: '${clock.label} rating ${rating ?? 'not recorded'}',
      child: SingleMotionBuilder(
        motion: const CupertinoMotion.snappy(),
        value: selected ? 1.0 : 0.0,
        active: !MediaQuery.disableAnimationsOf(context),
        builder: (context, taken, _) {
          final t = taken.clamp(0.0, 1.0);
          return InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Container(
              constraints: BoxConstraints(minHeight: 110.w),
              padding: EdgeInsets.symmetric(horizontal: 3.sp, vertical: 9.sp),
              decoration: BoxDecoration(
                color: Color.lerp(colors.surface, colors.surfaceRecessed, t),
                borderRadius: radius,
              ),
              // Drawn over the column, so the ring takes no room from it.
              foregroundDecoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: colors.textPrimary.withValues(alpha: 0.22 * t),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PrepClockGlyph(clock, size: 20.w),
                  SizedBox(height: 5.h),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      clock.label,
                      style: AppTypography.textXsRegular.copyWith(
                        color: Color.lerp(
                          colors.textSecondary,
                          colors.textPrimary,
                          t,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 5.h),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      rating?.toString() ?? '–',
                      style: AppTypography.textLgBold.copyWith(
                        color: colors.textPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
