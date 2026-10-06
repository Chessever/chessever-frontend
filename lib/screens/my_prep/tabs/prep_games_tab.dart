import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/library/widgets/library_game_card.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_filters.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/services/pgn_file_intake_service.dart'
    show chessGameToImportedGamesTourModel;
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Every downloaded game, newest first, on the Library's game cards. A card
/// is built from its PGN only when it scrolls into view.
class PrepGamesTab extends ConsumerStatefulWidget {
  const PrepGamesTab({
    super.key,
    required this.analysis,
    required this.games,
    required this.filter,
    required this.onFilterChanged,
  });

  final PrepAnalysis analysis;
  final List<PrepGame> games;
  final PrepFilter filter;
  final ValueChanged<PrepFilter> onFilterChanged;

  @override
  ConsumerState<PrepGamesTab> createState() => _PrepGamesTabState();
}

class _PrepGamesTabState extends ConsumerState<PrepGamesTab>
    with AutomaticKeepAliveClientMixin {
  final Map<int, GamesTourModel?> _cards = {};
  final _search = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(PrepGamesTab old) {
    super.didUpdateWidget(old);
    if (!identical(old.analysis, widget.analysis)) _cards.clear();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  GamesTourModel? _card(PrepGame game) {
    if (_cards.containsKey(game.index)) return _cards[game.index];
    if (_cards.length > 600) _cards.remove(_cards.keys.first);
    GamesTourModel? model;
    try {
      model = chessGameToImportedGamesTourModel(
        ChessGame.fromPgn(
          widget.analysis.gameId(game.index),
          widget.analysis.pgns[game.index],
        ),
      );
    } catch (_) {
      model = null;
    }
    return _cards[game.index] = model;
  }

  List<PrepGame> get _visible {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return widget.games;
    return [
      for (final g in widget.games)
        if (g.white.toLowerCase().contains(query) ||
            g.black.toLowerCase().contains(query) ||
            (g.opening?.toLowerCase().contains(query) ?? false) ||
            (g.eco?.toLowerCase() == query))
          g,
    ];
  }

  void _open(List<PrepGame> list, int index) {
    HapticFeedbackService.cardTap();
    // The board swipes through neighbours; a window keeps that instant
    // without building thousands of games up front.
    final start = (index - 25).clamp(0, list.length);
    final end = (index + 26).clamp(0, list.length);
    final models = <GamesTourModel>[];
    var selected = 0;
    for (var i = start; i < end; i++) {
      final model = _card(list[i]);
      if (model == null) continue;
      if (i == index) selected = models.length;
      models.add(model);
    }
    if (models.isEmpty) return;
    ref.read(chessboardViewFromProviderNew.notifier).state =
        ChessboardView.tour;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChessBoardScreenNew(
          currentIndex: selected,
          games: models,
          viewSource: ChessboardView.tour,
          showGamebaseButton: false,
          disableGamebaseOverlayByDefault: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = context.colors;
    final gutter = ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w);
    final list = _visible;
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(gutter, 4.h, gutter, 40.h),
      itemCount: list.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: EdgeInsets.only(bottom: 12.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PrepSidePicker(
                  side: widget.filter.side,
                  onChanged: (side) =>
                      widget.onFilterChanged(widget.filter.copyWith(side: side)),
                ),
                SizedBox(height: 10.h),
                _Search(controller: _search, onChanged: () => setState(() {})),
                SizedBox(height: 10.h),
                Text(
                  list.length == 1 ? '1 game' : '${list.length} games',
                  style: AppTypography.textXsRegular.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }
        final game = list[index - 1];
        final model = _card(game);
        if (model == null) return const SizedBox.shrink();
        return Padding(
          key: ValueKey(game.index),
          padding: EdgeInsets.only(bottom: 12.h),
          child: LibraryGameCard(
            game: model,
            eventName: game.speed == null
                ? game.source.label
                : '${game.source.label} · ${game.speed!.labelFor(game.source)}',
            onTap: () => _open(list, index - 1),
          ),
        );
      },
    );
  }
}

class _Search extends StatelessWidget {
  const _Search({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 40.h,
      decoration: BoxDecoration(
        color: colors.textPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10.br),
      ),
      child: Row(
        children: [
          SizedBox(width: 12.w),
          Icon(Icons.search_rounded, size: 18.sp, color: colors.iconSecondary),
          SizedBox(width: 8.w),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: (_) => onChanged(),
              style: AppTypography.textSmRegular.copyWith(
                color: colors.textPrimary,
              ),
              cursorColor: colors.accentText,
              decoration: InputDecoration(
                hintText: 'Search opponent or opening',
                hintStyle: AppTypography.textSmRegular.copyWith(
                  color: colors.textSecondary,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear search',
              onPressed: () {
                controller.clear();
                onChanged();
              },
              icon: Icon(Icons.close, size: 18.sp, color: colors.iconSecondary),
            )
          else
            SizedBox(width: 12.w),
        ],
      ),
    );
  }
}
