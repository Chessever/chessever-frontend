import 'dart:async';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/utils/twic_player_enrichment.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum GamebaseFilterGroupMode { and, or }

enum GamebaseOrderDirection { asc, desc }

class GamebaseFilterRule {
  const GamebaseFilterRule({
    required this.field,
    required this.op,
    this.value,
    this.values,
    this.negated = false,
  });

  final String field;
  final String op;
  final String? value;
  final List<String>? values;
  final bool negated;

  GamebaseFilterRule copyWith({
    String? field,
    String? op,
    String? value,
    List<String>? values,
    bool? negated,
    bool overrideValues = false,
  }) {
    return GamebaseFilterRule(
      field: field ?? this.field,
      op: op ?? this.op,
      value: value ?? this.value,
      values: overrideValues ? values : (values ?? this.values),
      negated: negated ?? this.negated,
    );
  }
}

class GamebaseOrderByRule {
  const GamebaseOrderByRule({required this.field, required this.direction});

  final String field;
  final GamebaseOrderDirection direction;

  GamebaseOrderByRule copyWith({
    String? field,
    GamebaseOrderDirection? direction,
  }) {
    return GamebaseOrderByRule(
      field: field ?? this.field,
      direction: direction ?? this.direction,
    );
  }
}

class GamebaseDatabaseSearchState {
  const GamebaseDatabaseSearchState({
    required this.metadata,
    required this.resource,
    required this.query,
    required this.filters,
    required this.filterMode,
    required this.orderBy,
    required this.selectedColumns,
    required this.pageNumber,
    required this.pageSize,
    required this.rows,
    required this.pagination,
    required this.isQueryLoading,
    required this.lastQueryError,
  });

  final GamebaseSearchMetadata metadata;
  final GamebaseSearchResourceMetadata resource;

  final String query;

  final List<GamebaseFilterRule> filters;
  final GamebaseFilterGroupMode filterMode;

  final List<GamebaseOrderByRule> orderBy;

  final List<String> selectedColumns;

  final int pageNumber;
  final int pageSize;
  final List<Map<String, dynamic>> rows;
  final GamebasePaginationMetadata pagination;

  final bool isQueryLoading;
  final String? lastQueryError;

  GamebaseDatabaseSearchState copyWith({
    GamebaseSearchMetadata? metadata,
    GamebaseSearchResourceMetadata? resource,
    String? query,
    List<GamebaseFilterRule>? filters,
    GamebaseFilterGroupMode? filterMode,
    List<GamebaseOrderByRule>? orderBy,
    List<String>? selectedColumns,
    int? pageNumber,
    int? pageSize,
    List<Map<String, dynamic>>? rows,
    GamebasePaginationMetadata? pagination,
    bool? isQueryLoading,
    String? lastQueryError,
  }) {
    return GamebaseDatabaseSearchState(
      metadata: metadata ?? this.metadata,
      resource: resource ?? this.resource,
      query: query ?? this.query,
      filters: filters ?? this.filters,
      filterMode: filterMode ?? this.filterMode,
      orderBy: orderBy ?? this.orderBy,
      selectedColumns: selectedColumns ?? this.selectedColumns,
      pageNumber: pageNumber ?? this.pageNumber,
      pageSize: pageSize ?? this.pageSize,
      rows: rows ?? this.rows,
      pagination: pagination ?? this.pagination,
      isQueryLoading: isQueryLoading ?? this.isQueryLoading,
      lastQueryError: lastQueryError,
    );
  }

  bool get hasActiveFilters => filters.isNotEmpty;

  bool get hasActiveQuery => query.trim().isNotEmpty;

  bool get hasSort => orderBy.isNotEmpty;

  bool get canGoPrev => pagination.pageNumber > 1;

  bool get canGoNext => pagination.hasMore;

  Map<String, dynamic> buildRequestBody() {
    final body = <String, dynamic>{
      'resource': resource.name,
      'pageNumber': pageNumber,
      'pageSize': pageSize,
      'includeTotal': true,
    };

    final qTrimmed = query.trim();
    if (qTrimmed.isNotEmpty) {
      body['q'] = qTrimmed;
    }

    final where = _buildWhereExpression();
    if (where != null) {
      body['where'] = where;
    }

    if (orderBy.isNotEmpty) {
      body['orderBy'] =
          orderBy
              .map(
                (o) => {
                  'field': o.field,
                  'direction':
                      o.direction == GamebaseOrderDirection.asc
                          ? 'asc'
                          : 'desc',
                },
              )
              .toList();
    }

    if (selectedColumns.isNotEmpty) {
      body['select'] = selectedColumns;
    }

    return body;
  }

