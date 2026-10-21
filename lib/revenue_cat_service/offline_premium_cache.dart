import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:flutter/foundation.dart';

/// The last time a live source (RevenueCat or the `entitlement` function)
/// confirmed this reader's Premium on this device. An offline launch has
/// neither source, so this is what tells it the reader paid.
@immutable
class OfflinePremiumSnapshot {
  const OfflinePremiumSnapshot({
    required this.verifiedAt,
    this.expiresAt,
    this.provider,
    this.willRenew = true,
  });

  /// A renewing subscription that passes its period while the device is
  /// offline has almost always renewed; it keeps Premium this much longer,
  /// until the device can ask again.
  static const renewalGrace = Duration(days: 7);

  /// How long a confirmation with no expiry date vouches for Premium.
  static const undatedLifetime = Duration(days: 30);

  final DateTime verifiedAt;
  final DateTime? expiresAt;
  final String? provider;
  final bool willRenew;

  /// Whether this snapshot still vouches for Premium at [now].
  bool honoredAt(DateTime now) {
    final expiresAt = this.expiresAt;
    if (expiresAt == null) {
      return now.isBefore(verifiedAt.add(undatedLifetime));
    }
    return now.isBefore(willRenew ? expiresAt.add(renewalGrace) : expiresAt);
  }

  Map<String, Object?> toJson() => {
    'verified_at': verifiedAt.toUtc().toIso8601String(),
    'expires_at': expiresAt?.toUtc().toIso8601String(),
    'provider': provider,
    'will_renew': willRenew,
  };

  static OfflinePremiumSnapshot? fromJson(Object? json) {
    if (json is! Map) return null;
    final verifiedAt = DateTime.tryParse(json['verified_at'] as String? ?? '');
    if (verifiedAt == null) return null;
    return OfflinePremiumSnapshot(
      verifiedAt: verifiedAt,
      expiresAt: switch (json['expires_at']) {
        String s => DateTime.tryParse(s),
        _ => null,
      },
      provider: json['provider'] as String?,
      willRenew: json['will_renew'] as bool? ?? true,
    );
  }
}

/// Keeps one [OfflinePremiumSnapshot] per user, so a shared device never
/// lends one account's Premium to another. Every call swallows storage
/// failures: a missing snapshot only means the reader is asked online.
class OfflinePremiumCache {
  const OfflinePremiumCache();

  static String _key(String userId) => 'offline_premium_v1:$userId';

  Future<OfflinePremiumSnapshot?> read(String userId) async {
    try {
      return OfflinePremiumSnapshot.fromJson(
        await AppDatabase.instance.getJson<Object?>(_key(userId)),
      );
    } catch (e) {
      debugPrint('OfflinePremiumCache: read failed: $e');
      return null;
    }
  }

  Future<void> write(String userId, OfflinePremiumSnapshot snapshot) async {
    try {
      await AppDatabase.instance.setJson(_key(userId), snapshot.toJson());
    } catch (e) {
      debugPrint('OfflinePremiumCache: write failed: $e');
    }
  }

  Future<void> clear(String userId) async {
    try {
      await AppDatabase.instance.remove(_key(userId));
    } catch (e) {
      debugPrint('OfflinePremiumCache: clear failed: $e');
    }
  }
}
