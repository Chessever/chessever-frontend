import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// The same portrait and three rating columns as the mobile player About tab.
class PrepIdentity extends StatelessWidget {
  const PrepIdentity({
    super.key,
    required this.profile,
    required this.onRating,
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
  final void Function(PrepAccount account, PrepTimeControl speed) onRating;

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
                          onTap:
                              account == null ||
                                  !account.ratings.containsKey(clock.name)
                              ? null
                              : () => onRating(account, clock),
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

class _Rating extends StatelessWidget {
  const _Rating({required this.clock, this.rating, this.onTap});
  final PrepTimeControl clock;
  final int? rating;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: '${clock.label} rating ${rating ?? 'not recorded'}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10.br),
        child: Container(
          constraints: BoxConstraints(minHeight: 110.w),
          padding: EdgeInsets.symmetric(horizontal: 3.sp, vertical: 9.sp),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(10.br),
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
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
              SizedBox(height: 5.h),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  rating?.toString() ?? '–',
                  style: AppTypography.textLgBold.copyWith(
                    color: context.colors.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
