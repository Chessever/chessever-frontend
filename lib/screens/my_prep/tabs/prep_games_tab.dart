import 'dart:io';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/library/widgets/library_game_card.dart';
import 'package:chessever2/screens/library/widgets/import_pgn_to_folder_sheet.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_filters.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/services/pgn_file_intake_service.dart'
    show chessGameToImportedGamesTourModel;
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_filter_dialog.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_filter_popup.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/game_filter/game_filter_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Every downloaded game, newest first, on the Library's game cards. A card
/// is built from its PGN only when it scrolls into view.
class PrepGamesTab extends ConsumerStatefulWidget {
  const PrepGamesTab({
    super.key,
    required this.analysis,
    this.profile,
    required this.games,
    required this.filter,
    required this.onFilterChanged,
  });

  final PrepAnalysis analysis;
  final PrepProfile? profile;
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
  bool _working = false;
  List<PrepGame>? _sortInput;
  List<GameSortCriterion>? _sorts;
  List<PrepGame> _sorted = const [];

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
    if (_cards.containsKey(game.rowId)) return _cards[game.rowId];
    if (_cards.length > 600) _cards.remove(_cards.keys.first);
    GamesTourModel? model;
    try {
      final pgn = widget.analysis.pgnOf(game);
      model = pgn == null
          ? null
          : chessGameToImportedGamesTourModel(
              ChessGame.fromPgn(widget.analysis.gameId(game), pgn),
            );
    } catch (_) {
      model = null;
    }
    return _cards[game.rowId] = model;
  }

  List<PrepGame> get _visible {
    final sorts = widget.filter.base?.sorts ?? const <GameSortCriterion>[];
    if (!identical(_sortInput, widget.games) || !listEquals(_sorts, sorts)) {
      _sortInput = widget.games;
      _sorts = sorts;
      _sorted = prepSortGames(widget.games, sorts);
    }
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _sorted;
    return [
      for (final g in _sorted)
        if (g.white.toLowerCase().contains(query) ||
            g.black.toLowerCase().contains(query) ||
            (g.opening?.toLowerCase().contains(query) ?? false) ||
            (g.eco?.toLowerCase() == query) ||
            (g.event?.toLowerCase().contains(query) ?? false))
          g,
    ];
  }

  Future<void> _showFilters() async {
    final profile = widget.profile;
    if (profile != null) {
      final filter = await showPrepFilterDialog(
        context: context,
        profile: profile,
        currentFilter: widget.filter,
      );
      if (filter != null && mounted) widget.onFilterChanged(filter);
      return;
    }
    // Library source nodes already pin the source.
    final filter = await showGameFilterDialog(
      context: context,
      currentFilter: widget.filter.dialogFilter,
      showLiveFilter: false,
      showSortSection: true,
      allowMultiSort: true,
      showOpeningFilter: true,
      showFinishFilter: true,
      showLevelFilter: false,
      showRatingRange: true,
    );
    if (filter != null && mounted) {
      widget.onFilterChanged(widget.filter.withGameFilter(filter));
    }
  }

  Future<void> _saveVisible({required bool export}) async {
    if (_working) return;
    final list = _visible;
    if (list.isEmpty) return;
    final analysis = widget.analysis;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _working = true);
    Directory? temporary;
    try {
      final entries = <(String, String)>[];
      for (final (i, game) in list.indexed) {
        final pgn = analysis.pgnOf(game);
        if (pgn == null) throw const FormatException('Missing PGN');
        entries.add((analysis.gameId(game), pgn));
        // Reading a large local source yields so the busy state stays usable.
        if (i % 100 == 99) {
          await Future<void>.delayed(Duration.zero);
          if (!mounted) return;
        }
      }
      if (export) {
        temporary = await Directory.systemTemp.createTemp(
          'chessever-prep-selection-',
        );
        final file = File('${temporary.path}/filtered-games.pgn');
        await file.writeAsString(
          entries.map((entry) => entry.$2.trim()).join('\n\n'),
        );
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'application/x-chess-pgn')],
          subject: '${entries.length} prepared games',
          sharePositionOrigin: origin,
        );
      } else {
        final games = await compute(parsePreparedGames, entries);
        if (!mounted) return;
        await showImportPgnToFolderSheet(
          context: context,
          games: games,
          sourceLabel: 'My Prep · ${games.length} filtered games',
        );
      }
    } catch (_) {
      if (mounted) {
        showAppSnack(
          context,
          'Could not save these games. Try again.',
          tone: AppSnackTone.danger,
        );
      }
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
      if (mounted) setState(() => _working = false);
    }
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
                Row(
                  children: [
                    Expanded(
                      child: _Search(
                        controller: _search,
                        onChanged: () => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 4),
                    PrepFilterButton(
                      active: widget.filter.isActive,
                      onPressed: _showFilters,
                    ),
                  ],
                ),
                SizedBox(height: 10.h),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        list.isEmpty
                            ? 'No games match these filters.'
                            : list.length == 1
                            ? '1 game'
                            : '${list.length} games'
                                  '${widget.filter.isActive ? ' · ${widget.filter.summary}' : ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.textXsRegular.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                    if (_working)
                      const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      PopupMenuButton<bool>(
                        tooltip: 'Save filtered games',
                        enabled: list.isNotEmpty,
                        onSelected: (export) => _saveVisible(export: export),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: false,
                            child: Text('Save filtered games to Library'),
                          ),
                          PopupMenuItem(
                            value: true,
                            child: Text('Export filtered PGN'),
                          ),
                        ],
                        icon: Icon(
                          Icons.more_horiz,
                          color: colors.iconSecondary,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        }
        final game = list[index - 1];
        final model = _card(game);
        if (model == null) return const SizedBox.shrink();
        return Padding(
          key: ValueKey(game.rowId),
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
      constraints: const BoxConstraints(minHeight: 48),
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
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
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

/// Shared folder saving receives exactly the selected games and original PGNs.
List<ChessGame> parsePreparedGames(List<(String, String)> entries) => [
  for (final entry in entries) ChessGame.fromPgn(entry.$1, entry.$2),
];
