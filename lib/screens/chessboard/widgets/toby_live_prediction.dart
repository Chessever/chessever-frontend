/// Toby's most likely moves at the broadcast board's position, with their
/// likelihood and outcome bars. Tapping a move toggles its arrow; tapping
/// a bar reveals its exact split and expected score.
///
/// Shown on any position of a broadcast game, live or finished, unless the
/// reader turned it off (Settings → Engine → Toby). Where the game
/// is over on the board it says so, with the result. Whatever the engine
/// source setting says: the engine lines may run Stockfish while this reads
/// Toby.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/chessboard/game_review/classification_style.dart';
import 'package:chessever2/screens/chessboard/game_review/game_analysis_report.dart'
    show GameMoveClassification;
import 'package:chessever2/screens/chessboard/provider/board_eval_restart_policy.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/utils/toby_palette.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/services/toby/toby_board_request.dart';
import 'package:chessever2/services/toby/toby_prediction.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// ---------------------------------------------------------------------------
// Arrow selection (shared with the board)
// ---------------------------------------------------------------------------

/// The Toby move the reader tapped: the position it belongs to, the move,
/// and the hue its arrow is drawn in.
typedef TobyArrowSelection = ({String fen, String uci, Color color});

/// The tapped Toby move per game, or null. The board draws it as an arrow
/// while it still shows [TobyArrowSelection.fen]; the prediction clears it
/// as soon as the position changes.
final tobyArrowProvider = StateProvider.autoDispose
    .family<TobyArrowSelection?, String>((ref, gameId) => null);

/// The arrow [selection] draws on a board showing [boardFen], or null when
/// nothing is selected, the selection belongs to another position, or the
/// move is not legal there.
Arrow? tobyArrowShape(TobyArrowSelection? selection, String boardFen) {
  if (selection == null) return null;
  if (_fenKey(selection.fen) != _fenKey(boardFen)) return null;
  final uci = selection.uci.trim();
  if (uci.length < 4 || !isFirstUciLegalForFen(boardFen, uci)) return null;
  try {
    final orig = Square.fromName(uci.substring(0, 2));
    final dest = Square.fromName(uci.substring(2, 4));
    if (orig == dest) return null;
    return Arrow(
      color: selection.color.withValues(alpha: 0.85),
      orig: orig,
      dest: dest,
      scale: 0.9,
    );
  } catch (_) {
    return null;
  }
}

String _fenKey(String fen) =>
    fen.trim().split(RegExp(r'\s+')).take(4).join(' ');

// ---------------------------------------------------------------------------
// Pure logic
// ---------------------------------------------------------------------------

/// Whether "Toby Predicts" may show for a board in this state: any position
/// of a broadcast game, live or finished, on its moves or in a variation,
/// but not under a line preview or in threats mode.
bool tobyLivePredictionOpen({
  required GameSource source,
  required bool isPvPreviewActive,
  required bool isThreatsMode,
}) => source == GameSource.supabase && !isPvPreviewActive && !isThreatsMode;

/// [tobyLivePredictionOpen] for a board state.
bool tobyLivePredictionOpenFor(ChessBoardStateNew state) =>
    tobyLivePredictionOpen(
      source: state.game.source,
      isPvPreviewActive: state.isPvPreviewActive,
      isThreatsMode: state.isThreatsMode,
    );

/// The result at a position where the game is over on the board
/// (checkmate, stalemate, insufficient material), as Toby's chances, else
/// null. There is nothing for Toby to predict there.
TobyWdl? tobyOverWdl(String fen) {
  try {
    final position = Chess.fromSetup(Setup.parseFen(fen));
    if (position.isCheckmate) {
      return position.turn == Side.white
          ? const TobyWdl(white: 0, draw: 0, black: 1)
          : const TobyWdl(white: 1, draw: 0, black: 0);
    }
    if (position.isStalemate || position.isInsufficientMaterial) {
      return const TobyWdl(white: 0, draw: 1, black: 0);
    }
  } catch (_) {}
  return null;
}

/// A move as the notation numbers it, from the position [fen] it is played
/// in: "24.Nf6" for White, "24…Nf6" for Black (U+2026).
String tobyNumberedMove(String fen, String san) {
  final fields = fen.trim().split(RegExp(r'\s+'));
  final blackToMove = fields.length > 1 && fields[1] == 'b';
  final number = fields.length > 5 ? int.tryParse(fields[5]) ?? 1 : 1;
  final moveNumber = number < 1 ? 1 : number;
  return blackToMove ? '$moveNumber…$san' : '$moveNumber.$san';
}

