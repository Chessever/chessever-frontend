import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart';
import 'package:chessever2/screens/my_likes/provider/my_likes_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// The one CTA the archive boundary carries. Specific on purpose: it names the
/// outcome (the history), never "unlimited likes", because liking is free.
const String kMyLikesHistoryCta = 'View full My Likes history';

/// The upgrade hand-off's feature id for anything behind the free window:
/// the boundary CTA and every older like opened from a locked card. A fixed
/// identifier for the paywall analytics, never user data.
const String kMyLikesHistoryFeatureId = 'my_likes_history';

/// The upgrade hand-off's feature id for exporting every like as PGN.
const String kMyLikesExportFeatureId = 'my_likes_export';

/// The surface My Likes gates resume on once the viewer is entitled.
const String kMyLikesReturnTo = 'my_likes';

/// Title and body for the boundary under a free user's latest likes.
({String title, String body}) myLikesArchiveCopy(MyLikesData data) {
  const limit = kFreeMyLikesVisibleLimit;

  // A search/filter that only hits the archive: say so instead of "no matches".
  final onlyArchiveMatches =
      data.isNarrowed && data.visibleCount == 0 && data.archivedMatchCount > 0;
  final title = onlyArchiveMatches
      ? 'No matches in your latest $limit likes'
      : "You're seeing your latest $limit likes";

  final String body;
  if (data.isNarrowed && data.archivedMatchCount > 0) {
    final n = data.archivedMatchCount;
    final too = data.visibleCount > 0 ? ' too' : '';
    if (!data.archivedMatchCountIsExact) {
      body =
          'More of your older likes match$too. '
          "They're kept safe and come back with Premium.";
    } else if (n == 1) {
      body =
          '1 older like matches$too. '
          "It's kept safe and comes back with Premium.";
    } else {
      body =
          '$n older likes match$too. '
          "They're kept safe and come back with Premium.";
    }
  } else {
    final n = data.archivedCount;
    body = n == 1
        ? 'Your 1 older like is kept safe and comes back with Premium.'
        : 'Your $n older likes are kept safe and come back with Premium.';
  }
  return (title: title, body: body);
}

/// Sits under a free user's latest [kFreeMyLikesVisibleLimit] likes: says how
/// many older likes are kept, and opens the paywall to bring them back.
///
/// The top-right corner is cut out as the shared For You lock notch
/// ([DiscoveryLockNotch]), so the card reads as a boundary rather than one more
/// game row.
class MyLikesArchiveBoundary extends StatelessWidget {
  const MyLikesArchiveBoundary({
    super.key,
    required this.data,
    required this.onViewHistory,
  });

  final MyLikesData data;
  final VoidCallback onViewHistory;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final copy = myLikesArchiveCopy(data);
    final notch = 28.w;

    return Semantics(
      container: true,
      label: 'Older likes',
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(16.w, 18.h, 16.w, 16.h),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(4.br),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Right inset clears the notch so the title is never cut.
                Padding(
                  padding: EdgeInsets.only(right: notch + 4.w),
                  child: Text(
                    copy.title,
                    style: AppTypography.textLgBold.copyWith(
                      color: colors.textPrimary,
                      height: 1.28,
                    ),
                  ),
                ),
                SizedBox(height: 6.h),
                Text(
                  copy.body,
                  style: AppTypography.textSmRegular.copyWith(
                    color: colors.textSecondary,
                    height: 1.42,
                  ),
                ),
                SizedBox(height: 16.h),
                _HistoryButton(onTap: onViewHistory),
              ],
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            // The same notch and padlock as every other For You lock.
            child: ExcludeSemantics(child: DiscoveryLockNotch(size: notch)),
          ),
        ],
      ),
    );
  }
}

/// Full-width brand CTA. The label wraps instead of overflowing, so large
/// text sizes never cut it.
class _HistoryButton extends StatelessWidget {
  const _HistoryButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: colors.brand,
        borderRadius: BorderRadius.circular(4.br),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: colors.inkOnAccent.withValues(alpha: 0.12),
          highlightColor: colors.inkOnAccent.withValues(alpha: 0.08),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: 48.h),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
              child: Center(
                child: Text(
                  kMyLikesHistoryCta,
                  textAlign: TextAlign.center,
                  style: AppTypography.textMdMedium.copyWith(
                    color: colors.inkOnAccent,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
