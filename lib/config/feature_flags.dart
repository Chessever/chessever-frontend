/// Features that are built but not shown yet. Their entry points check the
/// flag and the code behind them stays, so turning one back on is a
/// one-line change here.
class FeatureFlags {
  const FeatureFlags._();

  /// Streaks: the wall, player streak cards, the profile's streak line and
  /// the Feed's streak captions. Hidden until the statistics behind them are
  /// right.
  static const bool streaks = false;

  /// The classified-move sounds (brilliant, blunder...) on the main boards.
  /// Off: those boards play the ordinary move sounds, while the badges and
  /// landing animations stay. Feed keeps its own classified-move sounds
  /// either way.
  static const bool boardClassificationSounds = false;

  /// My Space's seeded defaults (elite openings, GM and Classical Smart
  /// Events). Off: a new My Space starts empty and My Database explains how
  /// to fill it. Pins an account already has are never touched.
  static const bool mySpaceDefaults = false;
}
