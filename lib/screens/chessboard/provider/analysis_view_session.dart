import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Presentation only. No report/cache/PGN writes and no global setting changes.
/// Widgets keep this alive for the board visit, not background report workers.
final analysisViewSessionProvider = StateNotifierProvider.autoDispose
    .family<AnalysisViewSessionController, AnalysisViewSession, String>(
      (ref, gameId) => AnalysisViewSessionController(),
    );

class AnalysisViewSession {
  const AnalysisViewSession({
    this.cleared = false,
    this.reportRequested = false,
    this.sourceHidden = false,
    this.hiddenVariationIds = const <String>{},
    this.revision = 0,
  });

  final bool cleared;
  final bool reportRequested;

  /// Set by Clear and kept for the rest of the visit, even after an explicit
  /// Generate Report lifts [cleared]: source symbols and comments stay hidden.
  final bool sourceHidden;

  /// Variation ids that existed when Clear was tapped. The navigator appends
  /// later branches under fresh ids, so anything the user plays after Clear
  /// renders normally while the pre-existing tree stays out of view.
  final Set<String> hiddenVariationIds;
  final int revision;

  bool showSourceAnnotations({required bool rawPgn}) =>
      !cleared && !sourceHidden && !rawPgn;
  bool showReport({required bool rawPgn}) =>
      !cleared && (!rawPgn || reportRequested);
}

class AnalysisViewSessionController extends StateNotifier<AnalysisViewSession> {
  AnalysisViewSessionController() : super(const AnalysisViewSession());

  void clear({Set<String> hiddenVariationIds = const <String>{}}) {
    state = AnalysisViewSession(
      cleared: true,
      sourceHidden: true,
      hiddenVariationIds: hiddenVariationIds,
      revision: state.revision + 1,
    );
  }

  int requestReport() {
    state = AnalysisViewSession(
      reportRequested: true,
      sourceHidden: state.sourceHidden,
      hiddenVariationIds: state.hiddenVariationIds,
      revision: state.revision + 1,
    );
    return state.revision;
  }

  bool isCurrentRequest(int revision) =>
      mounted && state.reportRequested && state.revision == revision;
}
