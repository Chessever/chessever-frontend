import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/screens/board_editor/board_editor_state.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' hide Board;
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

class BoardEditorScreen extends ConsumerStatefulWidget {
  const BoardEditorScreen({super.key});

  @override
  ConsumerState<BoardEditorScreen> createState() => _BoardEditorScreenState();
}

class _BoardEditorScreenState extends ConsumerState<BoardEditorScreen> {
  String? _analysisPgnOverride;
  String? _analysisPgnStartFen;
  String _analysisWhiteName = 'White';
  String _analysisBlackName = 'Black';

  String _fenPositionKey(String fen) =>
      fen.trim().split(RegExp(r'\s+')).take(4).join(' ');

  void _clearPgnOverride() {
    _analysisPgnOverride = null;
    _analysisPgnStartFen = null;
    _analysisWhiteName = 'White';
    _analysisBlackName = 'Black';
  }

  String? _analysisValidationError(BoardEditorState editorState) {
    bool hasWhiteKing = false;
    bool hasBlackKing = false;
    for (final piece in editorState.pieces.values) {
      if (piece.role == Role.king) {
        if (piece.color == Side.white) hasWhiteKing = true;
        if (piece.color == Side.black) hasBlackKing = true;
      }
    }
    if (!hasWhiteKing || !hasBlackKing) {
      return 'Position must include both kings before analysis.';
    }

    try {
      final setup = Setup.parseFen(editorState.fullFen);
      Chess.fromSetup(setup);
    } catch (_) {
      return 'Illegal position. Check king safety, side to move, and castling rights.';
    }
    return null;
  }

