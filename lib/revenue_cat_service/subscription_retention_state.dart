import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final subscriptionRetentionGraceProvider =
    FutureProvider<SubscriptionRetentionGrace?>((ref) async {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      if (userId == null) return null;

      final rows = await client
          .from('user_subscription_retention_grace')
          .select(
            'expired_at, favorite_cleanup_after, database_cleanup_after, '
            'favorite_trimmed_at, database_trimmed_at',
          )
          .eq('user_id', userId)
          .limit(1);

      if (rows.isEmpty) return null;
      return SubscriptionRetentionGrace.fromJson(rows.first);
    });

@immutable
class SubscriptionRetentionGrace {
  const SubscriptionRetentionGrace({
    required this.expiredAt,
    required this.favoriteCleanupAfter,
    required this.databaseCleanupAfter,
    this.favoriteTrimmedAt,
    this.databaseTrimmedAt,
  });

  final DateTime expiredAt;
  final DateTime favoriteCleanupAfter;
  final DateTime databaseCleanupAfter;
  final DateTime? favoriteTrimmedAt;
  final DateTime? databaseTrimmedAt;

  factory SubscriptionRetentionGrace.fromJson(Map<String, dynamic> json) {
    return SubscriptionRetentionGrace(
      expiredAt: DateTime.parse(json['expired_at'] as String).toLocal(),
      favoriteCleanupAfter:
          DateTime.parse(json['favorite_cleanup_after'] as String).toLocal(),
      databaseCleanupAfter:
          DateTime.parse(json['database_cleanup_after'] as String).toLocal(),
      favoriteTrimmedAt: switch (json['favorite_trimmed_at']) {
        String value => DateTime.tryParse(value)?.toLocal(),
        _ => null,
      },
      databaseTrimmedAt: switch (json['database_trimmed_at']) {
        String value => DateTime.tryParse(value)?.toLocal(),
        _ => null,
      },
    );
  }

  int favoriteDaysLeft({DateTime? now}) => _daysLeft(favoriteCleanupAfter, now);
  int databaseDaysLeft({DateTime? now}) => _daysLeft(databaseCleanupAfter, now);

  bool get favoritesRemoved => favoriteTrimmedAt != null;
  bool get databaseTrimmed => databaseTrimmedAt != null;

  int _daysLeft(DateTime deadline, DateTime? now) {
    final diff = deadline.difference(now ?? DateTime.now());
    if (diff.isNegative) return 0;
    final wholeDays = diff.inDays;
    return diff.inHours % 24 == 0 ? wholeDays : wholeDays + 1;
  }
}

String retentionWarningText(SubscriptionRetentionGrace grace, {DateTime? now}) {
  if (grace.databaseTrimmed) {
    return 'Your Pro grace period ended. Over-limit saved analyses were reduced to the free limit. You can still export your data or renew Pro for full access.';
  }

  final databaseDays = grace.databaseDaysLeft(now: now);
  if (grace.favoritesRemoved) {
    if (databaseDays <= 1) {
      return 'Your extra favorite players were reduced to the free limit. Tomorrow, over-limit saved analyses/database access will be reduced too. Export now or renew Pro to keep everything active.';
    }
    return 'Your extra favorite players were reduced to the free limit. Over-limit saved analyses/database access will be reduced in $databaseDays days. Export now or renew Pro to keep everything active.';
  }

  final favoriteDays = grace.favoriteDaysLeft(now: now);
  if (favoriteDays <= 1) {
    return 'Your Pro subscription expired. Tomorrow, extra favorite players will be reduced to the free limit. Your saved analyses/database access stays in grace for 7 more days after that.';
  }

  return 'Your Pro subscription expired. Your work is still available during grace: extra favorite players for $favoriteDays days, and saved analyses/database access for $databaseDays days. Export now or renew Pro to keep everything active.';
}

class SubscriptionRetentionWarningBanner extends StatelessWidget {
  const SubscriptionRetentionWarningBanner({
    super.key,
    required this.grace,
    this.margin = const EdgeInsets.fromLTRB(16, 8, 16, 12),
  });

  final SubscriptionRetentionGrace grace;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF3A2505),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFFBBF24)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              retentionWarningText(grace),
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
