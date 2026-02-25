class EngineSearchProgress {
  static const int minReportDepth = 12;

  EngineSearchProgress({
    required int depth,
    required this.kiloNodes,
    this.fenFragment = '',
    DateTime? timestamp,
  }) : depth = depth < minReportDepth ? minReportDepth : depth,
       timestamp = timestamp ?? DateTime.now();

  final int depth;
  final int kiloNodes;
  final String fenFragment;
  final DateTime timestamp;

  EngineSearchProgress copyWith({
    int? depth,
    int? kiloNodes,
    String? fenFragment,
    DateTime? timestamp,
  }) {
    return EngineSearchProgress(
      depth: depth ?? this.depth,
      kiloNodes: kiloNodes ?? this.kiloNodes,
      fenFragment: fenFragment ?? this.fenFragment,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

enum EngineComponent {
  evaluationGauge,
  principalVariation,
  moveImpact,
  cascadeEval,
}
