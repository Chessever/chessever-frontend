/// Toby's live prediction. In the notation, one line after the last move:
/// "Toby Predicts: 16…Qxd4 or 16…Qxc2 or 16…c5", each move in its own hue;
/// tapping a move draws its arrow on the board in that hue. On the player
/// rows, each side's win chance after its rating, "(17%)", dashed so it
/// reads as tappable; a tap explains it.
///
/// Shown only on a live broadcast game, while it is being played, with the
/// reader on the last move. Whatever the engine source setting says: the
/// engine lines may run Stockfish while this reads Toby.
library;

import 'dart:async';
import 'dart:math' as math;

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

/// Whether the live prediction may show for a board in this state: a live
/// broadcast game still being played, with the reader on its last move, not
/// in a variation, a line preview or threats mode.
bool tobyLivePredictionOpen({
  required GameStatus status,
  required GameSource source,
  required bool isAtLiveTail,
  required bool isInAnalysisVariation,
  required bool isPvPreviewActive,
  required bool isThreatsMode,
}) =>
    status.isOngoing &&
    source == GameSource.supabase &&
    isAtLiveTail &&
    !isInAnalysisVariation &&
    !isPvPreviewActive &&
    !isThreatsMode;

/// [tobyLivePredictionOpen] for a board state.
bool tobyLivePredictionOpenFor(ChessBoardStateNew state) =>
    tobyLivePredictionOpen(
      status: state.game.effectiveGameStatus,
      source: state.game.source,
      isAtLiveTail: state.isAtLiveTail,
      isInAnalysisVariation: state.analysisState.isInAnalysisVariation,
      isPvPreviewActive: state.isPvPreviewActive,
      isThreatsMode: state.isThreatsMode,
    );

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
  });

  /// 0 for the likeliest move.
  final int rank;
  final String uci;

  /// "34%", or "<1%".
  final String chance;

  /// "Nf6", as the panel shows it (the move number is the game's next).
  final String san;

  /// "24.Nf6" / "24…Nf6", as screen readers hear it.
  final String move;
  final Color hue;

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
      ),
    );
  }
  return tokens;
}

/// "White 28, draw 57, Black 15".
String tobyWdlSemantics(({int white, int draw, int black}) percentages) =>
    'White ${percentages.white}, draw ${percentages.draw}, '
    'Black ${percentages.black}';

// ---------------------------------------------------------------------------
// Shared with the player rows
// ---------------------------------------------------------------------------

/// Toby's White / Draw / Black chances for the live position of a game
/// (keyed by game id), or null while there are none to show. Written by the
/// notation's [TobyLivePrediction], read by the board's player rows, which
/// show each side's chance after its rating.
final tobyLiveChancesProvider = StateProvider.family<TobyWdl?, String>(
  (ref, gameId) => null,
);

/// Toby's one hue, as desktop and chessever.com draw "Toby Predicts"
/// (desktop 0xFF83C7C4): the win chance after a player's rating.
const Color kTobyChanceHue = Color(0xFF83C7C4);

/// What a tap on a player's chance explains.
String tobyChanceExplanation(({int white, int draw, int black}) p) =>
    'Toby predicts: White wins ${p.white}%, draw ${p.draw}%, '
    'Black wins ${p.black}%, from this position, for players of these '
    'ratings at this time control.\n$kTobyAttribution';

/// A short tappable text with a dashed underline (it explains itself on a
/// tap), as desktop and chessever.com mark Toby's tappable labels.
class TobyDashedHint extends StatelessWidget {
  const TobyDashedHint({
    super.key,
    required this.text,
    required this.style,
    required this.message,
    required this.semanticsLabel,
  });

