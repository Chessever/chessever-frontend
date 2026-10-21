import 'package:chessever2/revenue_cat_service/offline_premium_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final verifiedAt = DateTime.utc(2026, 10, 1);
  final expiresAt = DateTime.utc(2026, 11, 1);

  test('a renewing subscription holds a week past its period offline', () {
    final snapshot = OfflinePremiumSnapshot(
      verifiedAt: verifiedAt,
      expiresAt: expiresAt,
    );

    expect(snapshot.honoredAt(DateTime.utc(2026, 10, 20)), isTrue);
    expect(snapshot.honoredAt(DateTime.utc(2026, 11, 7)), isTrue);
    expect(snapshot.honoredAt(DateTime.utc(2026, 11, 9)), isFalse);
  });

  test('a cancelled subscription ends at its expiry', () {
    final snapshot = OfflinePremiumSnapshot(
      verifiedAt: verifiedAt,
      expiresAt: expiresAt,
      willRenew: false,
    );

    expect(snapshot.honoredAt(DateTime.utc(2026, 10, 31)), isTrue);
    expect(snapshot.honoredAt(DateTime.utc(2026, 11, 2)), isFalse);
  });

  test('an undated confirmation holds for thirty days', () {
    final snapshot = OfflinePremiumSnapshot(verifiedAt: verifiedAt);

    expect(snapshot.honoredAt(DateTime.utc(2026, 10, 30)), isTrue);
    expect(snapshot.honoredAt(DateTime.utc(2026, 11, 1)), isFalse);
  });

  test('the snapshot survives its stored form', () {
    final snapshot = OfflinePremiumSnapshot(
      verifiedAt: verifiedAt,
      expiresAt: expiresAt,
      provider: 'stripe',
      willRenew: false,
    );

    final restored = OfflinePremiumSnapshot.fromJson(snapshot.toJson())!;

    expect(restored.verifiedAt, verifiedAt);
    expect(restored.expiresAt, expiresAt);
    expect(restored.provider, 'stripe');
    expect(restored.willRenew, isFalse);
    expect(OfflinePremiumSnapshot.fromJson('garbage'), isNull);
  });
}