/// One move of the prediction line.
@immutable
class TobyPredictionToken {
  const TobyPredictionToken({
    required this.rank,
    required this.uci,
    required this.chance,
    required this.san,
    required this.move,
    required this.hue,
    required this.sideToMove,
    this.wdl,
    this.quality,
  });

  /// 0 for the likeliest move.
  final int rank;
  final String uci;

  /// "34%", or "<1%".
  final String chance;

  /// Unnumbered move notation, e.g. "Nf6".
  final String san;

  /// Numbered move shown in the table, e.g. "24.Nf6" / "24…Nf6".
  final String move;
  final Color hue;
  final Side sideToMove;
  final TobyWdl? wdl;
  final GameMoveClassification? quality;

  /// "34% 24.Nf6".
  String get text => '$chance $move';
}

/// The likeliest [count] moves of [reading] for the position [fen], most
/// likely first, each with its hue.
List<TobyPredictionToken> tobyPredictionTokens(
  TobyReading reading,
  String fen, {
  int count = 3,
}) {
  final indexed = reading.candidates.indexed.toList()
    ..sort((a, b) {
      final byChance = b.$2.probability.compareTo(a.$2.probability);
      return byChance != 0 ? byChance : a.$1.compareTo(b.$1);
    });
  final tokens = <TobyPredictionToken>[];
  for (final (_, candidate) in indexed.take(math.max(0, count))) {
    final rank = tokens.length;
    final san = candidate.san.trim().isEmpty ? candidate.uci : candidate.san;
    tokens.add(
      TobyPredictionToken(
        rank: rank,
        uci: candidate.uci,
        chance: tobyEngineLineChance(candidate.probability),
        san: san.trim(),
        move: tobyNumberedMove(fen, san.trim()),
        hue: tobyCandidateHue(rank),
        sideToMove: reading.sideToMove,
        wdl: candidate.wdl,
      ),
    );
  }
  return tokens;
}

/// What a tap on the Toby title explains, with the current position chances.
String tobyChanceExplanation(({int white, int draw, int black})? p) => [
  if (p != null)
    'White wins ${p.white}%, draw ${p.draw}%, Black wins ${p.black}%: '
        "Toby's prediction from this position, for players of these ratings "
        'at this time control.',
  kTobyAttribution,
].join('\n');

/// Broadcast-only Toby panel. Builds nothing for unsupported positions or
/// readers without access; it does not change the board's engine settings.
class TobyLivePrediction extends ConsumerStatefulWidget {
  const TobyLivePrediction({
    super.key,
    required this.params,
    this.onLayoutChange,
    this.onSettingsTap,
  });

  final ChessBoardProviderParams params;

  /// Called during build, before layout, whenever the line appears or
  /// disappears, so the notation can hold its scroll anchor.
  final VoidCallback? onLayoutChange;
  final VoidCallback? onSettingsTap;

  @override
  ConsumerState<TobyLivePrediction> createState() => _TobyLivePredictionState();
}

/// The board's position while the live prediction may show, else null.
String? _liveFenOf(AsyncValue<ChessBoardStateNew> async) {
  final state = async.valueOrNull;
  if (state == null || !tobyLivePredictionOpenFor(state)) return null;
  return state.analysisState.position.fen;
}

class _TobyLivePredictionState extends ConsumerState<TobyLivePrediction> {
  /// The reader was refused (sign-in or Premium): nothing more is asked on
  /// this board.
  bool _refused = false;

  String? _requestFen;
  TobyRequest? _request;

  /// Clears a tapped move's arrow on its own after [_arrowLife].
  Timer? _arrowTimer;
  static const Duration _arrowLife = Duration(seconds: 6);
  bool _visible = false;

  String get _gameId => widget.params.game.gameId;

  @override
  void dispose() {
    _arrowTimer?.cancel();
    super.dispose();
  }

  TobyRequest? _requestFor(String fen) {
    if (_requestFen == fen) return _request;
    _requestFen = fen;
    final state = ref.read(chessBoardScreenProviderNew(widget.params));
    final board = state.valueOrNull;
    final request = board == null
        ? null
        : buildTobyRequestFromBoardState(board, targetFen: fen);
    _request = request != null && request.isSupported ? request : null;
    return _request;
  }

