/// "Toby predicts": a panel pinned under the notation of a live game, with
/// two labelled rows. Result: White / Draw / Black chances as a legend over
/// one stacked bar. Next move: the three moves Toby expects, each in its own
/// hue with its chance. Tapping a move draws its arrow on the board in that
/// hue.
///
/// The title carries Toby's credit ([kTobyAttribution]): a tap shows it, and
/// screen readers hear it with the chances and the moves.
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

/// The widths of the capsule's White, Draw and Black segments in [total]:
/// proportional to [percentages], except that a share above zero never
/// draws narrower than [minSegment] (so a 1% sliver stays visible). A zero
/// share draws nothing. The three always add up to [total].
List<double> tobyWdlSegmentWidths(
  ({int white, int draw, int black}) percentages,
  double total, {
  required double minSegment,
}) {
  final values = [percentages.white, percentages.draw, percentages.black];
  if (total <= 0) return const [0, 0, 0];
  final positive = [
    for (var i = 0; i < 3; i++)
      if (values[i] > 0) i,
  ];
  if (positive.isEmpty) return [total / 3, total / 3, total / 3];
  final floor = math.min(minSegment, total / positive.length);
  final pinned = <int>{};
  final widths = List<double>.filled(3, 0);
  while (true) {
    final free = [
      for (final i in positive)
        if (!pinned.contains(i)) i,
    ];
    final room = total - floor * pinned.length;
    final freeSum = free.fold<int>(0, (sum, i) => sum + values[i]);
    var changed = false;
    for (final i in free) {
      final width = freeSum == 0 ? 0.0 : room * values[i] / freeSum;
      if (width < floor) {
        pinned.add(i);
        changed = true;
      }
      widths[i] = width;
    }
    if (!changed) break;
  }
  for (final i in pinned) {
    widths[i] = floor;
  }
  return widths;
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// The "Toby predicts" panel. Builds nothing when the board is not live at
/// its last move, when Toby cannot read the position, or when the reader is
/// refused (no paywall under the notation).
class TobyLivePrediction extends ConsumerStatefulWidget {
  const TobyLivePrediction({
    super.key,
    required this.params,
    this.onLayoutChange,
  });

  final ChessBoardProviderParams params;

  /// Called during build, before layout, whenever the panel appears or
  /// disappears, so the notation above can hold its scroll anchor.
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

/// The shortest a tappable move may be, as every tap target.
const double _minTapExtent = 44;

class _TobyLivePredictionState extends ConsumerState<TobyLivePrediction> {
  /// The reader was refused (sign-in or Premium): nothing more is asked on
  /// this board.
  bool _refused = false;

  String? _requestFen;
  TobyRequest? _request;

  /// The last position chances shown, held while the next reading comes.
  TobyWdl? _heldWdl;
  bool _visible = false;

  String get _gameId => widget.params.game.gameId;

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

  // Appears at full size in one frame: the notation above re-pins its scroll
  // once ([TobyLivePrediction.onLayoutChange]), which a growing panel would
  // outrun.
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

    if (liveFen == null || _refused) {
      _setVisible(false);
      return const SizedBox.shrink();
    }
    final request = _requestFor(liveFen);
    if (request == null) {
      _setVisible(false);
      return const SizedBox.shrink();
    }

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
        _setVisible(false);
        return const SizedBox.shrink();
      case TobyStatus.unavailable:
      case TobyStatus.notApplicable:
        _setVisible(false);
        return const SizedBox.shrink();
    }

    // Thinking about a new position: hold the last chances shown, with a
    // quiet moves row, at the same height. Before anything was ever shown
    // (or when the budget ran out with nothing), stay away rather than flash
    // a placeholder.
    if (shown == null &&
        (reading.status == TobyStatus.busy || _heldWdl == null)) {
      _setVisible(false);
      return const SizedBox.shrink();
    }

    final wdl = shown?.positionWdl ?? _heldWdl;
    if (shown?.positionWdl != null) _heldWdl = shown!.positionWdl;
    _setVisible(true);

    final tokens = shown == null
        ? const <TobyPredictionToken>[]
        : tobyPredictionTokens(shown, liveFen);
    final selection = ref.watch(tobyArrowProvider(_gameId));
    final selectedUci = selection != null && selection.fen == liveFen
        ? selection.uci
        : null;

    return TobyPredictsPanel(
      wdl: wdl,
      tokens: tokens,
      thinking: shown == null,
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

/// The panel itself, free of providers: a title, then a Result row (legend
/// over one stacked bar) and a Next move row (three tappable moves, most
/// likely first). Both rows share one label column.
class TobyPredictsPanel extends StatelessWidget {
  const TobyPredictsPanel({
    super.key,
    required this.wdl,
    required this.tokens,
    this.thinking = false,
    this.muted = false,
    this.selectedUci,
    this.onMoveTap,
  });

  final TobyWdl? wdl;
  final List<TobyPredictionToken> tokens;

  /// Toby is reading a new position: the moves row says so.
  final bool thinking;

  /// A first, quicker reading: the moves are set lighter, never fainter.
  final bool muted;
  final String? selectedUci;
  final ValueChanged<TobyPredictionToken>? onMoveTap;

  static const Duration _motion = Duration(milliseconds: 300);

  /// Space above the legend inside the Result row.
  static const double _legendInset = 4;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // One tonal step above the notation panel it sits in: no outline, no
    // shadow.
    final tray = Color.alphaBlend(
      colors.surfaceRecessed.withValues(alpha: 0.6),
      Color.alphaBlend(
        colors.surfaceRecessed.withValues(alpha: 0.3),
        colors.background,
      ),
    );
    final labelWidth = 76.sp;
    final rowLabel = AppTypography.textXsMedium.copyWith(
      color: context.textInk(0.55),
      fontSize: 12.sp,
      fontWeight: FontWeight.w500,
      height: 1.2,
    );

    // [top] puts the label on the first line of its row (the legend) rather
    // than between the legend and the bar.
    Widget labelled(String label, Widget child, {double? top}) => Row(
      crossAxisAlignment: top == null
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: top ?? 0),
          child: SizedBox(
            width: labelWidth,
            // Shrinks rather than clips under a large text size.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(label, maxLines: 1, style: rowLabel),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );

    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(8.sp, 4.sp, 8.sp, 8.sp),
      padding: EdgeInsets.fromLTRB(14.sp, 12.sp, 14.sp, 2.sp),
      decoration: BoxDecoration(
        color: tray,
        borderRadius: BorderRadius.circular(16.sp),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _title(context),
          SizedBox(height: 12.sp),
          labelled('Result', _result(context, tray), top: _legendInset.sp),
          SizedBox(height: 2.sp),
          labelled('Next move', _moves(context, tray, rowLabel)),
        ],
      ),
    );
  }

  /// "Toby predicts", which shows Toby's credit on a tap.
  Widget _title(BuildContext context) => Semantics(
    header: true,
    label: 'Toby predicts. $kTobyAttribution',
    child: ExcludeSemantics(
      child: Tooltip(
        message: kTobyAttribution,
        triggerMode: TooltipTriggerMode.tap,
        showDuration: const Duration(seconds: 4),
        excludeFromSemantics: true,
        child: Text(
          'Toby predicts',
          maxLines: 1,
          style: AppTypography.textSmMedium.copyWith(
            color: context.colors.textPrimary,
            fontSize: 14.sp,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
      ),
    ),
  );

  /// Legend over the bar: White at the bar's left end, Draw in the middle,
  /// Black at its right end, so each number sits by its share.
  Widget _result(BuildContext context, Color tray) {
    final wdl = this.wdl;
    final percentages = wdl?.percentages;
    final name = AppTypography.textXsMedium.copyWith(
      color: context.textInk(0.6),
      fontSize: 12.sp,
      fontWeight: FontWeight.w500,
      height: 1.2,
    );
    final value = name.copyWith(
      color: context.colors.textPrimary,
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    Widget entry(String label, int? share, Alignment alignment) => Expanded(
      child: Align(
        alignment: alignment,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignment,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '$label ', style: name),
                TextSpan(text: share == null ? '…' : '$share%', style: value),
              ],
            ),
            maxLines: 1,
          ),
        ),
      ),
    );

    return Semantics(
      container: true,
      label: percentages == null
          ? 'Result chances loading'
          : 'Result chances: ${tobyWdlSemantics(percentages)}',
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: _legendInset.sp),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  entry('White', percentages?.white, Alignment.centerLeft),
                  entry('Draw', percentages?.draw, Alignment.center),
                  entry('Black', percentages?.black, Alignment.centerRight),
                ],
              ),
              SizedBox(height: 6.sp),
              TobyWdlBar(wdl: wdl),
            ],
          ),
        ),
      ),
    );
  }

  /// The three likeliest moves, each a full-height tap target.
  Widget _moves(BuildContext context, Color tray, TextStyle quiet) {
    if (thinking || tokens.isEmpty) {
      return SizedBox(
        height: _minTapExtent,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Toby is thinking…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: quiet,
          ),
        ),
      );
    }
    // A ranked list read left to right, starting on the legend's left edge.
    // Not on the legend's three columns: under "White" a Black move would
    // read as White's.
    final hasSelection =
        selectedUci != null && tokens.any((token) => token.uci == selectedUci);
    return Align(
      alignment: Alignment.centerLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final token in tokens.take(3))
              _move(
                context,
                token,
                tray: tray,
                selected: token.uci == selectedUci,
                dimmed: hasSelection && token.uci != selectedUci,
                // The gap to the next move belongs to this one's tap area.
                trailing: token == tokens.take(3).last ? 0 : 22.sp,
              ),
          ],
        ),
      ),
    );
  }

  Widget _move(
    BuildContext context,
    TobyPredictionToken token, {
    required Color tray,
    required bool selected,
    required bool dimmed,
    required double trailing,
  }) {
    // Selection reads through the type alone (and the arrow on the board):
    // the selected move goes heavier, the others lighter. Every ink keeps
    // its full contrast on the tray.
    final ink = context.accentInk(token.hue, on: tray);
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
            height: _minTapExtent,
            padding: EdgeInsets.only(right: trailing),
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: token.san,
                    style: AppTypography.textSmMedium.copyWith(
                      color: ink,
                      fontSize: 15.sp,
                      fontWeight: weight,
                      height: 1.2,
                    ),
                  ),
                  TextSpan(
                    text: '  ${token.chance}',
                    style: AppTypography.textXsMedium.copyWith(
                      color: context.textInk(0.6),
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      height: 1.2,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// White / Draw / Black chances as one thin stacked bar, each share as wide
/// as its chance (with a floor so a sliver stays visible). The numbers live
/// in the legend above it.
class TobyWdlBar extends StatelessWidget {
  const TobyWdlBar({super.key, required this.wdl});

  final TobyWdl? wdl;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isLight = context.isLightTheme;
    final height = 8.sp;
    final radius = BorderRadius.circular(height / 2);
    final drawFill = isLight
        ? const Color(0xFFB3BEBF)
        : const Color(0xFF5C5C60);
    // One soft rim in the page's own ink, so the end share that would melt
    // into the tray (white on paper, black on the dark panel) keeps its
    // edge. Never a contrasting outline.
    final rim = isLight
        ? colors.textPrimary.withValues(alpha: 0.14)
        : Colors.white.withValues(alpha: 0.12);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final wdl = this.wdl;
        if (wdl == null) {
          return Container(
            height: height,
            decoration: BoxDecoration(
              color: drawFill.withValues(alpha: 0.35),
              borderRadius: radius,
            ),
          );
        }
        final widths = tobyWdlSegmentWidths(
          wdl.percentages,
          width,
          minSegment: 4.sp,
        );
        return ClipRRect(
          borderRadius: radius,
          child: Container(
            height: height,
            foregroundDecoration: BoxDecoration(
              border: Border.all(color: rim),
              borderRadius: radius,
            ),
            // Stretch: an empty share box would otherwise take no height.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedContainer(
                  duration: TobyPredictsPanel._motion,
                  curve: Curves.easeOutCubic,
                  width: widths[0],
                  color: colors.evalWhite,
                ),
                AnimatedContainer(
                  duration: TobyPredictsPanel._motion,
                  curve: Curves.easeOutCubic,
                  width: widths[1],
                  color: drawFill,
                ),
                Expanded(child: ColoredBox(color: colors.evalBlack)),
              ],
            ),
          ),
        );
      },
    );
  }
}
