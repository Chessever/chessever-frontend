/// Maximum number of favorite players a free user can have.
/// After reaching this limit, users must upgrade to premium.
const int kFreeFavoriteLimit = 3;

/// Thrown when a free user tries to add a favorite beyond [kFreeFavoriteLimit].
class FavoriteLimitExceededException implements Exception {
  final int limit;
  const FavoriteLimitExceededException(this.limit);

  @override
  String toString() =>
      'FavoriteLimitExceededException: limit of $limit reached';
}
