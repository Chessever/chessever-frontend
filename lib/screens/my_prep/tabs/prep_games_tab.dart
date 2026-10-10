import 'dart:io';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/library/widgets/add_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/gamebase_search_game_card.dart';
import 'package:chessever2/screens/library/widgets/import_pgn_to_folder_sheet.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart'
    show LibraryMenuAction;
import 'package:chessever2/screens/my_prep/prep_actions.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart'
    show prepCount;
import 'package:chessever2/screens/my_prep/widgets/prep_filters.dart';
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart'
    show PlayerEventData;
import 'package:chessever2/screens/player_profile/widgets/player_games_event_section.dart';
import 'package:chessever2/screens/player_profile/widgets/player_games_selection.dart';
import 'package:chessever2/screens/player_profile/widgets/player_games_toolbar.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/board_game_card_wrapper_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/game_card_wrapper/grid_game_card_wrapper_widget.dart';
import 'package:chessever2/services/pgn_file_intake_service.dart'
    show chessGameToImportedGamesTourModel;
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/number_format_utils.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/scroll_cache.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_filter_dialog.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:chessever2/widgets/game_filter/game_filter_dialog.dart';
import 'package:chessever2/widgets/scroll_to_top_button.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// One downloaded game as its card and the board read it, built from its
/// PGN. A card on screen holds it; it goes when the card scrolls away.
final prepGameCardProvider = Provider.autoDispose
    .family<GamesTourModel?, ({PrepAnalysis analysis, PrepGame game})>((
      ref,
      key,
    ) {
      final game = key.game;
      try {
        final pgn = key.analysis.pgnOf(game);
        if (pgn == null) return null;
        final model = chessGameToImportedGamesTourModel(
          ChessGame.fromPgn(key.analysis.gameId(game), pgn),
        );
        return model.copyWith(
          // Where a game card reads its event line from, as on a profile.
          tourSlug: game.eventLabel,
          // The index's clock, so the card's coin agrees with the filters.
          timeControl: switch (game.speed) {
            null => model.timeControl,
            PrepTimeControl.ultrabullet ||
            PrepTimeControl.bullet ||
            PrepTimeControl.blitz => 'blitz',
            PrepTimeControl.rapid => 'rapid',
            PrepTimeControl.classical ||
            PrepTimeControl.correspondence => 'standard',
          },
        );
      } catch (_) {
        return null;
      }
    });

/// Lets the screen around a [PrepGamesTab] act on the games it shows: the
/// tab's own row holds search, filters and layout only, as a profile's does.
class PrepGamesController {
  _PrepGamesTabState? _tab;

  /// How many games the filters and the search leave on screen.
  int get shown => _tab?._visible.length ?? 0;

  /// Whether the reader is picking games one by one.
  bool get selecting => _tab?._selecting ?? false;

  Future<void> saveToLibrary() async => _tab?._saveVisible(export: false);
  Future<void> exportPgn() async => _tab?._saveVisible(export: true);

  /// Turns the list into a pick list, as a profile's "Choose games manually".
  void chooseGames() => _tab?._startSelecting();
}

/// The menu rows for the games a [PrepGamesTab] shows right now; none while
/// it shows no game.
List<LibraryMenuAction> prepGamesMenu(PrepGamesController? games) {
  final shown = games?.shown ?? 0;
  if (games == null || shown == 0) return const [];
  final these = shown == 1 ? 'this game' : 'these ${prepCount(shown)} games';
  return [
    LibraryMenuAction(
      icon: Icons.library_add_outlined,
      label: 'Save $these to Library',
      onSelected: games.saveToLibrary,
    ),
    if (!games.selecting)
      LibraryMenuAction(
        icon: Icons.checklist_rounded,
        label: 'Choose games to save',
        onSelected: games.chooseGames,
      ),
    LibraryMenuAction(
      icon: Icons.ios_share_rounded,
      label: 'Export $these as PGN',
      onSelected: games.exportPgn,
    ),
  ];
}

/// Every downloaded game on a player profile's Games tab: the same search,
/// filter and layout row, event cards and game cards, read from the index.
/// A card is built from its PGN only when it scrolls into view.
class PrepGamesTab extends ConsumerStatefulWidget {
  const PrepGamesTab({
    super.key,
    required this.analysis,
    this.profile,
    required this.games,
    required this.filter,
    required this.onFilterChanged,
    this.controller,
  });

