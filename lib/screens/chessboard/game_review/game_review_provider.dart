import 'dart:async';

import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

@immutable
class MobileGameReviewState {
  const MobileGameReviewState({
    this.reportState = const GameReportState(),
    this.fingerprint,
    this.revealedFingerprint,
    this.isEligible = false,
    this.unavailableMessage,
  });

  final GameReportState reportState;
  final String? fingerprint;
  final String? revealedFingerprint;
  final bool isEligible;
  final String? unavailableMessage;

  bool get classificationsRevealed =>
      fingerprint != null && fingerprint == revealedFingerprint;

  /// Whether the Game Analysis entry point should be shown at all. A live or
  /// move-less game offers nothing to analyze yet, so the button (and its
  /// "starts when the game ends" copy) is hidden until there is a real report
  /// to run or show.
  bool get shouldOfferAnalysis =>
      isEligible || reportState.status != GameReportStatus.idle;

  MobileGameReviewState copyWith({
    GameReportState? reportState,
    String? fingerprint,
    String? revealedFingerprint,
    bool? isEligible,
    String? unavailableMessage,
    bool clearRevealed = false,
    bool clearUnavailableMessage = false,
  }) {
    return MobileGameReviewState(
      reportState: reportState ?? this.reportState,
      fingerprint: fingerprint ?? this.fingerprint,
      revealedFingerprint:
          clearRevealed
              ? null
              : (revealedFingerprint ?? this.revealedFingerprint),
      isEligible: isEligible ?? this.isEligible,
      unavailableMessage:
          clearUnavailableMessage
              ? null
              : (unavailableMessage ?? this.unavailableMessage),
    );
  }
}

class MobileGameReviewController extends ChangeNotifier {
  static const Duration defaultAutoStartDelay = Duration(seconds: 2);

  MobileGameReviewController({
    GameAnalysisReportController? reportController,
    Duration autoStartDelay = defaultAutoStartDelay,
  }) : _reportController = reportController ?? GameAnalysisReportController(),
       _autoStartDelay = autoStartDelay {
    _reportController.addListener(_onReportChanged);
  }

  final GameAnalysisReportController _reportController;
  MobileGameReviewState _state = const MobileGameReviewState();
  ChessGame? _game;
  int? _whiteRating;
  int? _blackRating;
  bool _active = false;
  bool _disposed = false;
  Timer? _autoStartTimer;
  final Duration _autoStartDelay;

  MobileGameReviewState get state => _state;

  void configure({
    required ChessGame game,
    required bool active,
    required bool finished,
    required int whiteRating,
    required int blackRating,
  }) {
    if (_disposed) return;
    final fingerprint = gameReportFingerprint(game);
    final changed = fingerprint != _state.fingerprint;
    _game = game;
    _whiteRating = whiteRating > 0 ? whiteRating : null;
    _blackRating = blackRating > 0 ? blackRating : null;
    _active = active;

    if (changed) {
      _autoStartTimer?.cancel();
      _reportController.invalidate();
      _state = MobileGameReviewState(
        fingerprint: fingerprint,
        isEligible: finished && game.mainline.isNotEmpty,
        unavailableMessage: _unavailableMessage(
          finished: finished,
          hasMoves: game.mainline.isNotEmpty,
        ),
      );
      notifyListeners();
      // A finished game already analyzed this session is restored instantly
      // (and its classifications revealed) instead of being recomputed.
      if (_state.isEligible) {
        _reportController.loadCachedReport(fingerprint);
      }
    } else {
      final eligible = finished && game.mainline.isNotEmpty;
      final message = _unavailableMessage(
        finished: finished,
        hasMoves: game.mainline.isNotEmpty,
      );
      if (_state.isEligible != eligible ||
          _state.unavailableMessage != message) {
        _state = _state.copyWith(
          isEligible: eligible,
          unavailableMessage: message,
          clearUnavailableMessage: message == null,
        );
        notifyListeners();
      }
    }

    if (!active) {
      _autoStartTimer?.cancel();
      if (_reportController.state.isRunning) {
        unawaited(_reportController.cancel());
      }
      return;
    }
    if (_state.isEligible &&
        (_reportController.state.status == GameReportStatus.idle ||
            _reportController.state.status == GameReportStatus.cancelled)) {
      _scheduleAnalyze();
    }
  }

  void setActive(bool active) {
    if (_disposed || _active == active) return;
    _active = active;
    if (!active) {
      _autoStartTimer?.cancel();
      if (_reportController.state.isRunning) {
        unawaited(_reportController.cancel());
      }
      return;
    }
    if (_state.isEligible &&
        (_reportController.state.status == GameReportStatus.idle ||
            _reportController.state.status == GameReportStatus.cancelled)) {
      _scheduleAnalyze();
    }
  }

  String? _unavailableMessage({
    required bool finished,
    required bool hasMoves,
  }) {
    if (!hasMoves) return 'Game analysis needs at least one move';
    if (!finished) return 'Game analysis starts when the game ends';
    return null;
  }

  void reveal() {
    final fingerprint = _state.fingerprint;
    if (fingerprint == null || fingerprint == _state.revealedFingerprint) {
      return;
    }
    _state = _state.copyWith(revealedFingerprint: fingerprint);
    notifyListeners();
  }

  Future<void> retry() async {
    if (!_active || !_state.isEligible) return;
    _autoStartTimer?.cancel();
    _reportController.invalidate();
    await _analyze();
  }

  void _scheduleAnalyze() {
    // configure() is invoked from the notation build lifecycle. Keep the first
    // scheduled start so unrelated rebuilds cannot postpone analysis forever.
    if (_autoStartTimer?.isActive ?? false) return;
    _autoStartTimer = Timer(_autoStartDelay, () {
      _autoStartTimer = null;
      if (_disposed || !_active || !_state.isEligible) return;
      unawaited(_analyze());
    });
  }

  Future<void> _analyze() async {
    final game = _game;
    if (game == null || !_active || !_state.isEligible) return;
    await _reportController.analyze(
      game,
      whiteRating: _whiteRating,
      blackRating: _blackRating,
    );
  }

  void _onReportChanged() {
    if (_disposed) return;
    _state = _state.copyWith(reportState: _reportController.state);
    // Reveal the per-move classification badges in the notation as soon as the
    // report is ready — the user no longer has to open the review sheet first.
    if (_reportController.state.status == GameReportStatus.completed &&
        _state.fingerprint != null &&
        _state.fingerprint != _state.revealedFingerprint) {
      _state = _state.copyWith(revealedFingerprint: _state.fingerprint);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _autoStartTimer?.cancel();
    _reportController.removeListener(_onReportChanged);
    _reportController.dispose();
    super.dispose();
  }
}

final mobileGameReviewProvider = ChangeNotifierProvider.autoDispose
    .family<MobileGameReviewController, ChessBoardProviderParams>(
      (ref, params) => MobileGameReviewController(),
    );