  final String text;
  final TextStyle style;
  final String message;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticsLabel,
    hint: 'Shows what it means',
    child: ExcludeSemantics(
      child: Tooltip(
        message: message,
        triggerMode: TooltipTriggerMode.tap,
        showDuration: const Duration(seconds: 6),
        excludeFromSemantics: true,
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          style: style.copyWith(
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.dashed,
            decorationColor: (style.color ?? context.colors.textPrimary)
                .withValues(alpha: 0.7),
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// "Toby Predicts: 16…Qxd4 or 16…Qxc2 or 16…c5", one line after the last
/// move. Builds nothing when the board is not live at its last move, when
/// Toby cannot read the position, or when the reader is refused (no paywall
/// in the notation). Also publishes the position's chances for the player
/// rows ([tobyLiveChancesProvider]).
class TobyLivePrediction extends ConsumerStatefulWidget {
  const TobyLivePrediction({
    super.key,
    required this.params,
    this.onLayoutChange,
  });

  final ChessBoardProviderParams params;

  /// Called during build, before layout, whenever the line appears or
  /// disappears, so the notation can hold its scroll anchor.
  final VoidCallback? onLayoutChange;

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

  /// The last position chances shown, held while the next reading comes.
  TobyWdl? _heldWdl;
  bool _visible = false;

  /// What the player rows were last given.
  TobyWdl? _published;
  ProviderContainer? _container;

  String get _gameId => widget.params.game.gameId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _container = ProviderScope.containerOf(context, listen: false);
  }

  @override
  void dispose() {
    final container = _container;
    final gameId = _gameId;
    if (_published != null && container != null) {
      // Not during the tree's teardown: the next microtask.
      Future.microtask(
        () => container.read(tobyLiveChancesProvider(gameId).notifier).state =
            null,
      );
    }
    super.dispose();
  }

  /// Hands [wdl] to the player rows after this frame (never mid-build).
  void _publish(TobyWdl? wdl) {
    if (identical(wdl, _published) || wdl == _published) return;
    _published = wdl;
    Future.microtask(() {
      if (!mounted) return;
      ref.read(tobyLiveChancesProvider(_gameId).notifier).state = wdl;
    });
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
    _publish(null);
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

    if (liveFen == null || _refused) return _hidden();
    final request = _requestFor(liveFen);
    if (request == null) return _hidden();

    final session = ref
        .read(chessBoardScreenProviderNew(widget.params).notifier)
        .tobySession;
    final reading = ref.watch(
      tobyReadingProvider(TobyQuery(request: request, session: session)),
    );

    TobyReading? shown;
    switch (reading.status) {
      case TobyStatus.ready:
      case TobyStatus.network:
      case TobyStatus.busy:
        shown = reading.reading;
      case TobyStatus.thinking:
        shown = null;
      case TobyStatus.signInRequired:
      case TobyStatus.premiumRequired:
      case TobyStatus.premiumUnconfirmed:
        _refused = true;
        return _hidden();
      case TobyStatus.unavailable:
      case TobyStatus.notApplicable:
        return _hidden();
    }

    // Thinking about a new position: hold the last chances, with a quiet
    // line. Before anything was ever shown (or when the budget ran out with
    // nothing), stay away rather than flash a placeholder.
    if (shown == null &&
        (reading.status == TobyStatus.busy || _heldWdl == null)) {
      return _hidden();
    }

    if (shown?.positionWdl != null) _heldWdl = shown!.positionWdl;
    _publish(_heldWdl);
    _setVisible(true);

    final tokens = shown == null
        ? const <TobyPredictionToken>[]
        : tobyPredictionTokens(shown, liveFen);
    final selection = ref.watch(tobyArrowProvider(_gameId));
    final selectedUci = selection != null && selection.fen == liveFen
        ? selection.uci
        : null;

    return TobyPredictsLine(
      tokens: tokens,
      muted: shown != null && !shown.isFinal,
      selectedUci: selectedUci,
      onMoveTap: (token) => _toggle(token, liveFen),
    );
  }

  void _toggle(TobyPredictionToken token, String fen) {
    HapticFeedback.selectionClick();
    final notifier = ref.read(tobyArrowProvider(_gameId).notifier);
    final current = notifier.state;
    final same =
        current != null && current.fen == fen && current.uci == token.uci;
    notifier.state = same ? null : (fen: fen, uci: token.uci, color: token.hue);
  }
}

/// The line itself, free of providers: "Toby Predicts:" (dashed, it shows
/// Toby's credit on a tap), then the likeliest moves joined by "or", each
/// in its arrow hue and tappable. No tokens: "thinking…".
class TobyPredictsLine extends StatelessWidget {
  const TobyPredictsLine({
    super.key,
    required this.tokens,
    this.muted = false,
    this.selectedUci,
    this.onMoveTap,
  });

  final List<TobyPredictionToken> tokens;

  /// A first, quicker reading: the moves are set lighter, never fainter.
  final bool muted;
  final String? selectedUci;
  final ValueChanged<TobyPredictionToken>? onMoveTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // The notation's background, which the move hues are checked against.
    final background = Color.alphaBlend(
      colors.surfaceRecessed.withValues(alpha: 0.3),
      colors.background,
    );
    final quiet = AppTypography.textSmMedium.copyWith(
      color: context.textInk(0.6),
      fontSize: 14.sp,
      fontWeight: FontWeight.w500,
      height: 1.3,
    );
    final hasSelection =
        selectedUci != null && tokens.any((token) => token.uci == selectedUci);
    // Moves keep a comfortable tap height without spacing the line out.
    final tapPad = EdgeInsets.symmetric(vertical: 8.sp);

    return Padding(
      padding: EdgeInsets.only(top: 2.sp),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Padding(
            padding: tapPad,
            child: TobyDashedHint(
              text: 'Toby Predicts:',
              style: quiet,
              message: kTobyAttribution,
              semanticsLabel: 'Toby Predicts. $kTobyAttribution',
            ),
          ),
          if (tokens.isEmpty)
            Padding(
              padding: tapPad,
              child: Text(' thinking…', style: quiet),
            ),
          for (var i = 0; i < tokens.length && i < 3; i++) ...[
            if (i > 0)
              Padding(
                padding: tapPad,
                child: Text(' or', style: quiet),
              ),
            _move(
              context,
              tokens[i],
              background: background,
              padding: tapPad,
              selected: tokens[i].uci == selectedUci,
              dimmed: hasSelection && tokens[i].uci != selectedUci,
            ),
          ],
        ],
      ),
    );
  }

  Widget _move(
    BuildContext context,
    TobyPredictionToken token, {
    required Color background,
    required EdgeInsets padding,
    required bool selected,
    required bool dimmed,
  }) {
    // Selection reads through the type alone (and the arrow on the board).
    final weight = selected
        ? FontWeight.w800
        : dimmed || muted
        ? FontWeight.w500
        : FontWeight.w700;
    return Semantics(
      button: true,
      selected: selected,
      label: '${token.move}, ${token.chance}',
      hint: selected ? 'Hide arrow' : 'Show arrow on the board',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onMoveTap == null ? null : () => onMoveTap!(token),
          child: Padding(
            padding: padding.copyWith(left: 5.sp),
            child: Text(
              token.move,
              maxLines: 1,
              softWrap: false,
              style: AppTypography.textSmMedium.copyWith(
                color: context.accentInk(token.hue, on: background),
                fontSize: 14.sp,
                fontWeight: weight,
                height: 1.3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
