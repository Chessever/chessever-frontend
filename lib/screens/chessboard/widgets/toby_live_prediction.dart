/// Toby's live prediction at the end of the notation: who is likelier to win
/// from here (a White / Draw / Black capsule) and the moves Toby expects
/// next, each in its own hue. Tapping a move draws its arrow on the board in
/// that hue.
///
/// The capsule carries Toby's credit ([kTobyAttribution]): a tap or long
/// press shows it, and screen readers hear it with the chances and the moves.
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
import 'package:flutter/rendering.dart';
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
    required this.move,
    required this.hue,
  });

  /// 0 for the likeliest move.
  final int rank;
  final String uci;

  /// "34%", or "<1%".
  final String chance;

  /// "24.Nf6" / "24…Nf6".
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

/// Which token a tap at [x] lands on: the token whose horizontal extent
/// holds [x], else the nearest one within [slop]. Null entries are tokens
/// not on screen (cut by the ellipsis).
int? tobyTokenAtX(
  List<({double left, double right})?> extents,
  double x, {
  required double slop,
}) {
  int? best;
  var bestDistance = double.infinity;
  for (var i = 0; i < extents.length; i++) {
    final extent = extents[i];
    if (extent == null) continue;
    final distance = x < extent.left
        ? extent.left - x
        : x > extent.right
        ? x - extent.right
        : 0.0;
    if (distance < bestDistance) {
      bestDistance = distance;
      best = i;
    }
  }
  return bestDistance <= slop ? best : null;
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

/// The live prediction block. Builds nothing when the board is not live at
/// its last move, when Toby cannot read the position, or when the reader is
/// refused (no paywall in the notation).
class TobyLivePrediction extends ConsumerStatefulWidget {
  const TobyLivePrediction({
    super.key,
    required this.params,
    this.onLayoutChange,
  });

  final ChessBoardProviderParams params;

  /// Called during build, before layout, whenever the block appears or
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

/// The shortest the tappable prediction line may be, as every tap target.
const double _minTapExtent = 44;

/// How far beside a move a tap still picks it.
const double _tapSlop = 12;

class _TobyLivePredictionState extends ConsumerState<TobyLivePrediction> {
  final GlobalKey _lineKey = GlobalKey();

  /// The reader was refused (sign-in or Premium): nothing more is asked on
  /// this board.
  bool _refused = false;

  String? _requestFen;
  TobyRequest? _request;

  /// The last position chances shown, held while the next reading comes.
  TobyWdl? _heldWdl;
  bool _visible = false;

  List<({int start, int end})> _tokenRanges = const [];
  List<TobyPredictionToken> _tokens = const [];

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
    // quiet line, at the same height. Before anything was ever shown (or
    // when the budget ran out with nothing), stay out of the notation
    // rather than flash a placeholder.
    if (shown == null &&
        (reading.status == TobyStatus.busy || _heldWdl == null)) {
      _setVisible(false);
      return const SizedBox.shrink();
    }

    final wdl = shown?.positionWdl ?? _heldWdl;
    if (shown?.positionWdl != null) _heldWdl = shown!.positionWdl;
    _setVisible(true);

    final muted = shown != null && !shown.isFinal;
    final tokens = shown == null
        ? const <TobyPredictionToken>[]
        : tobyPredictionTokens(shown, liveFen);
    final selection = ref.watch(tobyArrowProvider(_gameId));
    final selectedUci = selection != null && selection.fen == liveFen
        ? selection.uci
        : null;

    return Padding(
      padding: EdgeInsets.only(top: 10.sp),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TobyWdlCapsule(wdl: wdl),
          _buildLine(
            context,
            tokens: tokens,
            fen: liveFen,
            muted: muted,
            selectedUci: selectedUci,
          ),
        ],
      ),
    );
  }

  Widget _buildLine(
    BuildContext context, {
    required List<TobyPredictionToken> tokens,
    required String fen,
    required bool muted,
    required String? selectedUci,
  }) {
    final colors = context.colors;
    final paper = Color.alphaBlend(
      colors.surfaceRecessed.withValues(alpha: 0.3),
      colors.background,
    );
    final quietStyle = AppTypography.textXsMedium.copyWith(
      color: context.textInk(0.6),
      fontSize: 12.sp,
      fontWeight: FontWeight.w500,
      height: 1.2,
    );

    // One line height for the moves and the thinking placeholder, so the
    // block never changes height between readings.
    final lineStrut = StrutStyle(
      fontSize: 13.sp,
      height: 1.2,
      forceStrutHeight: true,
    );

    // The line is a tap target (it toggles board arrows), so it is at least
    // [_minTapExtent] tall; the text sits centred in it.
    Widget lineBox(Widget child) => ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _minTapExtent),
      child: Align(alignment: AlignmentDirectional.centerStart, child: child),
    );

    if (tokens.isEmpty) {
      _tokens = const [];
      _tokenRanges = const [];
      return lineBox(
        Text(
          'Toby is thinking…',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: quietStyle,
          strutStyle: lineStrut,
        ),
      );
    }

    // Selection reads through the type alone: the selected move stays bold
    // while the others drop to the regular weight. The network stage (a
    // first, quicker reading) is set lighter too, never fainter: every ink
    // keeps its full contrast on the paper.
    final hasSelection =
        selectedUci != null && tokens.any((token) => token.uci == selectedUci);

    final spans = <InlineSpan>[];
    final ranges = <({int start, int end})>[];
    var offset = 0;
    for (final token in tokens) {
      if (spans.isNotEmpty) {
        spans.add(TextSpan(text: ', ', style: quietStyle));
        offset += 2;
      }
      final selected = token.uci == selectedUci;
      final ink = context.accentInk(token.hue, on: paper);
      final light = muted || (hasSelection && !selected);
      final chanceText = '${token.chance} ';
      spans.add(
        TextSpan(
          text: chanceText,
          style: AppTypography.textXsMedium.copyWith(
            color: ink,
            fontSize: 12.sp,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontFeatures: const [FontFeature.tabularFigures()],
            height: 1.2,
          ),
        ),
      );
      spans.add(
        TextSpan(
          text: token.move,
          style: AppTypography.textXsMedium.copyWith(
            color: ink,
            fontSize: 13.sp,
            fontWeight: selected
                ? FontWeight.w800
                : light
                ? FontWeight.w500
                : FontWeight.w700,
            letterSpacing: -0.1,
            height: 1.2,
          ),
        ),
      );
      final start = offset;
      offset += chanceText.length + token.move.length;
      ranges.add((start: start, end: offset));
    }
    _tokens = tokens;
    _tokenRanges = ranges;

    return Semantics(
      container: true,
      label:
          'Toby predicts ${tokens.map((t) => t.text).join(', ')}. '
          '$kTobyAttribution',
      customSemanticsActions: {
        for (final token in tokens)
          CustomSemanticsAction(label: 'Show arrow for ${token.move}'): () =>
              _toggle(token, fen),
      },
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => _onTapUp(details, fen),
          child: lineBox(
            Text.rich(
              TextSpan(children: spans),
              key: _lineKey,
              strutStyle: lineStrut,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
        ),
      ),
    );
  }

  void _onTapUp(TapUpDetails details, String fen) {
    final paragraph = _lineKey.currentContext?.findRenderObject();
    if (paragraph is! RenderParagraph || !paragraph.hasSize) return;
    final local = paragraph.globalToLocal(details.globalPosition);
    final extents = <({double left, double right})?>[];
    for (final range in _tokenRanges) {
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: range.start, extentOffset: range.end),
      );
      final visible = boxes.where((box) => box.left < paragraph.size.width);
      if (visible.isEmpty) {
        extents.add(null);
        continue;
      }
      extents.add((
        left: visible.map((box) => box.left).reduce(math.min),
        right: visible
            .map((box) => box.right)
            .reduce(math.max)
            .clamp(0.0, paragraph.size.width)
            .toDouble(),
      ));
    }
    final index = tobyTokenAtX(extents, local.dx, slop: _tapSlop);
    if (index == null || index >= _tokens.length) return;
    _toggle(_tokens[index], fen);
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