  void _showSnack(String message, {Color? backgroundColor}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: kWhiteColor)),
        backgroundColor:
            backgroundColor ?? kBlack2Color.withValues(alpha: 0.95),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _onDone() {
    final editorState = ref.read(boardEditorProvider);
    final validationError = _analysisValidationError(editorState);
    if (validationError != null) {
      _showSnack(
        validationError,
        backgroundColor: kRedColor.withValues(alpha: 0.9),
      );
      return;
    }

    final fen = editorState.fullFen;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final usePgnOverride =
        _analysisPgnOverride != null &&
        _analysisPgnStartFen != null &&
        _fenPositionKey(_analysisPgnStartFen!) == _fenPositionKey(fen);

    final whiteName = usePgnOverride ? _analysisWhiteName : 'White';
    final blackName = usePgnOverride ? _analysisBlackName : 'Black';

    final pgn =
        usePgnOverride
            ? _analysisPgnOverride!
            : '[Event "Board Editor"]\n'
                '[Site "ChessEver"]\n'
                '[Date "${DateTime.now().toIso8601String().split('T')[0]}"]\n'
                '[White "$whiteName"]\n'
                '[Black "$blackName"]\n'
                '[Result "*"]\n'
                '[FEN "$fen"]\n'
                '[SetUp "1"]\n'
                '\n*';

    final whitePlayer = PlayerCard(
      name: whiteName,
      federation: '',
      title: '',
      rating: 0,
      countryCode: '',
      team: null,
      fideId: null,
    );

    final blackPlayer = PlayerCard(
      name: blackName,
      federation: '',
      title: '',
      rating: 0,
      countryCode: '',
      team: null,
      fideId: null,
    );

    final game = GamesTourModel(
      gameId: 'editor_$timestamp',
      whitePlayer: whitePlayer,
      blackPlayer: blackPlayer,
      whiteTimeDisplay: '--:--',
      blackTimeDisplay: '--:--',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: GameStatus.unknown,
      roundId: 'board_editor',
      tourId: 'board_editor',
      pgn: pgn,
    );

    ref.read(chessboardViewFromProviderNew.notifier).state =
        ChessboardView.tour;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => ChessBoardScreenNew(
              currentIndex: 0,
              games: [game],
              hideEventInfo: true,
              showGamebaseButton: false,
              disableGamebaseOverlayByDefault: true,
            ),
      ),
    );
  }

  Future<void> _pasteFen() async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboard?.text?.trim();
    if (text == null || text.isEmpty) {
      _showSnack('Clipboard is empty');
      return;
    }

    // Try parsing as FEN
    try {
      Setup.parseFen(text);
      setState(_clearPgnOverride);
      ref.read(boardEditorProvider.notifier).loadFen(text);
    } catch (_) {
      _showSnack(
        'Invalid FEN',
        backgroundColor: kRedColor.withValues(alpha: 0.9),
      );
    }
  }

  Future<void> _pastePgn() async {
    final controller = TextEditingController();
    final pgn = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Padding(
            padding: EdgeInsets.all(20.sp),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Paste PGN',
                  style: AppTypography.textLgMedium.copyWith(
                    color: kWhiteColor,
                  ),
                ),
                SizedBox(height: 12.h),
                TextField(
                  controller: controller,
                  maxLines: 8,
                  style: AppTypography.textSmRegular.copyWith(
                    color: kWhiteColor,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    hintText: '1. e4 e5 2. Nf3 ...',
                    hintStyle: AppTypography.textSmRegular.copyWith(
                      color: kWhiteColor.withValues(alpha: 0.3),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF111111),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8.br),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                SizedBox(height: 12.h),
                ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(controller.text),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kWhiteColor,
                    foregroundColor: kBackgroundColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.br),
                    ),
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                  ),
                  child: Text(
                    'Load',
                    style: AppTypography.textMdMedium.copyWith(
                      color: kBackgroundColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (pgn == null || pgn.trim().isEmpty) return;

    try {
      final rawPgn = pgn.trim();
      final game = PgnGame.parsePgn(rawPgn);
      // Determine starting position
      final fenHeader = game.headers['FEN'];
      final startPos =
          fenHeader != null
              ? Chess.fromSetup(Setup.parseFen(fenHeader))
              : Chess.initial;

      final startFen = startPos.fen;
      final whiteName = (game.headers['White'] ?? 'White').trim();
      final blackName = (game.headers['Black'] ?? 'Black').trim();

      setState(() {
        _analysisPgnOverride = rawPgn;
        _analysisPgnStartFen = startFen;
        _analysisWhiteName = whiteName.isNotEmpty ? whiteName : 'White';
        _analysisBlackName = blackName.isNotEmpty ? blackName : 'Black';
      });
      ref.read(boardEditorProvider.notifier).loadFen(startFen);
      _showSnack('PGN loaded. Analysis will keep moves and headers.');
    } catch (e) {
      _showSnack(
        'Failed to parse PGN',
        backgroundColor: kRedColor.withValues(alpha: 0.9),
      );
    }
  }

  void _copyFen() {
    final fen = ref.read(boardEditorProvider).fullFen;
    Clipboard.setData(ClipboardData(text: fen));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('FEN copied', style: TextStyle(color: kWhiteColor)),
        backgroundColor: kBlack2Color.withValues(alpha: 0.95),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(boardEditorProvider);
    final boardSettingsAsync = ref.watch(boardSettingsProviderNew);
    final boardSettings =
        boardSettingsAsync.valueOrNull ?? const BoardSettingsNew();
    final screenWidth = MediaQuery.of(context).size.width;
    final showEval = editorState.isEvaluatable;
    final evalBarWidth = 20.sp;
    final squareSize = screenWidth / 8;

    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // App bar
            _buildAppBar(),

            Expanded(
              child: Column(
                children: [
                  // Top controls: Reset/Clear, Side-to-move, Castling
                  _TopControls(
                    editorState: editorState,
                    onReset: () {
                      HapticFeedback.mediumImpact();
                      setState(_clearPgnOverride);
                      ref.read(boardEditorProvider.notifier).reset();
                    },
                    onClear: () {
                      HapticFeedback.mediumImpact();
                      setState(_clearPgnOverride);
                      ref.read(boardEditorProvider.notifier).clear();
                    },
                    onSideToMove: (side) {
                      HapticFeedback.selectionClick();
                      setState(_clearPgnOverride);
                      ref
                          .read(boardEditorProvider.notifier)
                          .setSideToMove(side);
                    },
                    onToggleCastling: ({
                      bool? whiteKingside,
                      bool? whiteQueenside,
                      bool? blackKingside,
                      bool? blackQueenside,
                    }) {
                      HapticFeedback.selectionClick();
                      setState(_clearPgnOverride);
                      ref
                          .read(boardEditorProvider.notifier)
                          .toggleCastling(
                            whiteKingside: whiteKingside,
                            whiteQueenside: whiteQueenside,
                            blackKingside: blackKingside,
                            blackQueenside: blackQueenside,
                          );
                    },
                  ),

                  // Board + Eval bar row
                  _BoardWithEvalBar(
                    editorState: editorState,
                    boardSettings: boardSettings,
                    screenWidth: screenWidth,
                    evalBarWidth: evalBarWidth,
                    showEval: showEval,
                  ),

                  // Piece Tray
                  _PieceTray(
                    pieceAssets: boardSettings.pieceAssets,
                    squareSize: squareSize,
                    selectedPiece: editorState.selectedPiece,
                    isDeleteMode: editorState.isDeleteMode,
                    onSelectPiece: (piece) {
                      HapticFeedback.selectionClick();
                      setState(_clearPgnOverride);
                      ref.read(boardEditorProvider.notifier).selectPiece(piece);
                    },
                    onToggleDeleteMode: () {
                      HapticFeedback.selectionClick();
                      setState(_clearPgnOverride);
                      ref.read(boardEditorProvider.notifier).toggleDeleteMode();
                    },
                    onDeleteLongPress: () {
                      HapticFeedback.heavyImpact();
                      setState(_clearPgnOverride);
                      ref.read(boardEditorProvider.notifier).clear();
                    },
                    onFlipBoard: () {
                      HapticFeedback.mediumImpact();
                      ref.read(boardEditorProvider.notifier).flipBoard();
                    },
                  ),

                  // FEN Bar
                  _FenBar(fen: editorState.fullFen, onCopy: _copyFen),

                  // Action buttons
                  _ActionRow(onPasteFen: _pasteFen, onPastePgn: _pastePgn),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: kWhiteColor,
              size: 20.sp,
            ),
          ),
          Expanded(
            child: Text(
              'Board Editor',
              style: AppTypography.textLgMedium.copyWith(color: kWhiteColor),
              textAlign: TextAlign.center,
            ),
          ),
          GestureDetector(
            onTap: _onDone,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: kWhiteColor,
                borderRadius: BorderRadius.circular(8.br),
              ),
              child: Text(
                'Analyze',
                style: AppTypography.textSmMedium.copyWith(
                  color: kBackgroundColor,
                ),
              ),
            ),
          ),
          SizedBox(width: 4.w),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Board + Eval Bar
// ---------------------------------------------------------------------------
class _BoardWithEvalBar extends ConsumerWidget {
  final BoardEditorState editorState;
  final BoardSettingsNew boardSettings;
  final double screenWidth;
  final double evalBarWidth;
  final bool showEval;

  const _BoardWithEvalBar({
    required this.editorState,
    required this.boardSettings,
    required this.screenWidth,
    required this.evalBarWidth,
    required this.showEval,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    double? evaluation;
    int? mate;
    bool isEvaluating = false;
    final fen = editorState.fullFen;

    if (showEval) {
      final evalAsync = ref.watch(
        gameCardEvalWithStockfishFallbackProvider(fen),
      );
      evalAsync.when(
        data: (cloud) {
          final pv = cloud.pvs.firstOrNull;
          if (pv != null) {
            final normalized = _normalizePvToWhitePerspective(pv);
            evaluation = normalized.eval;
            if (normalized.isMate && normalized.mate != 0) {
              mate = normalized.mate;
            }
          }
        },
        loading: () => isEvaluating = true,
        error: (_, __) {},
      );
    }

    return SingleMotionBuilder(
      motion: CupertinoMotion.snappy(),
      value: showEval ? 1.0 : 0.0,
      builder: (context, animVal, _) {
        final clamped = animVal.clamp(0.0, 1.0);
        final currentEvalWidth = evalBarWidth * clamped;
        final boardSize = screenWidth - currentEvalWidth;

        return Row(
          children: [
            if (clamped > 0.01)
              SizedBox(
                width: currentEvalWidth,
                height: boardSize,
                child: Opacity(
                  opacity: clamped,
                  child: EvaluationBarWidget(
                    width: currentEvalWidth,
                    height: boardSize,
                    evaluation: evaluation,
                    mate: mate,
                    isEvaluating: isEvaluating,
                    isFlipped: editorState.orientation == Side.black,
                    isWhiteToMove: editorState.sideToMove == Side.white,
                    positionKey: fen,
                  ),
                ),
              ),
            _EditorTapWrapper(
              boardSize: boardSize,
              orientation: editorState.orientation,
              pointerMode: editorState.pointerMode,
              onTapSquare: (square) {
                ref.read(boardEditorProvider.notifier).onTapSquare(square);
              },
              child: ChessboardEditor(
                size: boardSize,
                orientation: editorState.orientation,
                pieces: editorState.pieces,
                pointerMode: editorState.pointerMode,
                squareHighlights: editorState.selectedDragSquare != null
                    ? IMap({
                        editorState.selectedDragSquare!: SquareHighlight(
                          details: boardSettings.colorScheme.selected,
                        ),
                      })
                    : const IMap.empty(),
                settings: ChessboardSettings(
                  colorScheme: boardSettings.colorScheme,
                  pieceAssets: boardSettings.pieceAssets,
                  enableCoordinates: true,
                  dragFeedbackScale: 2.0,
                  dragFeedbackOffset: const Offset(0.0, -1.0),
                ),
                onEditedSquare: (square) {
                  ref.read(boardEditorProvider.notifier).onEditedSquare(square);
                },
                onDroppedPiece: (origin, dest, piece) {
                  ref
                      .read(boardEditorProvider.notifier)
                      .onDroppedPiece(origin, dest, piece);
                },
                onDiscardedPiece: (square) {
                  ref
                      .read(boardEditorProvider.notifier)
                      .onDiscardedPiece(square);
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Tap-to-move wrapper
// ---------------------------------------------------------------------------
class _EditorTapWrapper extends StatefulWidget {
  final double boardSize;
  final Side orientation;
  final EditorPointerMode pointerMode;
  final void Function(Square square) onTapSquare;
  final Widget child;

  const _EditorTapWrapper({
    required this.boardSize,
    required this.orientation,
    required this.pointerMode,
    required this.onTapSquare,
    required this.child,
  });

  @override
  State<_EditorTapWrapper> createState() => _EditorTapWrapperState();
}

class _EditorTapWrapperState extends State<_EditorTapWrapper> {
  Offset? _pointerDownPos;

  Square? _offsetToSquare(Offset offset) {
    final squareSize = widget.boardSize / 8;
    final x = (offset.dx / squareSize).floor();
    final y = (offset.dy / squareSize).floor();
    final orientX = widget.orientation == Side.black ? 7 - x : x;
    final orientY = widget.orientation == Side.black ? y : 7 - y;
    if (orientX >= 0 && orientX <= 7 && orientY >= 0 && orientY <= 7) {
      return Square.fromCoords(File(orientX), Rank(orientY));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        if (widget.pointerMode == EditorPointerMode.drag) {
          _pointerDownPos = event.localPosition;
        }
      },
      onPointerUp: (event) {
        final downPos = _pointerDownPos;
        _pointerDownPos = null;
        if (downPos == null || widget.pointerMode != EditorPointerMode.drag) {
          return;
        }
        // Only treat as tap if pointer didn't move much (not a drag)
        final delta = (event.localPosition - downPos).distance;
        if (delta > widget.boardSize / 8 * 0.5) return;
        final square = _offsetToSquare(event.localPosition);
        if (square != null) {
          widget.onTapSquare(square);
        }
      },
      onPointerCancel: (_) => _pointerDownPos = null,
      child: widget.child,
    );
  }
}

({double eval, bool isMate, int mate}) _normalizePvToWhitePerspective(Pv pv) {
  final sign = pv.whitePerspective ? 1 : -1;
  final isMate = pv.isMate && pv.mate != null;
  final normalizedMate = (pv.mate ?? 0) * sign;
  final normalizedEval = (pv.cp * sign) / 100.0;
  return (eval: normalizedEval, isMate: isMate, mate: normalizedMate);
}

// ---------------------------------------------------------------------------
// Top Controls
// ---------------------------------------------------------------------------
class _TopControls extends StatelessWidget {
  final BoardEditorState editorState;
  final VoidCallback onReset;
  final VoidCallback onClear;
  final void Function(Side) onSideToMove;
  final void Function({
    bool? whiteKingside,
    bool? whiteQueenside,
    bool? blackKingside,
    bool? blackQueenside,
  })
  onToggleCastling;

  const _TopControls({
    required this.editorState,
    required this.onReset,
    required this.onClear,
    required this.onSideToMove,
    required this.onToggleCastling,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Reset, Clear, Side-to-move
          Row(
            children: [
              _SmallButton(label: 'Reset', onTap: onReset),
              SizedBox(width: 8.w),
              _SmallButton(label: 'Clear', onTap: onClear),
              const Spacer(),
              // Side-to-move toggle
              _SideToMoveToggle(
                sideToMove: editorState.sideToMove,
                onChanged: onSideToMove,
              ),
            ],
          ),
          SizedBox(height: 8.h),
          // Row 2: Castling checkboxes
          _CastlingRow(
            editorState: editorState,
            onToggleCastling: onToggleCastling,
          ),
        ],
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SmallButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: kWhiteColor,
          borderRadius: BorderRadius.circular(8.br),
        ),
        child: Text(
          label,
          style: AppTypography.textSmMedium.copyWith(color: kBackgroundColor),
        ),
      ),
    );
  }
}

class _SideToMoveToggle extends StatelessWidget {
  final Side sideToMove;
  final void Function(Side) onChanged;

  const _SideToMoveToggle({required this.sideToMove, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SideOption(
          label: '\u2659', // White pawn
          isSelected: sideToMove == Side.white,
          onTap: () => onChanged(Side.white),
        ),
        SizedBox(width: 4.w),
        _SideOption(
          label: '\u265F', // Black pawn
          isSelected: sideToMove == Side.black,
          onTap: () => onChanged(Side.black),
        ),
      ],
    );
  }
}

class _SideOption extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SideOption({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36.h,
        height: 36.h,
        decoration: BoxDecoration(
          color: isSelected ? kWhiteColor : const Color(0xFF333333),
          borderRadius: BorderRadius.circular(8.br),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 20.f,
              color: isSelected ? kBackgroundColor : kWhiteColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _CastlingRow extends StatelessWidget {
  final BoardEditorState editorState;
  final void Function({
    bool? whiteKingside,
    bool? whiteQueenside,
    bool? blackKingside,
    bool? blackQueenside,
  })
  onToggleCastling;

  const _CastlingRow({
    required this.editorState,
    required this.onToggleCastling,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4.w,
      runSpacing: 4.h,
      children: [
        _CastlingCheck(
          label: '\u2654 O-O',
          value: editorState.whiteKingsideCastle,
          onChanged: (v) => onToggleCastling(whiteKingside: v),
        ),
        _CastlingCheck(
          label: '\u2654 O-O-O',
          value: editorState.whiteQueensideCastle,
          onChanged: (v) => onToggleCastling(whiteQueenside: v),
        ),
        _CastlingCheck(
          label: '\u265A O-O',
          value: editorState.blackKingsideCastle,
          onChanged: (v) => onToggleCastling(blackKingside: v),
        ),
        _CastlingCheck(
          label: '\u265A O-O-O',
          value: editorState.blackQueensideCastle,
          onChanged: (v) => onToggleCastling(blackQueenside: v),
        ),
      ],
    );
  }
}

class _CastlingCheck extends StatelessWidget {
  final String label;
  final bool value;
  final void Function(bool) onChanged;

  const _CastlingCheck({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20.sp,
            height: 20.sp,
            child: Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: kWhiteColor,
              checkColor: kBackgroundColor,
              side: BorderSide(color: kWhiteColor.withValues(alpha: 0.5)),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          SizedBox(width: 4.w),
          Text(
            label,
            style: AppTypography.textXsMedium.copyWith(
              color: kWhiteColor.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Piece Tray
// ---------------------------------------------------------------------------
class _PieceTray extends StatelessWidget {
  final PieceAssets pieceAssets;
  final double squareSize;
  final Piece? selectedPiece;
  final bool isDeleteMode;
  final void Function(Piece?) onSelectPiece;
  final VoidCallback onToggleDeleteMode;
  final VoidCallback onDeleteLongPress;
  final VoidCallback onFlipBoard;

  const _PieceTray({
    required this.pieceAssets,
    required this.squareSize,
    required this.selectedPiece,
    required this.isDeleteMode,
    required this.onSelectPiece,
    required this.onToggleDeleteMode,
    required this.onDeleteLongPress,
    required this.onFlipBoard,
  });

  static const _whiteRoles = [
    Role.king,
    Role.queen,
    Role.rook,
    Role.bishop,
    Role.knight,
    Role.pawn,
  ];
  static const _blackRoles = [
    Role.king,
    Role.queen,
    Role.rook,
    Role.bishop,
    Role.knight,
    Role.pawn,
  ];

  @override
  Widget build(BuildContext context) {
    final trayPieceSize = squareSize * 0.9;

    return Container(
      width: double.infinity,
      color: const Color(0xFFA1ADAE),
      padding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 8.w),
      child: Column(
        children: [
          // White pieces row
          Row(
            children: [
              // Delete button
              _TrayActionButton(
                icon: Icons.delete_outline_rounded,
                isActive: isDeleteMode,
                onTap: onToggleDeleteMode,
                onLongPress: onDeleteLongPress,
                size: trayPieceSize,
              ),
              SizedBox(width: 4.w),
              ..._whiteRoles.map((role) {
                final piece = Piece(color: Side.white, role: role);
                return _TrayPiece(
                  piece: piece,
                  pieceAssets: pieceAssets,
                  size: trayPieceSize,
                  isSelected:
                      !isDeleteMode &&
                      selectedPiece?.color == Side.white &&
                      selectedPiece?.role == role,
                  onTap: () => onSelectPiece(piece),
                );
              }),
            ],
          ),
          SizedBox(height: 4.h),
          // Black pieces row
          Row(
            children: [
              // Flip button
              _TrayActionButton(
                icon: Icons.swap_vert_rounded,
                isActive: false,
                onTap: onFlipBoard,
                size: trayPieceSize,
              ),
              SizedBox(width: 4.w),
              ..._blackRoles.map((role) {
                final piece = Piece(color: Side.black, role: role);
                return _TrayPiece(
                  piece: piece,
                  pieceAssets: pieceAssets,
                  size: trayPieceSize,
                  isSelected:
                      !isDeleteMode &&
                      selectedPiece?.color == Side.black &&
                      selectedPiece?.role == role,
                  onTap: () => onSelectPiece(piece),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrayActionButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double size;

  const _TrayActionButton({
    required this.icon,
    required this.isActive,
    required this.onTap,
    this.onLongPress,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color:
              isActive
                  ? kWhiteColor.withValues(alpha: 0.3)
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(6.br),
          border:
              isActive
                  ? Border.all(
                    color: kWhiteColor.withValues(alpha: 0.6),
                    width: 1.5,
                  )
                  : null,
        ),
        child: Center(
          child: Icon(
            icon,
            color: isActive ? kBackgroundColor : const Color(0xFF333333),
            size: size * 0.6,
          ),
        ),
      ),
    );
  }
}

class _TrayPiece extends StatelessWidget {
  final Piece piece;
  final PieceAssets pieceAssets;
  final double size;
  final bool isSelected;
  final VoidCallback onTap;

  const _TrayPiece({
    required this.piece,
    required this.pieceAssets,
    required this.size,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Draggable<Piece>(
          data: piece,
          feedback: PieceDragFeedback(
            piece: piece,
            squareSize: size,
            pieceAssets: pieceAssets,
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: PieceWidget(
              piece: piece,
              size: size,
              pieceAssets: pieceAssets,
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              color:
                  isSelected
                      ? kWhiteColor.withValues(alpha: 0.3)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(6.br),
              border:
                  isSelected
                      ? Border.all(
                        color: kWhiteColor.withValues(alpha: 0.6),
                        width: 1.5,
                      )
                      : null,
            ),
            child: PieceWidget(
              piece: piece,
              size: size,
              pieceAssets: pieceAssets,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// FEN Bar
// ---------------------------------------------------------------------------
class _FenBar extends StatelessWidget {
  final String fen;
  final VoidCallback onCopy;

  const _FenBar({required this.fen, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF333333),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      child: Row(
        children: [
          Expanded(
            child: Text(
              fen,
              style: AppTypography.textXsRegular.copyWith(
                color: kWhiteColor.withValues(alpha: 0.85),
                fontFamily: 'monospace',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: 8.w),
          GestureDetector(
            onTap: onCopy,
            child: Icon(
              Icons.copy_rounded,
              color: kWhiteColor.withValues(alpha: 0.7),
              size: 18.sp,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Action Row
// ---------------------------------------------------------------------------
class _ActionRow extends StatelessWidget {
  final VoidCallback onPasteFen;
  final VoidCallback onPastePgn;

  const _ActionRow({required this.onPasteFen, required this.onPastePgn});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      child: Row(
        children: [
          Expanded(child: _ActionButton(label: 'Paste FEN', onTap: onPasteFen)),
          SizedBox(width: 12.w),
          Expanded(child: _ActionButton(label: 'Paste PGN', onTap: onPastePgn)),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ActionButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12.h),
        decoration: BoxDecoration(
          color: kWhiteColor,
          borderRadius: BorderRadius.circular(24.br),
        ),
        child: Center(
          child: Text(
            label,
            style: AppTypography.textSmMedium.copyWith(color: kBackgroundColor),
          ),
        ),
      ),
    );
  }
}