  void _setVisible(bool visible) {
    if (visible == _visible) return;
    _visible = visible;
    widget.onLayoutChange?.call();
  }

  Widget _hidden() {
    _setVisible(false);
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    // The board's fen while the prediction may show, else null.
    final liveFenProvider = chessBoardScreenProviderNew(
      widget.params,
    ).select(_liveFenOf);
    final liveFen = ref.watch(liveFenProvider);
    ref.listen<String?>(liveFenProvider, (previous, next) {
      if (previous == next) return;
      // A new position (or leaving the live tail) drops the tapped arrow.
      Future.microtask(() {
        if (!mounted) return;
        final selection = ref.read(tobyArrowProvider(_gameId));
        if (selection != null && selection.fen != next) {
          ref.read(tobyArrowProvider(_gameId).notifier).state = null;
        }
      });
    });

    // The block's room is decided before Toby answers and then held: a
    // reader the app believes is Premium, in a build that can reach Toby,
    // gets a fixed-height table while the reading loads.
    if (liveFen == null || _refused) return _hidden();
    final showSetting = ref.watch(
      engineSettingsProviderNew.select(
        (settings) => settings.valueOrNull?.tobyEnabled ?? true,
      ),
    );
    if (!showSetting) return _hidden();
    if (!ref.watch(tobyReaderHasPremiumProvider) ||
        !ref.read(gamebaseRepositoryProvider).hasApiKey) {
      return _hidden();
    }
    // A terminal position has a result but no candidate moves.
    final over = tobyOverWdl(liveFen);
    if (over != null) {
      _setVisible(true);
      return TobyPredictsLine(
        wdl: over,
        tokens: const [],
        note: 'Game over',
        onSettingsTap: widget.onSettingsTap,
      );
    }

    final request = _requestFor(liveFen);
    if (request == null) return _hidden();

    final session = ref
        .read(chessBoardScreenProviderNew(widget.params).notifier)
        .tobySession;
    final reading = ref.watch(
      tobyReadingProvider(TobyQuery(request: request, session: session)),
    );

    TobyReading? shown;
    var waiting = true;
    switch (reading.status) {
      case TobyStatus.ready:
      case TobyStatus.network:
        shown = reading.reading;
      case TobyStatus.thinking:
        shown = null;
      case TobyStatus.busy:
      case TobyStatus.unavailable:
        // Out of budget or out of service: say so in place, same height.
        shown = reading.reading;
        waiting = false;
      case TobyStatus.signInRequired:
      case TobyStatus.premiumRequired:
      case TobyStatus.premiumUnconfirmed:
        _refused = true;
        return _hidden();
      case TobyStatus.notApplicable:
        return _hidden();
    }

    _setVisible(true);

    final tokens = shown == null
        ? const <TobyPredictionToken>[]
        : tobyPredictionTokens(shown, liveFen);
    final selection = ref.watch(tobyArrowProvider(_gameId));
    final selectedUci = selection != null && selection.fen == liveFen
        ? selection.uci
        : null;

    return TobyPredictsLine(
      wdl: shown?.positionWdl,
      tokens: tokens,
      waiting: waiting,
      muted: shown != null && !shown.isFinal,
      selectedUci: selectedUci,
      onMoveTap: (token) => _toggle(token, liveFen),
      onSettingsTap: widget.onSettingsTap,
    );
  }

  void _toggle(TobyPredictionToken token, String fen) {
    HapticFeedback.selectionClick();
    final notifier = ref.read(tobyArrowProvider(_gameId).notifier);
    final current = notifier.state;
    final same =
        current != null && current.fen == fen && current.uci == token.uci;
    final next = same ? null : (fen: fen, uci: token.uci, color: token.hue);
    notifier.state = next;
    // The arrow goes away by itself (or on the next move, or a second tap).
    _arrowTimer?.cancel();
    if (next == null) return;
    _arrowTimer = Timer(_arrowLife, () {
      if (!mounted) return;
      final arrow = ref.read(tobyArrowProvider(_gameId).notifier);
      if (arrow.state == next) arrow.state = null;
    });
  }
}

