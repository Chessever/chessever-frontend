import 'dart:convert';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/repository/library/library_repository.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/library/providers/gamebase_database_search_provider.dart';
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/library/widgets/create_folder_dialog.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class GamebaseDatabaseSearchScreen extends ConsumerStatefulWidget {
  const GamebaseDatabaseSearchScreen({super.key});

  @override
  ConsumerState<GamebaseDatabaseSearchScreen> createState() =>
      _GamebaseDatabaseSearchScreenState();
}

class _GamebaseDatabaseSearchScreenState
    extends ConsumerState<GamebaseDatabaseSearchScreen> {
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _queryFocusNode = FocusNode();

  @override
  void dispose() {
    _queryController.dispose();
    _queryFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchAsync = ref.watch(gamebaseDatabaseSearchProvider);

    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        backgroundColor: kBackgroundColor,
        elevation: 0,
        leading: IconButton(
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop();
          },
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: kWhiteColor),
        ),
        title: Text(
          'Database',
          style: AppTypography.textLgBold.copyWith(color: kWhiteColor),
        ),
        actions: [
          searchAsync.valueOrNull?.hasActiveFilters == true
              ? IconButton(
                  tooltip: 'Clear filters',
                  onPressed: () {
                    HapticFeedbackService.buttonPress();
                    ref.read(gamebaseDatabaseSearchProvider.notifier).clearFilters();
                  },
                  icon: Icon(Icons.filter_alt_off, color: kWhiteColor),
                )
              : const SizedBox.shrink(),
          IconButton(
            tooltip: 'Filters',
            onPressed: () {
              HapticFeedbackService.buttonPress();
              _openFilters();
            },
            icon: Icon(Icons.tune_rounded, color: kWhiteColor),
          ),
          IconButton(
            tooltip: 'Columns',
            onPressed: () {
              HapticFeedbackService.buttonPress();
              _openColumns();
            },
            icon: Icon(Icons.view_column_outlined, color: kWhiteColor),
          ),
          IconButton(
            tooltip: 'Sort',
            onPressed: () {
              HapticFeedbackService.buttonPress();
              _openSort();
            },
            icon: Icon(Icons.sort_rounded, color: kWhiteColor),
          ),
        ],
      ),
      body: searchAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: kPrimaryColor),
        ),
        error: (error, _) => _ErrorState(message: error.toString()),
        data: (state) {
          return Column(
            children: [
              _buildSearchBar(state),
              _buildMetaRow(state),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    HapticFeedbackService.medium();
                    await ref.read(gamebaseDatabaseSearchProvider.notifier).refresh();
                  },
                  color: kPrimaryColor,
                  backgroundColor: kBlack2Color,
                  child: _ResultsTable(
                    state: state,
                    onRowTap: (row) => _openRowDetails(state, row),
                    onSort: (field, ascending) {
                      final direction = ascending
                          ? GamebaseOrderDirection.asc
                          : GamebaseOrderDirection.desc;
                      ref
                          .read(gamebaseDatabaseSearchProvider.notifier)
                          .setOrderBy([GamebaseOrderByRule(field: field, direction: direction)]);
                    },
                  ),
                ),
              ),
              _PaginationBar(
                canGoPrev: state.canGoPrev,
                canGoNext: state.canGoNext,
                pageNumber: state.pagination.pageNumber,
                pageSize: state.pagination.pageSize,
                totalCount: state.pagination.totalCount,
                onPrev: () => ref.read(gamebaseDatabaseSearchProvider.notifier).prevPage(),
                onNext: () => ref.read(gamebaseDatabaseSearchProvider.notifier).nextPage(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchBar(GamebaseDatabaseSearchState state) {
    if (_queryController.text != state.query) {
      _queryController.text = state.query;
      _queryController.selection = TextSelection.fromPosition(
        TextPosition(offset: _queryController.text.length),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 6.h),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: kBlack2Color,
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(color: kWhiteColor.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Icon(Icons.search, color: kWhiteColor.withValues(alpha: 0.7)),
            SizedBox(width: 10.w),
            Expanded(
              child: TextField(
                controller: _queryController,
                focusNode: _queryFocusNode,
                style: AppTypography.textSmRegular.copyWith(color: kWhiteColor),
                onChanged:
                    (value) => ref
                        .read(gamebaseDatabaseSearchProvider.notifier)
                        .setQuery(value),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search…',
                  hintStyle: AppTypography.textSmRegular.copyWith(
                    color: kWhiteColor.withValues(alpha: 0.5),
                  ),
                  border: InputBorder.none,
                ),
              ),
            ),
            if (_queryController.text.isNotEmpty)
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  _queryController.clear();
                  ref.read(gamebaseDatabaseSearchProvider.notifier).setQuery('');
                  _queryFocusNode.unfocus();
                  setState(() {});
                },
                child: Container(
                  padding: EdgeInsets.all(6.sp),
                  decoration: BoxDecoration(
                    color: kWhiteColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.close,
                    size: 14.sp,
                    color: kWhiteColor.withValues(alpha: 0.7),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaRow(GamebaseDatabaseSearchState state) {
    final subtitle =
        state.pagination.totalCount != null
            ? '${state.pagination.totalCount} results'
            : 'Results';

    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 2.h, 16.w, 10.h),
      child: Row(
        children: [
          Expanded(
            child: Text(
              subtitle,
              style: AppTypography.textSmMedium.copyWith(
                color: kWhiteColor.withValues(alpha: 0.7),
              ),
            ),
          ),
          if (state.isQueryLoading)
            SizedBox(
              width: 18.sp,
              height: 18.sp,
              child: const CircularProgressIndicator(
                color: kPrimaryColor,
                strokeWidth: 2,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openFilters() async {
    final current = ref.read(gamebaseDatabaseSearchProvider).valueOrNull;
    if (current == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kBlack2Color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.br)),
      ),
      builder: (_) => const _FiltersSheet(),
    );
  }

  Future<void> _openColumns() async {
    final current = ref.read(gamebaseDatabaseSearchProvider).valueOrNull;
    if (current == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kBlack2Color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.br)),
      ),
      builder: (_) => const _ColumnsSheet(),
    );
  }

  Future<void> _openSort() async {
    final current = ref.read(gamebaseDatabaseSearchProvider).valueOrNull;
    if (current == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kBlack2Color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.br)),
      ),
      builder: (_) => const _SortSheet(),
    );
  }

  Future<void> _openRowDetails(
    GamebaseDatabaseSearchState state,
    Map<String, dynamic> row,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: kBlack2Color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.br)),
      ),
      builder:
          (_) => _RowDetailsSheet(
            state: state,
            row: row,
            onAddToBook: () => _addRowToBook(state, row),
          ),
    );
  }

  Future<void> _addRowToBook(
    GamebaseDatabaseSearchState state,
    Map<String, dynamic> row,
  ) async {
    final id = row[state.resource.primaryKey]?.toString().trim();
    if (id == null || id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Missing game id',
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
          ),
          backgroundColor: kRedColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final folder = await _pickBook();
    if (folder == null || !mounted) return;

    try {
      final libraryRepository = ref.read(libraryRepositoryProvider);
      final existing = await libraryRepository.getSavedAnalyses(folderId: folder.id);
      final alreadyAdded = existing.any((a) => a.sourceGameId == id);

      if (alreadyAdded && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Game already in "${folder.name}"',
              style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
            ),
            backgroundColor: kBlack2Color.withValues(alpha: 0.95),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final gamebaseRepository = ref.read(gamebaseRepositoryProvider);
      final game = await gamebaseRepository.getGameById(id);

      final chessGame = _toChessGame(id: id, row: row, gameData: game?.data);
      final title = _deriveTitle(row: row, fallbackId: id);

      final userId = libraryRepository.supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final analysis = SavedAnalysis(
        id: '',
        userId: userId,
        folderId: folder.id,
        title: title,
        sourceGameId: id,
        sourceTournamentId: 'gamebase',
        chessGame: chessGame,
        analysisState: const {},
        variationComments: const {},
        lastViewedPosition: -1,
        tags: const [],
        notes: null,
        isFavorite: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await libraryRepository.createSavedAnalysis(analysis);

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Added to "${folder.name}"',
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
          ),
          backgroundColor: kBlack2Color.withValues(alpha: 0.95),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to add game: $e',
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
          ),
          backgroundColor: kRedColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<LibraryFolder?> _pickBook() async {
    final foldersAsync = ref.read(libraryFoldersStreamProvider);

    final folders = await foldersAsync.when(
      data: (value) async => value,
      error: (_, __) async {
        final repo = ref.read(libraryRepositoryProvider);
        return repo.getFolders();
      },
      loading: () async {
        final repo = ref.read(libraryRepositoryProvider);
        return repo.getFolders();
      },
    );

    if (!mounted) return null;

    return showModalBottomSheet<LibraryFolder>(
      context: context,
      backgroundColor: kBlack2Color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.br)),
      ),
      builder: (_) => _BookPickerSheet(
        folders: folders,
        onCreateBook: _createBook,
      ),
    );
  }

  Future<LibraryFolder?> _createBook() async {
    final name = await showCreateFolderDialog(context);
    if (name == null || name.trim().isEmpty) return null;

    try {
      final repository = ref.read(libraryRepositoryProvider);
      final folder = await repository.createFolder(name: name.trim());
      ref.invalidate(libraryFoldersStreamProvider);
      return folder;
    } catch (e) {
      if (!mounted) return null;
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to create book: $e',
            style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
          ),
          backgroundColor: kRedColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return null;
    }
  }

  ChessGame _toChessGame({
    required String id,
    required Map<String, dynamic> row,
    required Map<String, dynamic>? gameData,
  }) {
    final data = gameData ?? row['data'];
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final looksLikeChessGame =
          map.containsKey('sf') && map.containsKey('md') && map.containsKey('m');
      if (looksLikeChessGame) {
        return ChessGame.fromJson({'id': id, ...map});
      }

      final pgn = _extractPgn(map);
      if (pgn != null) {
        return ChessGame.fromPgn(id, pgn);
      }
    }

    const startingFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
    return ChessGame(
      gameId: id,
      startingFen: startingFen,
      metadata: _deriveHeaders(row),
      mainline: const [],
    );
  }

  Map<String, dynamic> _deriveHeaders(Map<String, dynamic> row) {
    final headers = <String, dynamic>{
      'Event': row['event']?.toString() ?? 'Gamebase',
      'Site': 'ChessEver',
      'Result': row['result']?.toString() ?? '*',
    };

    final date = row['date']?.toString();
    if (date != null && date.isNotEmpty) headers['Date'] = date.split('T').first;

    final white = row['white']?.toString() ?? row['whiteName']?.toString();
    final black = row['black']?.toString() ?? row['blackName']?.toString();
    if (white != null && white.isNotEmpty) headers['White'] = white;
    if (black != null && black.isNotEmpty) headers['Black'] = black;
    return headers;
  }

  String _deriveTitle({required Map<String, dynamic> row, required String fallbackId}) {
    final white = row['white']?.toString() ?? row['whiteName']?.toString();
    final black = row['black']?.toString() ?? row['blackName']?.toString();

    final cleanedWhite = white?.trim();
    final cleanedBlack = black?.trim();

    if (cleanedWhite != null &&
        cleanedWhite.isNotEmpty &&
        cleanedBlack != null &&
        cleanedBlack.isNotEmpty) {
      return '$cleanedWhite vs $cleanedBlack';
    }

    return 'Game $fallbackId';
  }

  String? _extractPgn(Map<String, dynamic> data) {
    final direct =
        data['pgn'] ??
        data['PGN'] ??
        data['pgnText'] ??
        data['pgn_text'] ??
        data['pgnString'];
    if (direct is String && direct.trim().isNotEmpty) return direct;

    final headers = data['headers'];
    final moves = data['moves'];

    if (headers is Map && moves is List) {
      final headerMap = Map<String, dynamic>.from(headers);
      final moveList = moves.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      if (moveList.isEmpty) return null;

      final sb = StringBuffer();
      for (final entry in headerMap.entries) {
        sb.writeln('[${entry.key} "${entry.value}"]');
      }
      sb.writeln();
      sb.writeln(moveList.join(' '));
      if (!moveList.last.endsWith('*') &&
          !moveList.last.endsWith('1-0') &&
          !moveList.last.endsWith('0-1') &&
          !moveList.last.endsWith('1/2-1/2')) {
        sb.writeln(' *');
      }
      return sb.toString();
    }

    return null;
  }
}

