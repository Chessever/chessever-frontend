import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart'
    show prepGameRatings;
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
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
    this.accountKey,
    this.fideId,
    this.gameRatings = const {},
    this.inset = true,
  });
  final PrepProfile profile;
  final String? accountKey;
  final String? fideId;
  final bool inset;

  /// What the downloaded games say of each source's clocks, by games file
  /// ([prepGameRatings]): the rating a column shows where its source
  /// reports none, and the clocks there are games of to narrow to.
  final Map<String, Map<PrepTimeControl, int>> gameRatings;

  /// The clock the profile is narrowed to, whose column reads as taken.
  final PrepTimeControl? chosen;

  /// A tap on a clock's rating: it takes that clock, or gives it up.
  final ValueChanged<PrepTimeControl>? onRating;

  @override
  Widget build(BuildContext context) {
    final selected = profile.accounts
        .where((a) => a.key == accountKey)
        .firstOrNull;
    final main =
        selected ?? profile.databaseAccount ?? profile.accounts.firstOrNull;
    // One source read alone shows its own ratings. Read together, a clock
    // the main source has no rating for takes the next source's, in the
    // switch's order. A profile of several sources names whose every
    // rating is, read together or alone, so its columns never change shape.
    final readers = selected != null
        ? [selected]
        : [
            ?main,
            for (final source in PrepSource.values)
              ...profile.accounts.where(
                (a) => a.source == source && a.key != main?.key,
              ),
          ];
    final named = profile.accounts.length > 1;
    final played = {
      for (final account in readers)
        ...?gameRatings[PrepRepository.gamesFileName(account)]?.keys,
    };
    final online = main?.source.online ?? false;
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
                        child: _column(
                          clock,
                          prepClockRating(clock, readers, gameRatings),
                          named: named,
                          // A clock with neither a rating nor games has
                          // nothing to open, but one already taken can
                          // always be given up.
                          open: clock == chosen || played.contains(clock),
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

  Widget _column(
    PrepTimeControl clock,
    ({int rating, PrepSource source})? rated, {
    required bool named,
    required bool open,
  }) {
    final onRating = this.onRating;
    return _Rating(
      clock: clock,
      rating: rated?.rating,
      named: named,
      source: rated?.source,
      selected: clock == chosen,
      onTap: onRating == null || (rated == null && !open)
          ? null
          : () {
              HapticFeedbackService.buttonPress();
              onRating(clock);
            },
    );
  }
}

/// [clock]'s rating among [accounts], the first that has one: a source's
/// own figure, else the player's rating in its newest game of the clock
/// ([gameRatings], as [prepGameRatings] reads them). Null where none has.
({int rating, PrepSource source})? prepClockRating(
  PrepTimeControl clock,
  Iterable<PrepAccount> accounts,
  Map<String, Map<PrepTimeControl, int>> gameRatings,
) {
  for (final account in accounts) {
    final own = account.ratings[clock.name];
    if (own != null && own > 0) return (rating: own, source: account.source);
    final played =
        gameRatings[PrepRepository.gamesFileName(account)]?[clock] ?? 0;
    if (played > 0) return (rating: played, source: account.source);
  }
  return null;
}

/// A clock's rating. Taken as the choice it settles into the recessed
/// surface under a faint ring, as the rating cards of a player's profile do.
class _Rating extends StatelessWidget {
  const _Rating({
    required this.clock,
    this.rating,
    this.source,
    this.named = false,
    this.selected = false,
    this.onTap,
  });
  final PrepTimeControl clock;
  final int? rating;
  final PrepSource? source;

  /// Whether the figure names its [source], under it. A column without a
  /// rating keeps the room, so every column's figure stands at one height.
  final bool named;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(10.br);
    final mark = 16.sp;
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: [
        '${clock.label} rating ${rating ?? 'not recorded'}',
        if ((named && rating != null ? source : null) case final source?)
          'on ${source.label}',
      ].join(' '),
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
              // A named column holds one line more, and stays as tall as
              // the portrait beside it.
              padding: EdgeInsets.symmetric(
                horizontal: 3.sp,
                vertical: named ? 6.sp : 9.sp,
              ),
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
                  if (named) ...[
                    SizedBox(height: 4.h),
                    SizedBox.square(
                      dimension: mark,
                      child: switch ((rating, source)) {
                        (_?, final source?) => PrepSourceMark(
                          source: source,
                          size: mark,
                        ),
                        _ => null,
                      },
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