/// Compact Toby table for the broadcast board. Move taps still select an
/// arrow; the separate outcome bar reveals the candidate's result chances.
class TobyPredictsLine extends StatelessWidget {
  const TobyPredictsLine({
    super.key,
    this.wdl,
    required this.tokens,
    this.waiting = true,
    this.note,
    this.muted = false,
    this.selectedUci,
    this.onMoveTap,
    this.onMoveLongPress,
    this.playOnMoveTap = false,
    this.engineToggle,
    this.outcomeLegendPieces,
    this.phoneRowCount,
    this.onSettingsTap,
  });

  static const int _rowCount = 3;
  static const double engineHeaderHeight = 44;
  static double engineSelectorWidth(double contentWidth) =>
      math.min(136, contentWidth * .43);
  static double engineRowHeight(BuildContext context) =>
      _rowHeight(context, minimum: 28);
  static double _rowHeight(BuildContext context, {double minimum = 34}) =>
      math.max(minimum, MediaQuery.textScalerOf(context).scale(15.sp) + 12);
  static double panelHeight(BuildContext context) =>
      engineHeaderHeight + _rowCount * _rowHeight(context);

  final TobyWdl? wdl;
  final List<TobyPredictionToken> tokens;
  final bool waiting;
  final String? note;
  final bool muted;
  final String? selectedUci;
  final ValueChanged<TobyPredictionToken>? onMoveTap;
  final ValueChanged<TobyPredictionToken>? onMoveLongPress;
  final bool playOnMoveTap;
  final Widget? engineToggle;
  final PieceAssets? outcomeLegendPieces;
  final int? phoneRowCount;
  final VoidCallback? onSettingsTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final quiet = AppTypography.textSmMedium.copyWith(
      color: context.textInk(0.65),
      fontSize: 11.sp,
    );
    final value = AppTypography.textSmMedium.copyWith(
      color: colors.textPrimary,
      fontSize: 13.sp,
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final arrowSelected = tokens.any((token) => token.uci == selectedUci);

    return LayoutBuilder(
      builder: (context, constraints) {
        final moveWidth = engineToggle == null
            ? math.min(104.sp, constraints.maxWidth * .33)
            : engineSelectorWidth(constraints.maxWidth);
        final chanceWidth = math.min(68.sp, constraints.maxWidth * .25);
        final chanceInset = engineToggle == null ? 0.0 : 8.0;
        // The pinned engine rail uses the same compact rhythm as the PV
        // strip so short phones still have room for notation.
        final rowHeight = playOnMoveTap
            ? engineRowHeight(context)
            : _rowHeight(context);
        Widget cellText(
          String text,
          TextStyle style, {
          double? width,
          double leftInset = 0,
        }) => SizedBox(
          width: width,
          child: Padding(
            padding: EdgeInsets.only(left: leftInset),
            child: FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Text(text, maxLines: 1, style: style),
            ),
          ),
        );

        Widget king(PieceKind kind, String fallback) {
          final image = outcomeLegendPieces?[kind];
          if (image == null) return Text(fallback, style: quiet);
          return Image(
            image: image,
            width: 16.sp,
            height: 16.sp,
            filterQuality: FilterQuality.high,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: engineHeaderHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: moveWidth,
                    child:
                        engineToggle ??
                        _TobyTapHint(
                          message: tobyChanceExplanation(wdl?.percentages),
                          label: 'About Toby. $kTobyAttribution',
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: cellText(
                              'Toby',
                              value.copyWith(fontSize: 14.sp),
                            ),
                          ),
                        ),
                  ),
                  SizedBox(
                    width: chanceWidth,
                    child: engineToggle == null
                        ? cellText('Chance', quiet)
                        : _TobyTapHint(
                            label: 'Chance',
                            message:
                                'How likely the player is to make this move.',
                            child: cellText(
                              'Chance',
                              quiet,
                              leftInset: chanceInset,
                            ),
                          ),
                  ),
                  Expanded(
                    child: engineToggle == null
                        ? Semantics(
                            label: 'White wins, draw, Black wins',
                            excludeSemantics: true,
                            child: cellText('W / = / B', quiet),
                          )
                        : FittedBox(
                            key: const ValueKey('toby-outcome-legend'),
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _TobyTapHint(
                                  label: 'White wins',
                                  message:
                                      'How likely White is to win after this move.',
                                  child: SizedBox(
                                    width: 32,
                                    height: engineHeaderHeight,
                                    child: Center(
                                      child: king(PieceKind.whiteKing, 'White'),
                                    ),
                                  ),
                                ),
                                _TobyTapHint(
                                  label: 'Draw',
                                  message:
                                      'How likely the game is to end in a draw after this move.',
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      minWidth: 38,
                                      minHeight: engineHeaderHeight,
                                    ),
                                    child: Center(
                                      widthFactor: 1,
                                      child: Text('Draw', style: quiet),
                                    ),
                                  ),
                                ),
                                _TobyTapHint(
                                  label: 'Black wins',
                                  message:
                                      'How likely Black is to win after this move.',
                                  child: SizedBox(
                                    width: 32,
                                    height: engineHeaderHeight,
                                    child: Center(
                                      child: king(PieceKind.blackKing, 'Black'),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                  if (onSettingsTap != null)
                    IconButton(
                      tooltip: 'Engine settings',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 44,
                        height: 44,
                      ),
                      icon: Icon(
                        Icons.settings_outlined,
                        size: 17.sp,
                        color: colors.iconPrimary,
                      ),
                      onPressed: onSettingsTap,
                    ),
                ],
              ),
            ),
            for (var i = 0; i < (phoneRowCount ?? _rowCount); i++)
              SizedBox(
                height: rowHeight,
                child: i < tokens.length
                    ? Builder(
                        builder: (context) {
                          final token = tokens[i];
                          final selected = token.uci == selectedUci;
                          final fill = selected
                              ? token.hue.withValues(alpha: 0.12)
                              : engineToggle == null && i.isOdd
                              ? colors.textPrimary.withValues(alpha: 0.045)
                              : Colors.transparent;
                          final outcome = token.wdl;
                          final quality = token.quality;
                          final canTapMove = onMoveTap != null;
                          void tapMove() => onMoveTap?.call(token);
                          return ColoredBox(
                            color: fill,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Semantics(
                                  button: canTapMove,
                                  selected: selected,
                                  label:
                                      '${token.move}, ${token.chance} chance of being played'
                                      '${quality == null ? '' : ', ${quality.label}'}',
                                  hint: canTapMove
                                      ? (playOnMoveTap
                                            ? 'Play move'
                                            : selected
                                            ? 'Hide board arrow'
                                            : 'Show board arrow')
                                      : null,
                                  onTap: canTapMove ? tapMove : null,
                                  excludeSemantics: true,
                                  child: InkWell(
                                    onTap: canTapMove ? tapMove : null,
                                    onLongPress: onMoveLongPress == null
                                        ? null
                                        : () => onMoveLongPress!(token),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 6,
                                            right: 7,
                                          ),
                                          child: SizedBox(
                                            width: math.max(0, moveWidth - 13),
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(token.move, maxLines: 1, style: value.copyWith(
                                                      fontWeight: selected
                                                          ? FontWeight.w800
                                                          : (muted || arrowSelected)
                                                          ? FontWeight.w500
                                                          : FontWeight.w700,
                                                    )),
                                                    if (quality != null) ...[
                                                      const SizedBox(width: 4),
                                                      SvgPicture.asset(
                                                        classificationIconAsset(quality),
                                                        key: ValueKey('toby-quality-${token.uci}'),
                                                        width: 14,
                                                        height: 14,
                                                        excludeFromSemantics: true,
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        cellText(
                                          token.chance,
                                          value,
                                          width: chanceWidth,
                                          leftInset: chanceInset,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: outcome == null
                                      ? cellText('—', quiet)
                                      : _TobyTapHint(
                                          message: _candidateOutcomeMessage(
                                            outcome,
                                            token.sideToMove,
                                          ),
                                          label: 'Outcomes for ${token.move}',
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              right: 6,
                                            ),
                                            child: Center(
                                              child: TobyOutcomeBar(
                                                outcome: outcome,
                                              ),
                                            ),
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          );
                        },
                      )
                    : i == 0
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: cellText(
                                note ?? (waiting ? 'Thinking…' : 'Unavailable'),
                                quiet,
                              ),
                            ),
                            if (note != null && wdl != null)
                              Expanded(
                                child: _TobyTapHint(
                                  message: tobyChanceExplanation(
                                    wdl!.percentages,
                                  ),
                                  label: 'Game result',
                                  child: Center(
                                    child: TobyOutcomeBar(outcome: wdl!),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      )
                    : null,
              ),
          ],
        );
      },
    );
  }
}

String _candidateOutcomeMessage(TobyWdl outcome, Side mover) {
  // Format the model's numbers directly, not the rounded shares used for
  // position summaries. Expected score is for the player making this move.
  String percent(double p) =>
      tobyPercentage(p).replaceFirst(RegExp(r'\.0%$'), '%');
  final isWhite = mover == Side.white;
  final score = (isWhite ? outcome.white : outcome.black) + outcome.draw / 2;
  return 'White wins ${percent(outcome.white)} · Draw ${percent(outcome.draw)} · '
      'Black wins ${percent(outcome.black)}\n'
      '${isWhite ? 'White' : 'Black'} expected score ${percent(score)}';
}

/// A shared position/candidate palette. The vertical position gauge never
/// prints a pawn score; candidate labels are shown only when they can fit.
class TobyOutcomeBar extends StatelessWidget {
  const TobyOutcomeBar({
    super.key,
    required this.outcome,
    this.axis = Axis.horizontal,
    this.whiteFirst = true,
  });

  final TobyWdl? outcome;
  final Axis axis;
  final bool whiteFirst;

  @override
  Widget build(BuildContext context) {
    final vertical = axis == Axis.vertical;
    final split = outcome;
    final border = Border.all(color: context.textInk(0.38));
    final radius = BorderRadius.circular(vertical ? 2 : 3);
    final percentages = split?.percentages;
    final pieces = split == null
        ? const <({double share, Color fill, Color ink, int label})>[]
        : [
            (
              share: split.white,
              fill: const Color(0xFFE9E9E9),
              ink: const Color(0xFF171719),
              label: percentages!.white,
            ),
            (
              share: split.draw,
              fill: const Color(0xFF4D6694),
              ink: const Color(0xFFFFFFFF),
              label: percentages.draw,
            ),
            (
              share: split.black,
              fill: const Color(0xFF151619),
              ink: const Color(0xFFF4F4F4),
              label: percentages.black,
            ),
          ];
    final ordered = whiteFirst ? pieces : pieces.reversed;
    final bar = Container(
      height: vertical ? null : 17,
      clipBehavior: Clip.antiAlias,
      foregroundDecoration: BoxDecoration(border: border, borderRadius: radius),
      decoration: BoxDecoration(
        color: context.colors.surfaceRecessed,
        borderRadius: radius,
      ),
      child: split == null
          ? Center(
              child: Text(
                '—',
                style: TextStyle(fontSize: 11, color: context.textInk(0.65)),
              ),
            )
          : Flex(
              direction: axis,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final piece in ordered)
                  if (piece.share > 0)
                    Expanded(
                      flex: math.max(1, (piece.share * 10000).round()),
                      child: ColoredBox(
                        color: piece.fill,
                        child: vertical
                            ? null
                            : _TobySegmentValue(
                                percent: piece.label,
                                color: piece.ink,
                              ),
                      ),
                    ),
              ],
            ),
    );
    if (!vertical) return bar;
    return Semantics(
      container: true,
      label: percentages == null
          ? 'Toby position: outcome unavailable'
          : 'Toby position: White wins ${percentages.white}%, draw ${percentages.draw}%, Black wins ${percentages.black}%',
      excludeSemantics: true,
      child: bar,
    );
  }
}

