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
    this.hideVariations = false,
    this.revision = 0,
  });

  final bool cleared;
  final bool reportRequested;
  final bool hideVariations;
  final int revision;

  bool showSourceAnnotations({required bool rawPgn}) =>
      !cleared && !hideVariations && !rawPgn;
  bool showReport({required bool rawPgn}) =>
      !cleared && (!rawPgn || reportRequested);
}

class AnalysisViewSessionController extends StateNotifier<AnalysisViewSession> {
  AnalysisViewSessionController() : super(const AnalysisViewSession());

  void clear() {
    state = AnalysisViewSession(
      cleared: true,
      hideVariations: true,
      revision: state.revision + 1,
    );
  }

  int requestReport() {
    state = AnalysisViewSession(
      reportRequested: true,
      hideVariations: state.hideVariations,
      revision: state.revision + 1,
    );
    return state.revision;
  }

  bool isCurrentRequest(int revision) =>
      mounted && state.reportRequested && state.revision == revision;
}
