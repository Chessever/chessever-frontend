class EngineConfiguration {
  EngineConfiguration._();

  static final EngineConfiguration instance = EngineConfiguration._();

  /// Central place to control Stockfish depth.
  int get stockfishDepth => 15;

  /// Desired number of principal variation lines (MultiPV setting).
  int get principalVariationCount => 3;
}