class _TobySegmentValue extends StatelessWidget {
  const _TobySegmentValue({required this.percent, required this.color});

  final int percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (percent == 0) return const SizedBox.shrink();
    final value = '$percent%';
    final style = AppTypography.textXsMedium.copyWith(
      color: color,
      fontSize: 10,
      height: 1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: value, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final fits =
            painter.width + 6 <= constraints.maxWidth &&
            painter.height + 2 <= constraints.maxHeight;
        painter.dispose();
        return fits
            ? Center(child: Text(value, style: style, maxLines: 1))
            : const SizedBox.shrink();
      },
    );
  }
}

class _TobyTapHint extends StatelessWidget {
  const _TobyTapHint({
    required this.message,
    required this.label,
    required this.child,
  });

  final String message;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hint = GlobalKey<TooltipState>();
    void reveal() {
      Tooltip.dismissAllToolTips();
      hint.currentState?.ensureTooltipVisible();
    }

    return Semantics(
      button: true,
      label: '$label. $message',
      onTap: reveal,
      excludeSemantics: true,
      child: Tooltip(
        key: hint,
        message: message,
        triggerMode: TooltipTriggerMode.manual,
        excludeFromSemantics: true,
        child: InkWell(onTap: reveal, child: child),
      ),
    );
  }
}