  final PrepAnalysis analysis;
  final PrepProfile? profile;
  final List<PrepGame> games;
  final PrepFilter filter;
  final ValueChanged<PrepFilter> onFilterChanged;
  final PrepGamesController? controller;

  @override
  ConsumerState<PrepGamesTab> createState() => _PrepGamesTabState();
}

class _PrepGamesTabState extends ConsumerState<PrepGamesTab>
    with AutomaticKeepAliveClientMixin {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final Set<String> _collapsed = {};

  /// How many games a save or an export is reading; null when idle.
  int? _working;

  /// Picking games to save, and the games picked so far.
  bool _selecting = false;
  final Set<PrepGame> _selected = Set.identity();

  List<PrepGame>? _sortInput;
  List<GameSortCriterion>? _sorts;
  List<PrepGame> _sorted = const [];
  List<PrepGame>? _searchInput;
  String? _searched;
  List<PrepGame> _found = const [];
  List<PrepGame>? _sectionInput;
  List<_Section> _sections = const [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.controller?._tab = this;
  }

  @override
  void didUpdateWidget(PrepGamesTab old) {
    super.didUpdateWidget(old);
    // A fresh read of the index is new games: earlier picks name none of them.
    if (!identical(old.analysis, widget.analysis)) _selected.clear();
    if (identical(old.controller, widget.controller)) return;
    if (identical(old.controller?._tab, this)) old.controller?._tab = null;
    widget.controller?._tab = this;
  }

  @override
  void dispose() {
    final controller = widget.controller;
    if (identical(controller?._tab, this)) controller?._tab = null;
    _scroll.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// The games after the filters, the sort and the search, in list order.
  List<PrepGame> get _visible {
    final sorts = widget.filter.base?.sorts ?? const <GameSortCriterion>[];
    if (!identical(_sortInput, widget.games) || !listEquals(_sorts, sorts)) {
      _sortInput = widget.games;
      _sorts = sorts;
      _sorted = prepSortGames(widget.games, sorts);
    }
    final query = _search.text.trim().toLowerCase();
    if (identical(_searchInput, _sorted) && _searched == query) return _found;
    _searchInput = _sorted;
    _searched = query;
    // Every word must appear somewhere in the game's headers, as on desktop:
    // "carlsen sicilian 2023" narrows by player, opening and year at once.
    final terms = [
      for (final term in query.split(RegExp(r'\s+')))
        if (term.isNotEmpty) term,
    ];
    return _found = terms.isEmpty
        ? _sorted
        : [
            for (final g in _sorted)
              if (_matches(g, terms)) g,
          ];
  }

  static bool _matches(PrepGame g, List<String> terms) {
    final date = g.date;
    final text = [
      g.white,
      g.black,
      ?g.opening,
      ?g.eco,
      ?g.event,
      ?g.eventName,
      ?g.site,
      ?g.timeControlText,
      ?g.url,
      g.result,
      if (g.result == '1/2-1/2') '½-½',
      g.source.label,
      ?g.speed?.labelFor(g.source),
      ?g.whiteElo?.toString(),
      ?g.blackElo?.toString(),
      if (date != null)
        '${date.year}.${date.month.toString().padLeft(2, '0')}.'
            '${date.day.toString().padLeft(2, '0')}',
    ].join('\n').toLowerCase();
    return terms.every(text.contains);
  }

  /// [games] under their events, each event where its first game falls.
  /// A game outside any event joins the run of such games around it; a run
  /// ends where the next event begins, so the list stays in order.
  List<_Section> _sectionsOf(List<PrepGame> games) {
    if (identical(_sectionInput, games)) return _sections;
    _sectionInput = games;
    final events = <String, _Section>{};
    final ids = <String>{};
    final sections = <_Section>[];
    _Section? run;
    for (final game in games) {
      final key = game.eventKey;
      if (key == null) {
        if (run == null) sections.add(run = _Section('run:${game.rowId}'));
        run.games.add(game);
        continue;
      }
      var section = events[key];
      if (section == null) {
        section = events[key] = _Section(key, title: game.eventTitle);
        sections.add(section);
        run = null;
      }
      section.games.add(game);
      // One card per broadcast: a second event naming the same one is
      // found by its title instead.
      final id = game.eventId;
      if (section.id == null && id != null && ids.add(id)) section.id = id;
    }
    return _sections = sections;
  }

  void _toggle(String key) {
    HapticFeedbackService.selection();
    setState(() {
      if (!_collapsed.add(key)) _collapsed.remove(key);
    });
  }

  void _clear() {
    HapticFeedbackService.buttonPress();
    _search.clear();
    _searchFocus.unfocus();
    if (widget.filter.isActive) widget.onFilterChanged(const PrepFilter());
    setState(() {});
  }

  void _startSelecting() {
    if (_selecting) return;
    HapticFeedbackService.buttonPress();
    setState(() => _selecting = true);
  }

  void _stopSelecting() {
    HapticFeedbackService.buttonPress();
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _pick(PrepGame game) {
    if (!_selecting) return;
    HapticFeedbackService.selection();
    setState(() {
      if (!_selected.add(game)) _selected.remove(game);
    });
  }

  /// The picked games the list still shows, in its order.
  List<PrepGame> get _picked => [
    for (final game in _visible)
      if (_selected.contains(game)) game,
  ];

  void _pickAll() {
    final list = _visible;
    HapticFeedbackService.buttonPress();
    setState(
      () => _selected
        ..clear()
        ..addAll(list),
    );
    showAppSnack(context, 'Selected ${list.length} filtered games');
  }

  Future<void> _addPicked() async {
    final picked = _picked;
    if (picked.isEmpty) {
      showAppSnack(context, 'Select at least one game');
      return;
    }
    await _save(
      picked,
      export: false,
      label: 'My Prep · ${picked.length} selected games',
    );
  }

  Future<void> _showFilters() async {
    HapticFeedbackService.buttonPress();
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

  Future<void> _saveVisible({required bool export}) =>
      _save(_visible, export: export);

  /// Hands [list] to a Library folder, or to the share sheet as one PGN.
  Future<void> _save(
    List<PrepGame> list, {
    required bool export,
    String? label,
  }) async {
    if (_working != null || list.isEmpty) return;
    final analysis = widget.analysis;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _working = list.length);
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
          sourceLabel: label ?? 'My Prep · ${games.length} filtered games',
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
      if (mounted) setState(() => _working = null);
    }
  }

  GamesTourModel? _card(PrepGame game) =>
      ref.read(prepGameCardProvider((analysis: widget.analysis, game: game)));

  /// Opens [game] on the board among its neighbours in [order], the games
  /// as the list shows them.
  void _open(List<PrepGame> order, PrepGame game) {
    final index = order.indexOf(game);
    if (index < 0) return;
    // The board swipes through neighbours; a window keeps that instant
    // without building thousands of games up front.
    final start = (index - 25).clamp(0, order.length);
    final end = (index + 26).clamp(0, order.length);
    final models = <GamesTourModel>[];
    var selected = 0;
    for (var i = start; i < end; i++) {
      final model = _card(order[i]);
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
    final mode = ref.watch(gamesListViewModeProvider);
    final list = _visible;
    final sections = _sectionsOf(list);
    final profile = widget.profile;
    final searching = _search.text.trim().isNotEmpty;
    final narrowed = widget.filter.isActive || searching;
    final filterCount = widget.filter.activeCount + (searching ? 1 : 0);
    final working = _working;
    final picked = _selecting ? _picked.length : 0;

    // Cheap row descriptors; the cards themselves are built as they show.
    final rows = <_Row>[];
    final order = <PrepGame>[];
    // Only a list that has events needs its other games set apart from them.
    final headed = sections.any((s) => s.title != null);
    final columns = ResponsiveHelper.isTablet && ResponsiveHelper.isLandscape
        ? 4
        : 2;
    var hint = mode == GamesListViewMode.gamesCard;
    for (final section in sections) {
      final collapsed = _collapsed.contains(section.key);
      if (headed) rows.add(_HeaderRow(section, first: rows.isEmpty));
      if (headed && collapsed) continue;
      final games = section.games;
      order.addAll(games);
      if (mode == GamesListViewMode.chessBoardGrid) {
        for (var i = 0; i < games.length; i += columns) {
          rows.add(
            _GridRow(
              games.sublist(i, (i + columns).clamp(0, games.length)),
              last: i + columns >= games.length,
            ),
          );
        }
        continue;
      }
      for (final (i, game) in games.indexed) {
        rows.add(_GameRow(game, hint: hint, last: i == games.length - 1));
        hint = false;
      }
    }

    Widget cell(PrepGame game, _CardKind kind, {bool hint = false}) =>
        _PrepGameCard(
          key: ValueKey('prep_${kind.name}_${game.rowId}'),
          analysis: widget.analysis,
          game: game,
          kind: kind,
          showHint: hint,
          onOpen: () => _open(order, game),
          // While picking, a tap picks the game instead of opening it.
          onPick: _selecting ? () => _pick(game) : null,
          isPicked: _selected.contains(game),
        );

    Widget row(_Row row) => switch (row) {
      _HeaderRow(:final section, :final first) => Padding(
        padding: EdgeInsets.only(top: first ? 8.h : 20.h, bottom: 12.h),
        child: section.title == null
            ? _RunHeader(
                section: section,
                isCollapsed: _collapsed.contains(section.key),
                onToggle: () => _toggle(section.key),
              )
            : PlayerGamesEventSection(
                eventData: section.event,
                dataSource: section.dataSource,
                tourId: section.tourId,
                tourSlug: section.event.tourSlug ?? section.title,
                site: section.event.site,
                gameCount: section.games.length,
                playerScore: section.score,
                isCollapsed: _collapsed.contains(section.key),
                onToggleCollapsed: () => _toggle(section.key),
              ),
      ),
      _GridRow(:final games, :final last) => Padding(
        padding: EdgeInsets.only(bottom: last ? 0 : 12.h),
        child: Row(
          children: [
            for (var i = 0; i < columns; i++) ...[
              if (i > 0) SizedBox(width: 12.sp),
              Expanded(
                child: i < games.length
                    ? cell(games[i], _CardKind.grid)
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      ),
      _GameRow(:final game, :final hint, :final last) => Padding(
        padding: EdgeInsets.only(bottom: last ? 0 : 12.h),
        child: cell(
          game,
          mode == GamesListViewMode.chessBoard
              ? _CardKind.board
              : _CardKind.card,
          hint: hint,
        ),
      ),
    };

    final scroller = CustomScrollView(
      controller: _scroll,
      scrollCacheExtent: kListScrollCacheExtent,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      slivers: [
        // Shown again on the first scroll up, as a profile's row is. A
        // profile reserves a height for this bar and sets its rows at the
        // bottom of it; the same height is the least this one takes, so the
        // two sit alike in every state. It grows past that when its rows
        // need more (a second line, larger text), so no control is cut off.
        SliverFloatingHeader(
          child: Container(
            color: colors.background,
            constraints: BoxConstraints(
              minHeight:
                  PlayerGamesSearchBar.heightOf(context) +
                  10.h +
                  (narrowed
                      ? PlayerGamesActiveFiltersChip.heightOf(context)
                      : 0) +
                  (_selecting
                      ? PlayerGamesSelectionToolbar.heightOf(context)
                      : 0),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(gutter, 2.h, gutter, 4.h),
                  child: PlayerGamesSearchBar(
                    controller: _search,
                    focusNode: _searchFocus,
                    onChanged: (_) => setState(() {}),
                    onClear: () {
                      HapticFeedbackService.buttonPress();
                      _search.clear();
                      _searchFocus.unfocus();
                      setState(() {});
                    },
                    onFilterTap: _showFilters,
                    onLayoutToggle: () =>
                        ref.read(gamesListViewModeSwitcher).toggleViewMode(),
                    hasQuery: searching,
                    hasActiveFilters: narrowed,
                    activeFilterCount: filterCount,
                  ),
                ),
                if (_selecting)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      gutter,
                      0,
                      gutter,
                      narrowed ? 4.h : 6.h,
                    ),
                    child: PlayerGamesSelectionToolbar(
                      selectedCount: picked,
                      subtitle: narrowed
                          ? 'Selection follows current filters and search'
                          : 'Tap games manually or use quick select',
                      selectAllLabel: narrowed
                          ? 'Select filtered'
                          : 'Select all (${formatCompactCount(list.length)})',
                      onSelectAll: list.isEmpty ? null : _pickAll,
                      onAddSelected: _addPicked,
                      onClose: _stopSelecting,
                    ),
                  ),
                if (working != null)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 4.h),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox.square(
                          dimension: 12.sp,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.textSecondary,
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Text(
                          'Preparing $working games…',
                          style: AppTypography.textXsRegular.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (narrowed)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: gutter),
                    child: PlayerGamesActiveFiltersChip(
                      activeFilterCount: filterCount,
                      gameCount: list.length,
                      onClear: _clear,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (list.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: PlayerGamesNoMatches(onClear: _clear),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: gutter, vertical: 8.h),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => index < rows.length
                    ? row(rows[index])
                    : Container(
                        padding: EdgeInsets.only(top: 26.h, bottom: 14.h),
                        alignment: Alignment.center,
                        child: Text(
                          'Loaded all ${list.length} games',
                          style: AppTypography.textXsRegular.copyWith(
                            color: context.textInk(0.45),
                          ),
                        ),
                      ),
                childCount: rows.length + 1,
              ),
            ),
          ),
        SliverToBoxAdapter(child: SizedBox(height: 24.h)),
      ],
    );

    return Stack(
      children: [
        // Pulling down asks the sources for newer games, as on My Prep.
        if (profile == null)
          scroller
        else
          RefreshIndicator(
            color: colors.textPrimary,
            backgroundColor: colors.surface,
            onRefresh: () => prepRefreshProfile(context, ref, profile.id),
            child: scroller,
          ),
        Positioned(
          bottom: 0,
          right: 0,
          child: ScrollToTopButton(scrollController: _scroll),
        ),
      ],
    );
  }
}

/// A slice of the list: one event's games, or a run of games outside any.
class _Section {
  _Section(this.key, {this.title});

  final String key;

  /// The event's name; null for a run of games that belong to no event.
  final String? title;
  final List<PrepGame> games = [];

  /// The ChessEver broadcast the event's card opens, when a game names one.
  String? id;

  String get tourId => id ?? title ?? key;

  /// A broadcast is opened by its id; a database event is found by name.
  PlayerProfileDataSource get dataSource => id == null
      ? PlayerProfileDataSource.twic
      : PlayerProfileDataSource.supabase;

  /// The player's points here: a win is one, a draw a half.
  late final double score = games.fold(
    0,
    (sum, g) => switch (g.outcome) {
      PrepOutcome.win => sum + 1,
      PrepOutcome.draw => sum + 0.5,
      _ => sum,
    },
  );

  /// The servers a run's games were played on, in the order they appear.
  late final String sources = {
    for (final g in games) g.source.label,
  }.join(' · ');

  /// What the event's card shows before, or without, a broadcast behind it.
  late final PlayerEventData event = () {
    DateTime? start;
    DateTime? end;
    String? slug;
    String? site;
    var ratings = 0.0;
    var rated = 0;
    final clocks = <PrepTimeControl, int>{};
    for (final g in games) {
      final speed = g.speed;
      if (speed != null) clocks[speed] = (clocks[speed] ?? 0) + 1;
      final from = g.eventDate ?? g.date;
      if (from != null && (start == null || from.isBefore(start))) start = from;
      final to = g.date;
      if (to != null && (end == null || to.isAfter(end))) end = to;
      slug ??= g.eventSlug;
      // A server's link to one game is not where the event was held.
      final place = g.site;
      if (site == null &&
          place != null &&
          (!place.startsWith('http') || place.contains('/broadcast/'))) {
        site = place;
      }
      final average = g.averageElo;
      if (average != null) {
        ratings += average;
        rated++;
      }
    }
    return PlayerEventData(
      tourId: tourId,
      tourName: title ?? '',
      tourSlug: slug,
      broadcastSlug: slug,
      gamesPlayed: games.length,
      score: score,
      startDate: start,
      endDate: end,
      site: site,
      // The clock most of its games were played at, for the card's coin.
      dominantTimeControl: clocks.isEmpty
          ? null
          : clocks.entries.reduce((a, b) => b.value > a.value ? b : a).key.name,
      avgElo: rated == 0 ? null : (ratings / rated).round(),
    );
  }();
}

sealed class _Row {
  const _Row();
}

class _HeaderRow extends _Row {
  const _HeaderRow(this.section, {required this.first});
  final _Section section;
  final bool first;
}

class _GameRow extends _Row {
  const _GameRow(this.game, {required this.hint, required this.last});
  final PrepGame game;
  final bool hint;
  final bool last;
}

class _GridRow extends _Row {
  const _GridRow(this.games, {required this.last});
  final List<PrepGame> games;
  final bool last;
}

enum _CardKind { card, board, grid }

/// One game in the list's layout, on the cards a player profile uses.
class _PrepGameCard extends ConsumerWidget {
  const _PrepGameCard({
    super.key,
    required this.analysis,
    required this.game,
    required this.kind,
    required this.showHint,
    required this.onOpen,
    this.onPick,
    this.isPicked = false,
  });

  final PrepAnalysis analysis;
  final PrepGame game;
  final _CardKind kind;
  final bool showHint;
  final VoidCallback onOpen;

  /// Set while games are being picked to save: a tap picks this one.
  final VoidCallback? onPick;
  final bool isPicked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(
      prepGameCardProvider((analysis: analysis, game: game)),
    );
    if (model == null) return const SizedBox.shrink();
    final pick = onPick;
    final card = switch (kind) {
      _CardKind.card => GamebaseSearchGameCard(
        game: model,
        allGames: [model],
        gameIndex: 0,
        showRound: true,
        showSwipeHint: showHint,
        showGamebaseButton: false,
        onAdd:
            pick ?? () => showAddToFolderSheet(context: context, game: model),
        // Downloaded games stay readable, so opening one asks for nothing.
        onTap: pick ?? onOpen,
      ),
      _CardKind.board => BoardGameCardWrapperWidget(
        game: model,
        orderedGames: [model],
        gameIndex: 0,
        playerProfileDataSource: PlayerProfileDataSource.twic,
        streamEnabled: false,
        onChangedWithLiveGames: (_) => onOpen(),
        pinnedIds: const [],
        onPinToggle: (_) {},
        showPin: false,
      ),
      _CardKind.grid => GridGameCardWrapperWidget(
        game: model,
        orderedGames: [model],
        gameIndex: 0,
        playerProfileDataSource: PlayerProfileDataSource.twic,
        streamEnabled: false,
        onChangedWithLiveGames: (_) => onOpen(),
        pinnedIds: const [],
        onPinToggle: (_) {},
        showPin: false,
      ),
    };
    if (pick == null) return card;
    return PlayerGamesSelectableCard(
      card: card,
      isSelected: isPicked,
      // A list card's own tap picks; a board would open itself, so the
      // wrapper takes its gestures.
      onTap: kind == _CardKind.card ? null : pick,
      cornerRadius: kind == _CardKind.grid ? 12 : 14,
    );
  }
}

/// Heads a run of games that belong to no event, where the list has event
/// cards to set them apart from: where they were played, how many, the score.
class _RunHeader extends StatelessWidget {
  const _RunHeader({
    required this.section,
    required this.isCollapsed,
    required this.onToggle,
  });

  final _Section section;
  final bool isCollapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final count = section.games.length;
    return Container(
      padding: EdgeInsets.only(left: 12.w),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(8.br),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: section.sources,
                    style: AppTypography.textSmMedium.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                  TextSpan(
                    text: '   $count ${count == 1 ? 'game' : 'games'}',
                    style: AppTypography.textXsRegular.copyWith(
                      color: context.textInk(0.5),
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: 8.w),
          PlayerGamesScorePill(gameCount: count, playerScore: section.score),
          PlayerGamesCollapseToggle(
            isCollapsed: isCollapsed,
            onTap: onToggle,
            label: '${section.sources} games',
          ),
        ],
      ),
    );
  }
}

/// Shared folder saving receives exactly the selected games and original PGNs.
List<ChessGame> parsePreparedGames(List<(String, String)> entries) => [
  for (final entry in entries) ChessGame.fromPgn(entry.$1, entry.$2),
];
