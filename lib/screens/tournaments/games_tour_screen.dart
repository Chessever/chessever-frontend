import 'dart:async';
import 'dart:math';

import 'package:chessever2/screens/chessboard/ChessBoardScreen.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_fen_model.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_widget.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/screens/tournaments/providers/chess_board_visibility_provider.dart';
import 'package:chessever2/screens/tournaments/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tournaments/providers/games_tour_screen_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/back_drop_filter_widget.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'dart:ui';

import 'package:stockfish/stockfish.dart';

class GamesTourScreen extends ConsumerWidget {
  const GamesTourScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isChessBoardVisible = ref.watch(chessBoardVisibilityProvider);
    return GestureDetector(
      onTap: FocusScope.of(context).unfocus,
      child: RefreshIndicator(
        onRefresh: () async {
          FocusScope.of(context).unfocus();
          await ref.read(gamesTourScreenProvider.notifier).refreshGames();
        },
        color: kWhiteColor70,
        backgroundColor: kDarkGreyColor,
        displacement: 60.h,
        strokeWidth: 3.w,
        child: ref
            .watch(gamesAppBarProvider)
            .when(
              data: (_) {
                return ref
                    .watch(gamesTourScreenProvider)
                    .when(
                      data: (data) {
                        if (data.gamesTourModels.isEmpty) {
                          return EmptyWidget(
                            title:
                                "No games available yet. Check back soon or set a\nreminder for updates.",
                          );
                        }

                        return Column(
                          children: [
                            if (isChessBoardVisible)
                              Expanded(
                                child: ListView.builder(
                                  padding: EdgeInsets.only(
                                    left: 20.sp,
                                    right: 20.sp,
                                    top: 12.sp,
                                    bottom:
                                        MediaQuery.of(
                                          context,
                                        ).viewPadding.bottom,
                                  ),
                                  itemCount: data.gamesTourModels.length,
                                  itemBuilder: (cxt, index) {
                                    return ChessBoardFromFEN(
                                      chessBoardFenModel:
                                          ChessBoardFenModel.fromGamesTourModel(
                                            data.gamesTourModels[index],
                                          ),
                                    );
                                  },
                                ),
                              )
                            else
                              Expanded(
                                child: ListView.builder(
                                  padding: EdgeInsets.only(
                                    left: 20.sp,
                                    right: 20.sp,
                                    top: 12.sp,
                                    bottom:
                                        MediaQuery.of(
                                          context,
                                        ).viewPadding.bottom,
                                  ),
                                  itemCount: data.gamesTourModels.length,
                                  itemBuilder: (cxt, index) {
                                    final game = data.gamesTourModels[index];
                                    return Padding(
                                      padding: EdgeInsets.only(bottom: 12.sp),
                                      child: _GameCard(
                                        onTap: () {
                                          if (data
                                                  .gamesTourModels[index]
                                                  .gameStatus
                                                  .displayText !=
                                              '*') {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder:
                                                    (_) => ChessBoardScreen(
                                                      data.gamesTourModels,
                                                      currentIndex: index,
                                                    ),
                                              ),
                                            );
                                          } else {
                                            showDialog(
                                              context: context,
                                              builder:
                                                  (_) => AlertDialog(
                                                    title: const Text(
                                                      "No PGN Data",
                                                    ),
                                                    content: const Text(
                                                      "This game has no PGN data available.",
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed:
                                                            () => Navigator.pop(
                                                              context,
                                                            ),
                                                        child: const Text("OK"),
                                                      ),
                                                    ],
                                                  ),
                                            );
                                          }
                                        },
                                        gamesTourModel: game,
                                        pinnedIds: data.pinnedGamedIs,
                                        onPinToggle: (gamesTourModel) async {
                                          await ref
                                              .read(
                                                gamesTourScreenProvider
                                                    .notifier,
                                              )
                                              .togglePinGame(
                                                gamesTourModel.gameId,
                                              );
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
                          ],
                        );
                      },
                      error: (_, __) => GenericErrorWidget(),
                      loading: () => _TourLoadingWidget(),
                    );
              },
              error: (_, __) => GenericErrorWidget(),
              loading: () => _TourLoadingWidget(),
            ),
      ),
    );
  }
}

class _TourLoadingWidget extends StatelessWidget {
  const _TourLoadingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final mockPlayer = PlayerCard(
      name: 'name',
      federation: 'federation',
      title: 'title',
      rating: 0,
      countryCode: 'USA',
    );
    final gamesTourModel = GamesTourModel(
      gameId: 'gameId',
      whitePlayer: mockPlayer,
      blackPlayer: mockPlayer,
      whiteTimeDisplay: 'whiteTimeDisplay',
      blackTimeDisplay: 'blackTimeDisplay',
      gameStatus: GameStatus.whiteWins,
    );

    final gamesTourModelList = List.generate(8, (_) => gamesTourModel);

    return ListView.builder(
      scrollDirection: Axis.vertical,
      padding: EdgeInsets.only(
        left: 20.sp,
        right: 20.sp,
        top: 12.sp,
        bottom: MediaQuery.of(context).viewPadding.bottom,
      ),
      shrinkWrap: true,
      itemCount: gamesTourModelList.length,
      itemBuilder: (cxt, index) {
        return SkeletonWidget(
          ignoreContainers: true,
          child: Padding(
            padding: EdgeInsets.only(bottom: 12.sp),
            child: _GameCard(
              onTap: () {},
              gamesTourModel: gamesTourModelList[index],
              onPinToggle: (game) {},
              pinnedIds: [],
            ),
          ),
        );
      },
    );
  }
}

class EmptyWidget extends StatelessWidget {
  const EmptyWidget({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgWidget(SvgAsset.infoIcon, height: 24.h, width: 24.w),
        SizedBox(height: 12.h),
        Text(
          title,
          style: AppTypography.textXsRegular.copyWith(color: kWhiteColor70),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.gamesTourModel,
    required this.onPinToggle,
    required this.pinnedIds,
    required this.onTap,
    super.key,
  });

  final GamesTourModel gamesTourModel;
  final void Function(GamesTourModel game) onPinToggle;
  final List<String> pinnedIds;
  final Function() onTap;

  bool get isPinned => pinnedIds.contains(gamesTourModel.gameId);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            height: 60.h,
            padding: EdgeInsets.only(left: 12.sp),
            decoration: BoxDecoration(
              color: kWhiteColor70,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12.br),
                topRight: Radius.circular(12.br),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: MediaQuery.of(context).size.width * (30 / 100),
                  child: _GamesRound(
                    playerName: gamesTourModel.whitePlayer.name,
                    playerRank: gamesTourModel.whitePlayer.displayTitle,
                    countryCode: gamesTourModel.whitePlayer.countryCode,
                  ),
                ),
                Spacer(),
                ChessProgressBar(fen: gamesTourModel.fen ?? ''),
                Spacer(),
                SizedBox(
                  width: MediaQuery.of(context).size.width * (30 / 100),
                  child: _GamesRound(
                    playerName: gamesTourModel.blackPlayer.name,
                    playerRank: gamesTourModel.blackPlayer.displayTitle,
                    countryCode: gamesTourModel.blackPlayer.countryCode,
                  ),
                ),
                Spacer(),
                Stack(
                  alignment: Alignment.topRight,
                  children: [
                    if (isPinned) ...[
                      Positioned(
                        left: 4.sp,
                        child: SvgPicture.asset(
                          SvgAsset.pin,
                          color: kpinColor,
                          height: 14.h,
                          width: 14.w,
                        ),
                      ),
                    ],
                    Align(
                      alignment: Alignment.center,
                      child: GestureDetector(
                        onTapDown: (TapDownDetails details) {
                          _showBlurredPopup(context, details);
                        },
                        child: Icon(
                          Icons.more_vert_rounded,
                          color: kBlackColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            height: 24.h,
            padding: EdgeInsets.symmetric(horizontal: 10.sp),
            decoration: BoxDecoration(
              color: kBlack2Color,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(12.br),
                bottomRight: Radius.circular(12.br),
              ),
            ),
            child: Row(
              children: [
                _TimerWidget(
                  turn: false,
                  time: gamesTourModel.whiteTimeDisplay,
                ),
                Spacer(),
                _TimerWidget(
                  turn: false,
                  time: gamesTourModel.blackTimeDisplay,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showBlurredPopup(BuildContext context, TapDownDetails details) {
    // Get card position and size
    final RenderBox cardRenderBox = context.findRenderObject() as RenderBox;
    final Offset cardPosition = cardRenderBox.localToGlobal(Offset.zero);
    final Size cardSize = cardRenderBox.size;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      pageBuilder: (
        BuildContext buildContext,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
      ) {
        // Position menu at bottom of card + 8 padding
        final double menuTop = cardPosition.dy + 60.h + 24.h + 8.sp;

        return Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Stack(
              children: [
                // Blur background with cutout for current card
                _SelectiveBlurBackground(
                  cardPosition: cardPosition,
                  cardSize: cardSize,
                ),
                // Selected card in its original position (unblurred)
                Positioned(
                  left: cardPosition.dx,
                  top: cardPosition.dy,
                  child: GestureDetector(
                    onTap: () {}, // Prevent tap from closing dialog
                    child: SizedBox(
                      width: cardSize.width,
                      height: cardSize.height,
                      child: Column(
                        children: [
                          Container(
                            height: 60.h,
                            padding: EdgeInsets.only(left: 12.sp),
                            decoration: BoxDecoration(
                              color: kWhiteColor70,
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(12.br),
                                topRight: Radius.circular(12.br),
                              ),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width:
                                      MediaQuery.of(context).size.width *
                                      (30 / 100),
                                  child: _GamesRound(
                                    playerName: gamesTourModel.whitePlayer.name,
                                    playerRank:
                                        gamesTourModel.whitePlayer.displayTitle,
                                    countryCode:
                                        gamesTourModel.whitePlayer.countryCode,
                                  ),
                                ),
                                Spacer(),
                                ChessProgressBar(fen: gamesTourModel.fen ?? ''),
                                Spacer(),
                                SizedBox(
                                  width:
                                      MediaQuery.of(context).size.width *
                                      (30 / 100),
                                  child: _GamesRound(
                                    playerName: gamesTourModel.blackPlayer.name,
                                    playerRank:
                                        gamesTourModel.blackPlayer.displayTitle,
                                    countryCode:
                                        gamesTourModel.blackPlayer.countryCode,
                                  ),
                                ),
                                Spacer(),
                                Stack(
                                  alignment: Alignment.topRight,
                                  children: [
                                    if (isPinned) ...[
                                      Positioned(
                                        left: 4.sp,
                                        child: SvgPicture.asset(
                                          SvgAsset.pin,
                                          color: kpinColor,
                                          height: 14.h,
                                          width: 14.w,
                                        ),
                                      ),
                                    ],
                                    Align(
                                      alignment: Alignment.center,
                                      child: Icon(
                                        Icons.more_vert_rounded,
                                        color: kBlackColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Container(
                            height: 24.h,
                            padding: EdgeInsets.symmetric(horizontal: 10.sp),
                            decoration: BoxDecoration(
                              color: kBlack2Color,
                              borderRadius: BorderRadius.only(
                                bottomLeft: Radius.circular(12.br),
                                bottomRight: Radius.circular(12.br),
                              ),
                            ),
                            child: Row(
                              children: [
                                _TimerWidget(
                                  turn: false,
                                  time: gamesTourModel.whiteTimeDisplay,
                                ),
                                Spacer(),
                                _TimerWidget(
                                  turn: false,
                                  time: gamesTourModel.blackTimeDisplay,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Popup menu positioned correctly
                Positioned(
                  left: details.globalPosition.dx - 120.w,
                  top: menuTop,
                  child: GestureDetector(
                    onTap: () {}, // Prevent tap from closing dialog
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        width: 120.w,
                        decoration: BoxDecoration(
                          color: kDarkGreyColor,
                          borderRadius: BorderRadius.circular(12.br),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 10,
                              offset: Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _PopupMenuItem(
                              onTap: () {
                                Navigator.pop(context);
                                onPinToggle(gamesTourModel);
                              },
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      isPinned
                                          ? "Unpin from Top"
                                          : "Pin to Top",
                                      style: AppTypography.textXsMedium
                                          .copyWith(color: kWhiteColor),
                                    ),
                                  ),
                                  SizedBox(width: 8.w),
                                  SvgPicture.asset(
                                    SvgAsset.pin,
                                    height: 13.h,
                                    width: 13.w,
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              height: 1.h,
                              width: double.infinity,
                              margin: EdgeInsets.symmetric(horizontal: 12.sp),
                              color: kDividerColor,
                            ),
                            _PopupMenuItem(
                              onTap: () {
                                Navigator.pop(context);
                                // Handle share action
                              },
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      "Share",
                                      style: AppTypography.textXsMedium
                                          .copyWith(color: kWhiteColor),
                                    ),
                                  ),
                                  SizedBox(width: 8.w),
                                  SvgPicture.asset(
                                    SvgAsset.share,
                                    height: 13.h,
                                    width: 13.w,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }
}

class _SelectiveBlurBackground extends StatelessWidget {
  const _SelectiveBlurBackground({
    required this.cardPosition,
    required this.cardSize,
    super.key,
  });

  final Offset cardPosition;
  final Size cardSize;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Full screen blur
        BackDropFilterWidget(),
        // Cutout for the selected card (clear area)
        Positioned(
          left: cardPosition.dx,
          top: cardPosition.dy,
          child: Container(
            width: cardSize.width,
            height: cardSize.height,
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12.br),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12.br),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PopupMenuItem extends StatelessWidget {
  const _PopupMenuItem({required this.onTap, required this.child, super.key});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.br),
      child: Container(
        width: 120.w,
        height: 40.h,
        padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 8.sp),
        child: child,
      ),
    );
  }
}

class _GamesRound extends StatelessWidget {
  const _GamesRound({
    required this.playerName,
    required this.playerRank,
    required this.countryCode,
    super.key,
  });

  final String playerName;
  final String playerRank;
  final String countryCode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          playerName,
          maxLines: 1,
          style: AppTypography.textXsMedium.copyWith(color: kBlackColor),
        ),
        Row(
          children: [
            CountryFlag.fromCountryCode(countryCode, height: 12.h, width: 16.w),
            SizedBox(width: 4.w),
            Text(
              playerRank,
              style: AppTypography.textXsMedium.copyWith(color: kBlack2Color),
            ),
          ],
        ),
      ],
    );
  }
}

class ChessProgressBar extends StatefulWidget {
  final String fen;
  final bool useStockfish;

  const ChessProgressBar({
    required this.fen,
    this.useStockfish = true,
    super.key,
  });

  @override
  _ChessProgressBarState createState() => _ChessProgressBarState();
}

class _ChessProgressBarState extends State<ChessProgressBar> {
  double progress = 0.5; // Start at neutral position
  Stockfish? sf;
  bool _isEvaluating = false;
  bool _disposed = false;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    print("ChessProgressBar: initState called with FEN: ${widget.fen}");
    if (widget.useStockfish) {
      _startAndEvaluateWithStockfish(widget.fen);
    } else {
      _startAndEvaluateWithFallback(widget.fen);
    }
  }

  @override
  void didUpdateWidget(ChessProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fen != widget.fen) {
      print("ChessProgressBar: FEN changed, re-evaluating");
      if (widget.useStockfish) {
        _startAndEvaluateWithStockfish(widget.fen);
      } else {
        _startAndEvaluateWithFallback(widget.fen);
      }
    }
  }

  // Fallback evaluation using simple heuristics
  Future<void> _startAndEvaluateWithFallback(String fen) async {
    print("Using fallback evaluation for FEN: $fen");

    setState(() {
      _isEvaluating = true;
    });

    // Simulate analysis time
    await Future.delayed(const Duration(milliseconds: 1000));

    if (_disposed) return;

    // Simple heuristic evaluation based on material count
    double evaluation = _evaluatePositionHeuristic(fen);

    final clampedScore = evaluation.clamp(-10.0, 10.0);
    final newProgress = (clampedScore + 10.0) / 20.0;

    if (mounted) {
      setState(() {
        progress = newProgress;
        _isEvaluating = false;
      });
    }
  }

  // Simple material-based evaluation
  double _evaluatePositionHeuristic(String fen) {
    if (fen.isEmpty) return 0.0;

    final parts = fen.split(' ');
    if (parts.isEmpty) return 0.0;

    final position = parts[0];

    // Piece values
    const pieceValues = {
      'q': 9.0,
      'Q': 9.0,
      'r': 5.0,
      'R': 5.0,
      'b': 3.0,
      'B': 3.0,
      'n': 3.0,
      'N': 3.0,
      'p': 1.0,
      'P': 1.0,
    };

    double whiteScore = 0.0;
    double blackScore = 0.0;

    for (int i = 0; i < position.length; i++) {
      final char = position[i];
      if (pieceValues.containsKey(char)) {
        if (char == char.toUpperCase()) {
          whiteScore += pieceValues[char]!;
        } else {
          blackScore += pieceValues[char]!;
        }
      }
    }

    // Add some randomness for variety
    final random = Random(fen.hashCode);
    final randomFactor = (random.nextDouble() - 0.5) * 2.0; // -1.0 to 1.0

    return (whiteScore - blackScore) + randomFactor;
  }

  Future<void> _startAndEvaluateWithStockfish(String fen) async {
    print("Starting Stockfish evaluation for FEN: $fen");

    // Validate FEN input
    if (fen.isEmpty || fen.trim().isEmpty) {
      print('Invalid FEN: FEN string is empty');
      _startAndEvaluateWithFallback(fen);
      return;
    }

    // Clean up previous instance
    _cleanup();

    setState(() {
      _isEvaluating = true;
    });

    try {
      // Try to create Stockfish instance
      sf = Stockfish();
      print("Stockfish instance created");

      // Set up timeout
      _timeoutTimer = Timer(const Duration(seconds: 10), () {
        print('Stockfish initialization timeout - using fallback');
        _cleanup();
        _startAndEvaluateWithFallback(fen);
      });

      // Wait for initialization with shorter delay
      await Future.delayed(const Duration(milliseconds: 500));

      if (_disposed) return;

      // Check if Stockfish is ready before sending commands
      if (sf?.state != StockfishState.ready) {
        print("Stockfish not ready, waiting...");
        await Future.delayed(const Duration(milliseconds: 1000));

        if (sf?.state != StockfishState.ready) {
          print("Stockfish still not ready after waiting - using fallback");
          _cleanup();
          _startAndEvaluateWithFallback(fen);
          return;
        }
      }

      print("Sending UCI command");
      sf!.stdin = 'uci';
      await Future.delayed(const Duration(milliseconds: 300));

      if (_disposed) return;

      print("Sending isready command");
      sf!.stdin = 'isready';
      await Future.delayed(const Duration(milliseconds: 300));

      if (_disposed) return;

      double? evalCp;
      bool evaluationComplete = false;

      sf!.stdout.listen(
        (line) {
          print("Stockfish output: $line");

          if (_disposed || evaluationComplete) return;

          if (line.contains('readyok')) {
            print("Stockfish is ready");
          } else if (line.startsWith('info') && line.contains('score')) {
            if (line.contains('score cp ')) {
              try {
                final parts = line.split(' ');
                final cpIndex = parts.indexOf('cp');
                if (cpIndex != -1 && cpIndex + 1 < parts.length) {
                  evalCp = int.parse(parts[cpIndex + 1]) / 100.0;
                  print("Found CP score: $evalCp");
                }
              } catch (e) {
                print('Error parsing centipawn score: $e');
              }
            } else if (line.contains('score mate ')) {
              try {
                final parts = line.split(' ');
                final mateIndex = parts.indexOf('mate');
                if (mateIndex != -1 && mateIndex + 1 < parts.length) {
                  final mateValue = int.parse(parts[mateIndex + 1]);
                  evalCp = mateValue > 0 ? 1000.0 : -1000.0;
                  print("Found mate score: $evalCp");
                }
              } catch (e) {
                print('Error parsing mate score: $e');
              }
            }
          } else if (line.startsWith('bestmove')) {
            print("Evaluation complete. Best move: $line");
            if (!evaluationComplete && !_disposed) {
              evaluationComplete = true;
              _timeoutTimer?.cancel();

              final score = (evalCp ?? 0.0).clamp(-10.0, 10.0);
              final newProgress = (score + 10.0) / 20.0;

              print(
                "Final evaluation: $evalCp, clamped: $score, progress: $newProgress",
              );

              if (mounted) {
                setState(() {
                  progress = newProgress;
                  _isEvaluating = false;
                });
              }

              _cleanup();
            }
          }
        },
        onError: (error) {
          print('Stockfish stream error: $error');
          _timeoutTimer?.cancel();
          _cleanup();
          _startAndEvaluateWithFallback(fen);
        },
      );

      if (_disposed) return;

      print("Setting position: $fen");
      sf!.stdin = 'position fen $fen';
      await Future.delayed(const Duration(milliseconds: 100));

      if (_disposed) return;

      print("Starting analysis with depth 10");
      sf!.stdin = 'go depth 10'; // Reduced depth for faster results
    } catch (e) {
      print('Error starting Stockfish evaluation: $e');
      _timeoutTimer?.cancel();
      _cleanup();
      // Fallback to heuristic evaluation
      _startAndEvaluateWithFallback(fen);
    }
  }

  void _cleanup() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;

    if (sf != null) {
      try {
        sf?.dispose();
      } catch (e) {
        print('Error disposing Stockfish: $e');
      }
      sf = null;
    }
  }

  @override
  void dispose() {
    print("ChessProgressBar: dispose called");
    _disposed = true;
    _cleanup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _ProgressWidget(progress: progress, isEvaluating: _isEvaluating);
  }
}

class _ProgressWidget extends StatelessWidget {
  const _ProgressWidget({
    required this.progress,
    required this.isEvaluating,
    super.key,
  });

  final double progress;
  final bool isEvaluating;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48.w,
      height: 12.h,
      child: Stack(
        children: [
          // Background container
          Container(
            width: 48.w,
            height: 12.h,
            decoration: BoxDecoration(
              color: kBlack2Color,
              borderRadius: BorderRadius.all(Radius.circular(4.br)),
            ),
          ),
          // Progress container
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            width: (48.w * progress).clamp(0.0, 48.w),
            height: 12.h,
            decoration: BoxDecoration(
              color: kWhiteColor,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(4.br),
                bottomLeft: Radius.circular(4.br),
                topRight:
                    progress >= 0.99 ? Radius.circular(4.br) : Radius.zero,
                bottomRight:
                    progress >= 0.99 ? Radius.circular(4.br) : Radius.zero,
              ),
            ),
          ),
          // Loading indicator when evaluating
          if (isEvaluating)
            Container(
              width: 48.w,
              height: 12.h,
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.3),
                borderRadius: BorderRadius.all(Radius.circular(4.br)),
              ),
              child: Center(
                child: SizedBox(
                  width: 8,
                  height: 8,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),
          // Center divider line to show neutral position
          Positioned(
            left: 48.w / 2 - 0.5,
            top: 0,
            child: Container(
              width: 1,
              height: 12.h,
              color: Colors.grey.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }
}

// Simplified version without Stockfish for testing
class SimpleChessProgressBar extends StatefulWidget {
  final String fen;
  final double? mockEvaluation; // For testing

  const SimpleChessProgressBar({
    required this.fen,
    this.mockEvaluation,
    super.key,
  });

  @override
  _SimpleChessProgressBarState createState() => _SimpleChessProgressBarState();
}

class _SimpleChessProgressBarState extends State<SimpleChessProgressBar> {
  double progress = 0.5;

  @override
  void initState() {
    super.initState();
    _simulateEvaluation();
  }

  void _simulateEvaluation() {
    // Simulate evaluation with mock data or random values
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        final mockEval =
            widget.mockEvaluation ?? (widget.fen.hashCode % 20 - 10).toDouble();
        final clampedScore = mockEval.clamp(-10.0, 10.0);
        setState(() {
          progress = (clampedScore + 10.0) / 20.0;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _ProgressWidget(progress: progress, isEvaluating: progress == 0.5);
  }
}

class _TimerWidget extends StatelessWidget {
  const _TimerWidget({required this.turn, required this.time, super.key});

  final bool turn;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Text(
      time,
      style: AppTypography.textXsMedium.copyWith(
        color: turn ? kLightBlue : kWhiteColor,
      ),
    );
  }
}
