/// Prefer the canonical FIDE/Supabase rating over Gamebase metadata.
///
/// Gamebase remains the fallback while its staged player row is unavailable or
/// waiting for the canonical rating synchronization to complete.
int? preferCanonicalFideRating({
  required int? canonicalRating,
  required int? gamebaseRating,
}) => canonicalRating ?? gamebaseRating;