  Map<String, dynamic>? _buildWhereExpression() {
    if (filters.isEmpty) return null;

    final expressions = <Map<String, dynamic>>[];

    for (final rule in filters) {
      final column = resource.columnByName(rule.field);
      final condition = _ruleToConditionMap(rule, column);
      if (condition == null) continue;

      if (rule.negated) {
        expressions.add({'not': condition});
      } else {
        expressions.add(condition);
      }
    }

    if (expressions.isEmpty) return null;

    return {
      filterMode == GamebaseFilterGroupMode.and ? 'and' : 'or': expressions,
    };
  }

  Map<String, dynamic>? _ruleToConditionMap(
    GamebaseFilterRule rule,
    GamebaseSearchColumnMetadata? column,
  ) {
    final op = rule.op.trim();
    if (op.isEmpty) return null;

    final field = rule.field.trim();
    if (field.isEmpty) return null;

    final needsNoValue = op == 'isNull' || op == 'isNotNull';
    final needsMultiple = op == 'in' || op == 'nin' || op == 'between';

    if (needsNoValue) {
      return {'field': field, 'op': op};
    }

    if (needsMultiple) {
      final raw = rule.values ?? const [];
      final cleaned =
          raw.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      if (cleaned.isEmpty) return null;
      final typed = cleaned.map((v) => _castValue(v, column)).toList();
      return {'field': field, 'op': op, 'values': typed};
    }

    final value = rule.value?.trim() ?? '';
    if (value.isEmpty) return null;
    return {'field': field, 'op': op, 'value': _castValue(value, column)};
  }

  dynamic _castValue(String input, GamebaseSearchColumnMetadata? column) {
    final type = (column?.type ?? 'string').toLowerCase().trim();

    switch (type) {
      case 'integer':
        return int.tryParse(input) ?? input;
      case 'number':
        return double.tryParse(input) ?? input;
      case 'boolean':
        final lowered = input.toLowerCase().trim();
        if (lowered == 'true' || lowered == '1' || lowered == 'yes') {
          return true;
        }
        if (lowered == 'false' || lowered == '0' || lowered == 'no') {
          return false;
        }
        return input;
      case 'datetime':
        final dt = DateTime.tryParse(input);
        return dt?.toIso8601String() ?? input;
      case 'uuid':
      case 'json':
      case 'string':
      default:
        return input;
    }
  }

  static GamebaseDatabaseSearchState initial({
    required GamebaseSearchMetadata metadata,
    required GamebaseSearchResourceMetadata resource,
  }) {
    final allColumns = resource.columns.map((c) => c.name).toList();
    final columnSet = allColumns.toSet();

    final curated = <String>[];
    for (final name in <String>[
      resource.primaryKey,
      'date',
      'timeControl',
      'result',
      'whitePlayerId',
      'blackPlayerId',
      'white_player_id',
      'black_player_id',
      'tour_id',
      'tournament_id',
    ]) {
      if (columnSet.contains(name) && !curated.contains(name)) {
        curated.add(name);
      }
    }

    final fallback =
        resource.defaultSearchColumns.isNotEmpty
            ? resource.defaultSearchColumns
            : allColumns.take(6).toList();

    final safeColumns =
        curated.isNotEmpty
            ? curated
            : (fallback.isNotEmpty ? fallback : <String>[resource.primaryKey]);

    return GamebaseDatabaseSearchState(
      metadata: metadata,
      resource: resource,
      query: '',
      filters: const [],
      filterMode: GamebaseFilterGroupMode.and,
      orderBy: const [],
      selectedColumns: safeColumns,
      pageNumber: 1,
      pageSize: 20,
      rows: const [],
      pagination: const GamebasePaginationMetadata(pageNumber: 1, pageSize: 20),
      isQueryLoading: false,
      lastQueryError: null,
    );
  }
}

final gamebaseDatabaseSearchProvider = StateNotifierProvider.autoDispose<
  GamebaseDatabaseSearchNotifier,
  AsyncValue<GamebaseDatabaseSearchState>
>((ref) => GamebaseDatabaseSearchNotifier(ref));

