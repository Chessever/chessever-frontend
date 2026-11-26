/// "Toby Predicts" at the end of the notation: the moves Toby expects at the
/// board's position, each in its own hue with its chance (tapping one draws
/// its arrow on the board in that hue), and under them the result chances
/// by player, "Gukesh 17%   Draw 76%   Sindarov 7%". "Toby Predicts:" is
/// dashed: a tap explains the chances and credits Toby.
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

/// A side as the chances line names it: the surname ("Carlsen" from
/// "Carlsen, Magnus"), else [fallback] ("White" / "Black") for a blank name.
String tobySideName(String? name, String fallback) {
  final surname = (name ?? '').split(',').first.trim();
  return surname.isEmpty ? fallback : surname;
}

/// A player as the chances line shows it: the surname.
typedef TobySide = ({String name});

/// "White 28, draw 57, Black 15".
String tobyWdlSemantics(({int white, int draw, int black}) percentages) =>
    'White ${percentages.white}, draw ${percentages.draw}, '
    'Black ${percentages.black}';

// ---------------------------------------------------------------------------
// Dashed hint
// ---------------------------------------------------------------------------

/// What a tap on "Toby Predicts:" explains, with the chances when known.
String tobyChanceExplanation(({int white, int draw, int black})? p) => [
  if (p != null)
    'White wins ${p.white}%, draw ${p.draw}%, Black wins ${p.black}%: '
        "Toby's prediction from this position, for players of these ratings "
        'at this time control.',
  kTobyAttribution,
].join('\n');

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

/// "Toby Predicts: 16…Qxd4 or 16…Qxc2 or 16…c5" after the last move, with
/// the result chances under it. Builds nothing when the board is not live at its last move, when
/// Toby cannot read the position, or when the reader is refused (no paywall
/// in the notation).
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
    // gets both lines at a fixed height from the first frame (placeholders
    // until the reading lands). Everyone else never gets the block, so it
    // never appears and then vanishes.
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
    final game = widget.params.game;
    final white = (name: tobySideName(game.whitePlayer.name, 'White'));
    final black = (name: tobySideName(game.blackPlayer.name, 'Black'));

    // Game over on the board: the result, in the same two lines.
    final over = tobyOverWdl(liveFen);
    if (over != null) {
      _setVisible(true);
      return TobyPredictsLine(
        white: white,
        black: black,
        wdl: over,
        tokens: const [],
        note: 'game over',
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

    if (shown?.positionWdl != null) _heldWdl = shown!.positionWdl;
    _setVisible(true);

    final tokens = shown == null
        ? const <TobyPredictionToken>[]
        : tobyPredictionTokens(shown, liveFen);
    final selection = ref.watch(tobyArrowProvider(_gameId));
    final selectedUci = selection != null && selection.fen == liveFen
        ? selection.uci
        : null;

    return TobyPredictsLine(
      white: white,
      black: black,
      wdl: _heldWdl,
      tokens: tokens,
      waiting: waiting,
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

/// Free of providers: "Toby Predicts:" (dashed, a tap explains it), then
/// the likeliest moves joined by "or", each in its arrow hue and tappable
/// with its chance (no tokens: "thinking…"); under it the result chances
/// by player, "Gukesh 17%   Draw 76%   Sindarov 7%".
class TobyPredictsLine extends StatelessWidget {
  const TobyPredictsLine({
    super.key,
    this.white = (name: 'White'),
    this.black = (name: 'Black'),
    this.wdl,
    required this.tokens,
    this.waiting = true,
    this.note,
    this.muted = false,
    this.selectedUci,
    this.onMoveTap,
  });

  final TobySide white;
  final TobySide black;
  final TobyWdl? wdl;
  final List<TobyPredictionToken> tokens;

  /// No moves yet: true while Toby is reading ("thinking…"), false when it
  /// gave up on this position ("not available").
  final bool waiting;

  /// Said in place of the moves when there are none to predict
  /// ("game over"); overrides [waiting].
  final String? note;

  /// The two lines' fixed heights: the block never changes height between
  /// readings, placeholders, longer names or larger text (a line too wide
  /// shrinks to fit rather than wrap).
  static double get movesLineHeight => 34.sp;
  static double get chancesLineHeight => 24.sp;

  /// A first, quicker reading: the moves are set lighter, never fainter.
  final bool muted;
  final String? selectedUci;
  final ValueChanged<TobyPredictionToken>? onMoveTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final shares = wdl?.percentages;
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
    // Every piece fills the line's height, so the moves are tall taps.
    final line = movesLineHeight;

    Widget fixedLine(double height, Widget child) => SizedBox(
      height: height,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: child,
      ),
    );

    final moves = fixedLine(
      line,
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: line,
            child: Center(
              child: TobyDashedHint(
                text: 'Toby Predicts:',
                style: quiet,
                message: tobyChanceExplanation(shares),
                semanticsLabel: 'Toby Predicts. $kTobyAttribution',
              ),
            ),
          ),
          if (tokens.isEmpty)
            Text(
              ' ${note ?? (waiting ? 'thinking…' : 'not available')}',
              style: quiet,
            ),
          for (var i = 0; i < tokens.length && i < 3; i++) ...[
            _move(
              context,
              tokens[i],
              background: background,
              height: line,
              selected: tokens[i].uci == selectedUci,
              dimmed: hasSelection && tokens[i].uci != selectedUci,
            ),
          ],
        ],
      ),
    );

    final value = quiet.copyWith(
      color: colors.textPrimary,
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    // Before the first reading the numbers wait as "…", names in place.
    String percentText(int? percent) => percent == null ? '…' : '$percent%';

    // A player's share: surname and chance.
    Widget side(TobySide side, int? percent) => Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '${side.name} ', style: quiet),
          TextSpan(text: percentText(percent), style: value),
        ],
      ),
      maxLines: 1,
      softWrap: false,
    );

    // Space alone parts the three: no glyph between them.
    final gap = SizedBox(width: 14.sp);

    return Padding(
      padding: EdgeInsets.only(top: 2.sp, bottom: 4.sp),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          moves,
          Semantics(
            label: shares == null
                ? 'Result chances loading'
                : 'Result chances: ${white.name} ${shares.white}, '
                      'draw ${shares.draw}, ${black.name} ${shares.black}',
            child: ExcludeSemantics(
              child: fixedLine(
                chancesLineHeight,
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    side(white, shares?.white),
                    gap,
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: 'Draw ', style: quiet),
                          TextSpan(
                            text: percentText(shares?.draw),
                            style: value,
                          ),
                        ],
                      ),
                      maxLines: 1,
                      softWrap: false,
                    ),
                    gap,
                    side(black, shares?.black),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _move(
    BuildContext context,
    TobyPredictionToken token, {
    required Color background,
    required double height,
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
          child: Container(
            height: height,
            // Space alone parts the moves: no "or", no glyph.
            padding: EdgeInsets.only(left: 12.sp),
            alignment: Alignment.center,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: token.move,
                    style: AppTypography.textSmMedium.copyWith(
                      color: context.accentInk(token.hue, on: background),
                      fontSize: 14.sp,
                      fontWeight: weight,
                      height: 1.3,
                    ),
                  ),
                  TextSpan(
                    text: ' ${token.chance}',
                    style: AppTypography.textSmMedium.copyWith(
                      color: context.accentInk(token.hue, on: background),
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      height: 1.3,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              softWrap: false,
            ),
          ),
        ),
      ),
    );
  }
}