/// White / Draw / Black chances as one horizontal capsule, each share as
/// wide as its chance (with a floor so a sliver stays visible) and its
/// number centred inside when it fits.
class TobyWdlCapsule extends StatelessWidget {
  const TobyWdlCapsule({super.key, required this.wdl});

  final TobyWdl? wdl;

  static const Duration _motion = Duration(milliseconds: 300);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isLight = context.isLightTheme;
    final height = 16.sp;
    final radius = BorderRadius.circular(height / 2);
    final drawFill = isLight
        ? const Color(0xFFB3BEBF)
        : const Color(0xFF5C5C60);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(constraints.maxWidth, 184.sp);
        final wdl = this.wdl;
        if (wdl == null) {
          return _credited(
            label: 'Win chances loading',
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: drawFill.withValues(alpha: 0.35),
                borderRadius: radius,
              ),
            ),
          );
        }
        final percentages = wdl.percentages;
        final widths = tobyWdlSegmentWidths(
          percentages,
          width,
          minSegment: 6.sp,
        );
        final textScaler = MediaQuery.textScalerOf(context);
        final labelStyle = AppTypography.textXsMedium.copyWith(
          fontSize: 10.sp,
          fontWeight: FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
          height: 1.0,
          letterSpacing: 0,
        );
        bool fits(int value, double segment) {
          if (value <= 0) return false;
          final painter = TextPainter(
            text: TextSpan(text: '$value', style: labelStyle),
            textDirection: TextDirection.ltr,
            textScaler: textScaler,
            maxLines: 1,
          )..layout();
          final ok =
              painter.width + 8.sp <= segment && painter.height <= height;
          painter.dispose();
          return ok;
        }

        Widget label(int value, double segment, Color ink) {
          if (!fits(value, segment)) return const SizedBox.shrink();
          return Center(
            child: Text(
              '$value',
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.center,
              style: labelStyle.copyWith(color: ink),
              textHeightBehavior: const TextHeightBehavior(
                applyHeightToFirstAscent: false,
                applyHeightToLastDescent: false,
              ),
            ),
          );
        }

        // One soft rim in the page's own ink, so the end share that would
        // melt into the page (white on paper, black on the dark panel) keeps
        // its edge. Never a contrasting outline.
        final rim = isLight
            ? colors.textPrimary.withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.12);
        final whiteInk = isLight ? colors.textPrimary : colors.evalBlack;
        final drawInk = isLight ? colors.textPrimary : Colors.white;
        const blackInk = Colors.white;

        return _credited(
          label: tobyWdlSemantics(percentages),
          child: ClipRRect(
            borderRadius: radius,
            child: Container(
              width: width,
              height: height,
              foregroundDecoration: BoxDecoration(
                border: Border.all(color: rim),
                borderRadius: radius,
              ),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: _motion,
                    curve: Curves.easeOutCubic,
                    width: widths[0],
                    color: colors.evalWhite,
                    child: label(percentages.white, widths[0], whiteInk),
                  ),
                  AnimatedContainer(
                    duration: _motion,
                    curve: Curves.easeOutCubic,
                    width: widths[1],
                    color: drawFill,
                    child: label(percentages.draw, widths[1], drawInk),
                  ),
                  Expanded(
                    child: ColoredBox(
                      color: colors.evalBlack,
                      child: label(percentages.black, widths[2], blackInk),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// The capsule as one tap target that shows Toby's credit, heard with the
  /// chances by screen readers.
  static Widget _credited({required String label, required Widget child}) =>
      Semantics(
        container: true,
        label: '$label. $kTobyAttribution',
        child: ExcludeSemantics(
          child: Tooltip(
            message: kTobyAttribution,
            triggerMode: TooltipTriggerMode.tap,
            showDuration: const Duration(seconds: 4),
            excludeFromSemantics: true,
            child: child,
          ),
        ),
      );
}