class _ResultsTable extends StatelessWidget {
  const _ResultsTable({
    required this.state,
    required this.onRowTap,
    required this.onSort,
  });

  final GamebaseDatabaseSearchState state;
  final void Function(Map<String, dynamic> row) onRowTap;
  final void Function(String field, bool ascending) onSort;

  @override
  Widget build(BuildContext context) {
    if (state.lastQueryError != null) {
      return ListView(
        padding: EdgeInsets.fromLTRB(16.w, 48.h, 16.w, 24.h),
        children: [
          _InlineError(message: state.lastQueryError!),
        ],
      );
    }

    if (state.rows.isEmpty) {
      return ListView(
        padding: EdgeInsets.fromLTRB(16.w, 48.h, 16.w, 24.h),
        children: const [
          _EmptyState(),
        ],
      );
    }

    final columns = state.selectedColumns;
    final sortField = state.orderBy.isNotEmpty ? state.orderBy.first.field : null;
    final sortAscending =
        state.orderBy.isNotEmpty ? state.orderBy.first.direction == GamebaseOrderDirection.asc : true;
    final sortIndex = sortField == null ? null : columns.indexOf(sortField);

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          sortColumnIndex: sortIndex != null && sortIndex >= 0 ? sortIndex : null,
          sortAscending: sortAscending,
          headingRowColor: WidgetStatePropertyAll(kBlack3Color),
          dataRowColor: WidgetStatePropertyAll(kBlack2Color),
          columns: [
            for (var i = 0; i < columns.length; i++)
              DataColumn(
                label: Text(
                  _humanize(columns[i]),
                  style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
                ),
                onSort: (_, ascending) => onSort(columns[i], ascending),
              ),
          ],
          rows: [
            for (final row in state.rows)
              DataRow(
                onSelectChanged: (_) => onRowTap(row),
                cells: [
                  for (final col in columns)
                    DataCell(
                      Text(
                        _formatCell(row[col]),
                        style: AppTypography.textSmRegular.copyWith(
                          color: kWhiteColor.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _formatCell(dynamic value) {
    if (value == null) return '—';
    if (value is bool) return value ? 'true' : 'false';
    if (value is num) return value.toString();
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return '—';
      final dt = DateTime.tryParse(trimmed);
      if (dt != null) return dt.toIso8601String();
      return trimmed;
    }
    if (value is Map || value is List) {
      try {
        return jsonEncode(value);
      } catch (_) {
        return value.toString();
      }
    }
    return value.toString();
  }
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.canGoPrev,
    required this.canGoNext,
    required this.pageNumber,
    required this.pageSize,
    required this.totalCount,
    required this.onPrev,
    required this.onNext,
  });

  final bool canGoPrev;
  final bool canGoNext;
  final int pageNumber;
  final int pageSize;
  final int? totalCount;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final rightText = totalCount == null ? 'Page $pageNumber' : 'Page $pageNumber • $totalCount total';

    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 16.h),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: kWhiteColor.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          _IconPillButton(
            icon: Icons.chevron_left_rounded,
            onTap: canGoPrev ? onPrev : null,
          ),
          SizedBox(width: 10.w),
          _IconPillButton(
            icon: Icons.chevron_right_rounded,
            onTap: canGoNext ? onNext : null,
          ),
          const Spacer(),
          Text(
            rightText,
            style: AppTypography.textSmRegular.copyWith(
              color: kWhiteColor.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconPillButton extends StatelessWidget {
  const _IconPillButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44.w,
        height: 36.h,
        decoration: BoxDecoration(
          color: kBlack2Color,
          borderRadius: BorderRadius.circular(10.br),
          border: Border.all(
            color:
                enabled
                    ? kWhiteColor.withValues(alpha: 0.12)
                    : kWhiteColor.withValues(alpha: 0.06),
          ),
        ),
        child: Icon(
          icon,
          color:
              enabled
                  ? kWhiteColor.withValues(alpha: 0.9)
                  : kWhiteColor.withValues(alpha: 0.35),
          size: 22.ic,
        ),
      ),
    );
  }
}

class _FiltersSheet extends ConsumerWidget {
  const _FiltersSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchAsync = ref.watch(gamebaseDatabaseSearchProvider);

    return searchAsync.when(
      loading: () => SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 32.h),
          child: const Center(
            child: CircularProgressIndicator(color: kPrimaryColor),
          ),
        ),
      ),
      error: (error, _) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
          child: _InlineError(message: error.toString()),
        ),
      ),
      data: (state) {
        final filterable = state.resource.filterableColumns;

        final defaultField =
            filterable.isNotEmpty ? filterable.first.name : state.resource.primaryKey;
        final defaultOperators =
            state.resource.columnByName(defaultField)?.operators ?? const ['eq'];
        final defaultOp =
            defaultOperators.isNotEmpty ? defaultOperators.first : 'eq';

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: kWhiteColor.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(10.br),
                  ),
                ),
                SizedBox(height: 14.h),
                Row(
                  children: [
                    Text(
                      'Filters',
                      style: AppTypography.textMdMedium.copyWith(
                        color: kWhiteColor,
                      ),
                    ),
                    const Spacer(),
                    _SmallTextButton(
                      label: 'Clear',
                      onTap: () => ref
                          .read(gamebaseDatabaseSearchProvider.notifier)
                          .clearFilters(),
                      color: kRedColor,
                    ),
                  ],
                ),
                SizedBox(height: 12.h),
                Row(
                  children: [
                    Text(
                      'Match',
                      style: AppTypography.textSmMedium.copyWith(
                        color: kWhiteColor.withValues(alpha: 0.7),
                      ),
                    ),
                    SizedBox(width: 10.w),
                    _SegmentedControl<GamebaseFilterGroupMode>(
                      value: state.filterMode,
                      values: const [
                        GamebaseFilterGroupMode.and,
                        GamebaseFilterGroupMode.or,
                      ],
                      labels: const ['All', 'Any'],
                      onChanged: ref
                          .read(gamebaseDatabaseSearchProvider.notifier)
                          .setFilterMode,
                    ),
                  ],
                ),
                SizedBox(height: 12.h),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: state.filters.length,
                    separatorBuilder: (_, __) => SizedBox(height: 10.h),
                    itemBuilder: (context, index) {
                      return _FilterRuleCard(
                        key: ValueKey('filter-$index'),
                        state: state,
                        rule: state.filters[index],
                        onChanged: (rule) => ref
                            .read(gamebaseDatabaseSearchProvider.notifier)
                            .updateFilterRule(index, rule),
                        onRemove: () => ref
                            .read(gamebaseDatabaseSearchProvider.notifier)
                            .removeFilterRule(index),
                      );
                    },
                  ),
                ),
                SizedBox(height: 12.h),
                _PrimaryButton(
                  label: 'Add Filter',
                  onTap: () {
                    ref
                        .read(gamebaseDatabaseSearchProvider.notifier)
                        .addFilterRule(
                          GamebaseFilterRule(
                            field: defaultField,
                            op: defaultOp,
                          ),
                        );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FilterRuleCard extends StatelessWidget {
  const _FilterRuleCard({
    super.key,
    required this.state,
    required this.rule,
    required this.onChanged,
    required this.onRemove,
  });

  final GamebaseDatabaseSearchState state;
  final GamebaseFilterRule rule;
  final ValueChanged<GamebaseFilterRule> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final columns = state.resource.filterableColumns;
    final selectedColumn = state.resource.columnByName(rule.field) ?? columns.firstOrNull;

    final operators = selectedColumn?.operators ?? const ['eq'];
    final selectedOp = operators.contains(rule.op) ? rule.op : (operators.isNotEmpty ? operators.first : 'eq');

    return Container(
      padding: EdgeInsets.all(12.sp),
      decoration: BoxDecoration(
        color: kBlack3Color,
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: kWhiteColor.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _Dropdown<String>(
                  value: selectedColumn?.name,
                  items: [
                    for (final c in columns) _DropdownItem(value: c.name, label: _humanize(c.name)),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    final newColumn = state.resource.columnByName(value);
                    final newOps = newColumn?.operators ?? const ['eq'];
                    final op = newOps.contains(selectedOp) ? selectedOp : (newOps.isNotEmpty ? newOps.first : 'eq');
                    onChanged(
                      rule.copyWith(field: value, op: op, value: null, values: null, overrideValues: true),
                    );
                  },
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: _Dropdown<String>(
                  value: selectedOp,
                  items: [
                    for (final op in operators)
                      _DropdownItem(value: op, label: _operatorLabel(op)),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    onChanged(
                      rule.copyWith(op: value, value: null, values: null, overrideValues: true),
                    );
                  },
                ),
              ),
              SizedBox(width: 10.w),
              GestureDetector(
                onTap: onRemove,
                child: Container(
                  padding: EdgeInsets.all(8.sp),
                  decoration: BoxDecoration(
                    color: kRedColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10.br),
                  ),
                  child: Icon(Icons.delete_outline_rounded, color: kRedColor, size: 18.ic),
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          Row(
            children: [
              Expanded(
                child: _ValueEditor(
                  column: selectedColumn,
                  op: selectedOp,
                  rule: rule,
                  onChanged: onChanged,
                ),
              ),
              SizedBox(width: 10.w),
              _ToggleChip(
                label: 'NOT',
                isActive: rule.negated,
                onTap: () => onChanged(rule.copyWith(negated: !rule.negated)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ValueEditor extends StatelessWidget {
  const _ValueEditor({
    required this.column,
    required this.op,
    required this.rule,
    required this.onChanged,
  });

  final GamebaseSearchColumnMetadata? column;
  final String op;
  final GamebaseFilterRule rule;
  final ValueChanged<GamebaseFilterRule> onChanged;

  @override
  Widget build(BuildContext context) {
    final needsNoValue = op == 'isNull' || op == 'isNotNull';
    final needsMultiple = op == 'in' || op == 'nin' || op == 'between';

    if (needsNoValue) {
      return Text(
        'No value',
        style: AppTypography.textSmRegular.copyWith(
          color: kWhiteColor.withValues(alpha: 0.55),
        ),
      );
    }

    final col = column;
    if (col == null) {
      return _TextInput(
        value: rule.value ?? '',
        hint: 'Value',
        onChanged: (v) => onChanged(rule.copyWith(value: v)),
      );
    }

    final enumValues = col.enumValues;
    if (!needsMultiple && enumValues != null && enumValues.isNotEmpty) {
      final currentValue = rule.value;
      return _Dropdown<String>(
        value: currentValue != null && enumValues.contains(currentValue) ? currentValue : null,
        hint: 'Select value',
        items: [for (final v in enumValues) _DropdownItem(value: v, label: v)],
        onChanged: (v) => onChanged(rule.copyWith(value: v)),
      );
    }

    if (!needsMultiple) {
      final type = col.type;
      final hint = type == 'datetime' ? 'YYYY-MM-DD or ISO date' : 'Value';
      return _TextInput(
        value: rule.value ?? '',
        hint: hint,
        onChanged: (v) => onChanged(rule.copyWith(value: v)),
        keyboardType: _keyboardTypeFor(type),
      );
    }

    final existing = rule.values ?? const [];
    final label = op == 'between' ? 'A,B' : 'A,B,C';
    return _TextInput(
      value: existing.join(','),
      hint: label,
      onChanged: (v) {
        final parts = v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        onChanged(rule.copyWith(values: parts, overrideValues: true));
      },
    );
  }

  TextInputType _keyboardTypeFor(String? type) {
    switch ((type ?? '').toLowerCase()) {
      case 'integer':
      case 'number':
        return TextInputType.number;
      default:
        return TextInputType.text;
    }
  }
}

class _ColumnsSheet extends ConsumerWidget {
  const _ColumnsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchAsync = ref.watch(gamebaseDatabaseSearchProvider);

    return searchAsync.when(
      loading: () => SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 32.h),
          child: const Center(
            child: CircularProgressIndicator(color: kPrimaryColor),
          ),
        ),
      ),
      error: (error, _) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
          child: _InlineError(message: error.toString()),
        ),
      ),
      data: (state) {
        final all = state.resource.columns;
        final selected = state.selectedColumns.toSet();

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: kWhiteColor.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(10.br),
                  ),
                ),
                SizedBox(height: 14.h),
                Row(
                  children: [
                    Text(
                      'Columns',
                      style: AppTypography.textMdMedium.copyWith(
                        color: kWhiteColor,
                      ),
                    ),
                    const Spacer(),
                    _SmallTextButton(
                      label: 'Reset',
                      onTap: () => ref
                          .read(gamebaseDatabaseSearchProvider.notifier)
                          .setSelectedColumns(
                            state.resource.defaultSearchColumns.isNotEmpty
                                ? state.resource.defaultSearchColumns
                                : [state.resource.primaryKey],
                          ),
                    ),
                  ],
                ),
                SizedBox(height: 12.h),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: all.length,
                    itemBuilder: (context, index) {
                      final col = all[index];
                      final isSelected = selected.contains(col.name);
                      return CheckboxListTile(
                        value: isSelected,
                        onChanged: (checked) {
                          final next = {...selected};
                          if (checked == true) {
                            next.add(col.name);
                          } else {
                            next.remove(col.name);
                          }
                          ref
                              .read(gamebaseDatabaseSearchProvider.notifier)
                              .setSelectedColumns(next.toList());
                        },
                        title: Text(
                          _humanize(col.name),
                          style: AppTypography.textSmRegular.copyWith(
                            color: kWhiteColor,
                          ),
                        ),
                        subtitle: Text(
                          col.type,
                          style: AppTypography.textXsRegular.copyWith(
                            color: kWhiteColor.withValues(alpha: 0.55),
                          ),
                        ),
                        activeColor: kPrimaryColor,
                        checkColor: kBlackColor,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SortSheet extends ConsumerWidget {
  const _SortSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchAsync = ref.watch(gamebaseDatabaseSearchProvider);

    return searchAsync.when(
      loading: () => SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 32.h),
          child: const Center(
            child: CircularProgressIndicator(color: kPrimaryColor),
          ),
        ),
      ),
      error: (error, _) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
          child: _InlineError(message: error.toString()),
        ),
      ),
      data: (state) {
        final sortable = state.resource.sortableColumns;
        final current = state.orderBy.isNotEmpty ? state.orderBy.first : null;

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: kWhiteColor.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(10.br),
                  ),
                ),
                SizedBox(height: 14.h),
                Row(
                  children: [
                    Text(
                      'Sort',
                      style: AppTypography.textMdMedium.copyWith(
                        color: kWhiteColor,
                      ),
                    ),
                    const Spacer(),
                    _SmallTextButton(
                      label: 'Clear',
                      onTap: () => ref
                          .read(gamebaseDatabaseSearchProvider.notifier)
                          .setOrderBy(const []),
                      color: kRedColor,
                    ),
                  ],
                ),
                SizedBox(height: 12.h),
                if (sortable.isEmpty)
                  Text(
                    'No sortable columns',
                    style: AppTypography.textSmRegular.copyWith(
                      color: kWhiteColor.withValues(alpha: 0.6),
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: _Dropdown<String>(
                          value: current?.field,
                          hint: 'Column',
                          items: [
                            for (final c in sortable)
                              _DropdownItem(
                                value: c.name,
                                label: _humanize(c.name),
                              ),
                          ],
                          onChanged: (field) {
                            if (field == null) return;
                            final direction = current?.direction ??
                                GamebaseOrderDirection.desc;
                            ref
                                .read(gamebaseDatabaseSearchProvider.notifier)
                                .setOrderBy([
                                  GamebaseOrderByRule(
                                    field: field,
                                    direction: direction,
                                  ),
                                ]);
                          },
                        ),
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: _Dropdown<GamebaseOrderDirection>(
                          value: current?.direction,
                          hint: 'Direction',
                          items: const [
                            _DropdownItem(
                              value: GamebaseOrderDirection.asc,
                              label: 'Ascending',
                            ),
                            _DropdownItem(
                              value: GamebaseOrderDirection.desc,
                              label: 'Descending',
                            ),
                          ],
                          onChanged: (dir) {
                            final field = current?.field ?? sortable.first.name;
                            final direction =
                                dir ?? GamebaseOrderDirection.desc;
                            ref
                                .read(gamebaseDatabaseSearchProvider.notifier)
                                .setOrderBy([
                                  GamebaseOrderByRule(
                                    field: field,
                                    direction: direction,
                                  ),
                                ]);
                          },
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RowDetailsSheet extends StatelessWidget {
  const _RowDetailsSheet({
    required this.state,
    required this.row,
    required this.onAddToBook,
  });

  final GamebaseDatabaseSearchState state;
  final Map<String, dynamic> row;
  final VoidCallback onAddToBook;

  @override
  Widget build(BuildContext context) {
    final id = row[state.resource.primaryKey]?.toString();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: kWhiteColor.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(10.br),
              ),
            ),
            SizedBox(height: 14.h),
            Row(
              children: [
                Expanded(
                  child: Text(
                    id == null || id.isEmpty ? 'Row' : 'Game $id',
                    style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (id != null && id.isNotEmpty)
                  IconButton(
                    tooltip: 'Copy id',
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: id));
                      if (context.mounted) {
                        HapticFeedback.lightImpact();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Copied id',
                              style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
                            ),
                            backgroundColor: kBlack2Color.withValues(alpha: 0.95),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    icon: Icon(Icons.copy_rounded, color: kWhiteColor.withValues(alpha: 0.8)),
                  ),
              ],
            ),
            SizedBox(height: 10.h),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: row.entries.length,
                separatorBuilder: (_, __) => SizedBox(height: 10.h),
                itemBuilder: (context, index) {
                  final entry = row.entries.elementAt(index);
                  return _KeyValueRow(
                    label: entry.key,
                    value: entry.value,
                  );
                },
              ),
            ),
            SizedBox(height: 12.h),
            _PrimaryButton(
              label: 'Add to Book',
              onTap: () {
                Navigator.of(context).pop();
                onAddToBook();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BookPickerSheet extends StatefulWidget {
  const _BookPickerSheet({
    required this.folders,
    required this.onCreateBook,
  });

  final List<LibraryFolder> folders;
  final Future<LibraryFolder?> Function() onCreateBook;

  @override
  State<_BookPickerSheet> createState() => _BookPickerSheetState();
}

class _BookPickerSheetState extends State<_BookPickerSheet> {
  bool _isCreating = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 16.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: kWhiteColor.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(10.br),
              ),
            ),
            SizedBox(height: 14.h),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Choose a Book',
                style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
              ),
            ),
            SizedBox(height: 10.h),
            _buildCreateTile(context),
            SizedBox(height: 10.h),
            if (widget.folders.isEmpty)
              Text(
                'No books yet.',
                style: AppTypography.textSmRegular.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.65),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: widget.folders.length,
                  separatorBuilder: (_, __) => SizedBox(height: 10.h),
                  itemBuilder: (context, index) {
                    final folder = widget.folders[index];
                    return ListTile(
                      onTap: () => Navigator.of(context).pop(folder),
                      title: Text(
                        folder.name,
                        style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
                      ),
                      trailing: Icon(Icons.chevron_right_rounded, color: kWhiteColor.withValues(alpha: 0.6)),
                      contentPadding: EdgeInsets.zero,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateTile(BuildContext context) {
    return ListTile(
      onTap:
          _isCreating
              ? null
	              : () async {
	                setState(() => _isCreating = true);
	                final folder = await widget.onCreateBook();
	                if (!context.mounted) return;
	                setState(() => _isCreating = false);
	                if (folder != null) {
	                  Navigator.of(context).pop(folder);
	                }
	              },
      leading: Icon(
        Icons.create_new_folder_outlined,
        color: kPrimaryColor,
      ),
      title: Text(
        'Create new book',
        style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
      ),
      trailing:
          _isCreating
              ? SizedBox(
                width: 18.sp,
                height: 18.sp,
                child: const CircularProgressIndicator(
                  color: kPrimaryColor,
                  strokeWidth: 2,
                ),
              )
              : Icon(
                Icons.chevron_right_rounded,
                color: kWhiteColor.withValues(alpha: 0.6),
              ),
      contentPadding: EdgeInsets.zero,
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.label, required this.value});

  final String label;
  final dynamic value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(12.sp),
      decoration: BoxDecoration(
        color: kBlack3Color,
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: kWhiteColor.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _humanize(label),
            style: AppTypography.textXsMedium.copyWith(
              color: kWhiteColor.withValues(alpha: 0.6),
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            _stringify(value),
            style: AppTypography.textSmRegular.copyWith(
              color: kWhiteColor.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  String _stringify(dynamic v) {
    if (v == null) return '—';
    if (v is String) return v.isEmpty ? '—' : v;
    if (v is num || v is bool) return v.toString();
    try {
      return jsonEncode(v);
    } catch (_) {
      return v.toString();
    }
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: 12.h),
        decoration: BoxDecoration(
          color: kPrimaryColor,
          borderRadius: BorderRadius.circular(12.br),
        ),
        child: Center(
          child: Text(
            label,
            style: AppTypography.textSmBold.copyWith(color: kBlackColor),
          ),
        ),
      ),
    );
  }
}

class _SmallTextButton extends StatelessWidget {
  const _SmallTextButton({
    required this.label,
    required this.onTap,
    this.color,
  });

  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
        child: Text(
          label,
          style: AppTypography.textSmMedium.copyWith(
            color: color ?? kPrimaryColor,
          ),
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: isActive ? kPrimaryColor.withValues(alpha: 0.2) : kBlack2Color,
          borderRadius: BorderRadius.circular(12.br),
          border: Border.all(
            color:
                isActive
                    ? kPrimaryColor.withValues(alpha: 0.6)
                    : kWhiteColor.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: AppTypography.textXsMedium.copyWith(
            color: isActive ? kPrimaryColor : kWhiteColor.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}

class _SegmentedControl<T> extends StatelessWidget {
  const _SegmentedControl({
    required this.value,
    required this.values,
    required this.labels,
    required this.onChanged,
  });

  final T value;
  final List<T> values;
  final List<String> labels;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kBlack3Color,
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: kWhiteColor.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(values.length, (index) {
          final v = values[index];
          final selected = v == value;
          return GestureDetector(
            onTap: () => onChanged(v),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: selected ? kPrimaryColor : Colors.transparent,
                borderRadius: BorderRadius.circular(10.br),
              ),
              child: Text(
                labels[index],
                style: AppTypography.textXsMedium.copyWith(
                  color: selected ? kBlackColor : kWhiteColor.withValues(alpha: 0.75),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _DropdownItem<T> {
  const _DropdownItem({required this.value, required this.label});

  final T value;
  final String label;
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
  });

  final T? value;
  final String? hint;
  final List<_DropdownItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w),
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: kWhiteColor.withValues(alpha: 0.08)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: kBlack2Color,
          iconEnabledColor: kWhiteColor.withValues(alpha: 0.7),
          hint:
              hint == null
                  ? null
                  : Text(
                    hint!,
                    style: AppTypography.textSmRegular.copyWith(
                      color: kWhiteColor.withValues(alpha: 0.55),
                    ),
                  ),
          items: [
            for (final item in items)
              DropdownMenuItem<T>(
                value: item.value,
                child: Text(
                  item.label,
                  style: AppTypography.textSmRegular.copyWith(color: kWhiteColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _TextInput extends StatelessWidget {
  const _TextInput({
    required this.value,
    required this.hint,
    required this.onChanged,
    this.keyboardType,
  });

  final String value;
  final String hint;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController(text: value);
    controller.selection = TextSelection.fromPosition(
      TextPosition(offset: controller.text.length),
    );

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: kWhiteColor.withValues(alpha: 0.08)),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: AppTypography.textSmRegular.copyWith(color: kWhiteColor),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: AppTypography.textSmRegular.copyWith(
            color: kWhiteColor.withValues(alpha: 0.5),
          ),
          border: InputBorder.none,
        ),
        onChanged: onChanged,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_outlined, color: kWhiteColor.withValues(alpha: 0.35), size: 56.sp),
          SizedBox(height: 12.h),
          Text(
            'No results',
            style: AppTypography.textMdMedium.copyWith(color: kWhiteColor.withValues(alpha: 0.85)),
          ),
          SizedBox(height: 6.h),
          Text(
            'Try adjusting your query or filters.',
            style: AppTypography.textSmRegular.copyWith(color: kWhiteColor.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(12.sp),
      decoration: BoxDecoration(
        color: kRedColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: kRedColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: kRedColor, size: 18.sp),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              message,
              style: AppTypography.textSmRegular.copyWith(color: kRedColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.sp),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 56.sp, color: kRedColor.withValues(alpha: 0.8)),
            SizedBox(height: 12.h),
            Text(
              'Failed to load database',
              style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
            ),
            SizedBox(height: 8.h),
            Text(
              message,
              style: AppTypography.textSmRegular.copyWith(color: kWhiteColor.withValues(alpha: 0.65)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

String _humanize(String name) {
  return name
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m.group(1)} ${m.group(2)}')
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

String _operatorLabel(String op) {
  switch (op) {
    case 'eq':
      return 'Equals';
    case 'ne':
      return 'Not Equals';
    case 'lt':
      return 'Less Than';
    case 'lte':
      return 'Less or Equal';
    case 'gt':
      return 'Greater Than';
    case 'gte':
      return 'Greater or Equal';
    case 'in':
      return 'In List';
    case 'nin':
      return 'Not In List';
    case 'like':
      return 'Like';
    case 'ilike':
      return 'Like (CI)';
    case 'startsWith':
      return 'Starts With';
    case 'endsWith':
      return 'Ends With';
    case 'contains':
      return 'Contains';
    case 'notContains':
      return 'Not Contains';
    case 'between':
      return 'Between';
    case 'isNull':
      return 'Is Empty';
    case 'isNotNull':
      return 'Is Not Empty';
    default:
      return op;
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