class GamebaseDatabaseSearchNotifier
    extends StateNotifier<AsyncValue<GamebaseDatabaseSearchState>> {
  GamebaseDatabaseSearchNotifier(this._ref)
    : super(const AsyncValue.loading()) {
    _initialize();
  }

  final Ref _ref;
  Timer? _debounceTimer;

  int _token = 0;

  Future<void> _initialize() async {
    try {
      final repository = _ref.read(gamebaseRepositoryProvider);
      final metadata = await repository.getSearchMetadata();
      final resource = metadata.resourceByName('game');
      if (resource == null) {
        throw Exception('Search metadata missing "game" resource');
      }

      state = AsyncValue.data(
        GamebaseDatabaseSearchState.initial(
          metadata: metadata,
          resource: resource,
        ),
      );
      await refresh();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void setQuery(String query) {
    final current = state.valueOrNull;
    if (current == null) return;

    final trimmed = query;
    state = AsyncValue.data(
      current.copyWith(query: trimmed, pageNumber: 1, lastQueryError: null),
    );

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 320), refresh);
  }

  void setFilterMode(GamebaseFilterGroupMode mode) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(
      current.copyWith(filterMode: mode, pageNumber: 1, lastQueryError: null),
    );
    unawaited(refresh());
  }

  void addFilterRule(GamebaseFilterRule rule) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(
      current.copyWith(
        filters: [...current.filters, rule],
        pageNumber: 1,
        lastQueryError: null,
      ),
    );
    unawaited(refresh());
  }

  void updateFilterRule(int index, GamebaseFilterRule rule) {
    final current = state.valueOrNull;
    if (current == null) return;
    if (index < 0 || index >= current.filters.length) return;
    final next = [...current.filters];
    next[index] = rule;
    state = AsyncValue.data(
      current.copyWith(filters: next, pageNumber: 1, lastQueryError: null),
    );
    unawaited(refresh());
  }

  void removeFilterRule(int index) {
    final current = state.valueOrNull;
    if (current == null) return;
    if (index < 0 || index >= current.filters.length) return;
    final next = [...current.filters]..removeAt(index);
    state = AsyncValue.data(
      current.copyWith(filters: next, pageNumber: 1, lastQueryError: null),
    );
    unawaited(refresh());
  }

  void clearFilters() {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(
      current.copyWith(filters: const [], pageNumber: 1, lastQueryError: null),
    );
    unawaited(refresh());
  }

  void setOrderBy(List<GamebaseOrderByRule> orderBy) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(
      current.copyWith(orderBy: orderBy, pageNumber: 1, lastQueryError: null),
    );
    unawaited(refresh());
  }

  void setSelectedColumns(List<String> columns) {
    final current = state.valueOrNull;
    if (current == null) return;
    final unique = <String>{};
    for (final c in columns) {
      final trimmed = c.trim();
      if (trimmed.isNotEmpty) unique.add(trimmed);
    }

    final fallback =
        unique.isNotEmpty
            ? unique.toList()
            : <String>[current.resource.primaryKey];

    state = AsyncValue.data(
      current.copyWith(selectedColumns: fallback, lastQueryError: null),
    );
    unawaited(refresh());
  }

  Future<void> goToPage(int pageNumber) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final nextPage = pageNumber < 1 ? 1 : pageNumber;
    state = AsyncValue.data(
      current.copyWith(pageNumber: nextPage, lastQueryError: null),
    );
    await refresh();
  }

  Future<void> nextPage() async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (!current.canGoNext) return;
    await goToPage(current.pagination.pageNumber + 1);
  }

  Future<void> prevPage() async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (!current.canGoPrev) return;
    await goToPage(current.pagination.pageNumber - 1);
  }

  Future<void> refresh({bool exactCount = false}) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final token = ++_token;
    state = AsyncValue.data(
      current.copyWith(isQueryLoading: true, lastQueryError: null),
    );

    try {
      final repository = _ref.read(gamebaseRepositoryProvider);
      final body =
          current.buildRequestBody()
            ..['countMode'] = exactCount ? 'exact' : 'auto';
      final response = await repository.queryResource(body: body);
      var enrichedRows = response.data;
      final fideIds = collectFideIdsFromRows(enrichedRows);
      if (fideIds.isNotEmpty) {
        final playersByFideId = await _ref
            .read(chessPlayerRepositoryProvider)
            .getPlayersByFideIds(fideIds);
        enrichedRows = enrichSearchRowsWithChessPlayers(
          enrichedRows,
          playersByFideId,
        );
      }

      if (!mounted || token != _token) return;

      state = AsyncValue.data(
        current.copyWith(
          rows: enrichedRows,
          pagination: response.metadata,
          pageNumber: response.metadata.pageNumber,
          pageSize: current.pageSize,
          isQueryLoading: false,
          lastQueryError: null,
        ),
      );
    } catch (e, st) {
      if (!mounted || token != _token) return;
      debugPrint('[GamebaseDatabaseSearch] error: $e');
      state = AsyncValue.data(
        current.copyWith(
          isQueryLoading: false,
          lastQueryError: userFacingError(
            e,
            fallback: 'Could not run this search. Please try again.',
          ),
        ),
      );
      if (kDebugMode) {
        debugPrintStack(stackTrace: st);
      }
    }
  }

  Future<void> requestExactCount() async {
    await refresh(exactCount: true);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
