import 'dart:async';

import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/gamebase/search/gamebase_search_models.dart';
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
      body['orderBy'] = orderBy
          .map(
            (o) => {
              'field': o.field,
              'direction': o.direction == GamebaseOrderDirection.asc
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
        if (lowered == 'true' || lowered == '1' || lowered == 'yes') return true;
        if (lowered == 'false' || lowered == '0' || lowered == 'no') return false;
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
    ]) {
      if (columnSet.contains(name) && !curated.contains(name)) {
        curated.add(name);
      }
    }

    final fallback =
        resource.defaultSearchColumns.isNotEmpty ? resource.defaultSearchColumns : allColumns.take(6).toList();

    final safeColumns = curated.isNotEmpty
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
    GamebaseDatabaseSearchNotifier, AsyncValue<GamebaseDatabaseSearchState>>(
  (ref) => GamebaseDatabaseSearchNotifier(ref),
);

class GamebaseDatabaseSearchNotifier
    extends StateNotifier<AsyncValue<GamebaseDatabaseSearchState>> {
  GamebaseDatabaseSearchNotifier(this._ref) : super(const AsyncValue.loading()) {
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
        GamebaseDatabaseSearchState.initial(metadata: metadata, resource: resource),
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
      current.copyWith(
        query: trimmed,
        pageNumber: 1,
        lastQueryError: null,
      ),
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

    final fallback = unique.isNotEmpty ? unique.toList() : <String>[
      current.resource.primaryKey,
    ];

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

  Future<void> refresh() async {
    final current = state.valueOrNull;
    if (current == null) return;

    final token = ++_token;
    state = AsyncValue.data(current.copyWith(isQueryLoading: true, lastQueryError: null));

    try {
      final repository = _ref.read(gamebaseRepositoryProvider);
      // NOTE: `/api/search/query` for `resource=game` is currently unreliable in
      // production (500 "Unknown Error"). We fall back to global search and
      // apply the sheet's filters client-side so Library search stays usable.
      final query = current.query.trim();
      if (query.isEmpty) {
        if (!mounted || token != _token) return;
        state = AsyncValue.data(
          current.copyWith(
            rows: const [],
            pagination: const GamebasePaginationMetadata(pageNumber: 1, pageSize: 20),
            pageNumber: 1,
            pageSize: current.pageSize,
            isQueryLoading: false,
            lastQueryError: null,
          ),
        );
        return;
      }

      final response = await repository.globalSearch(
        query: query,
        pageNumber: current.pageNumber,
        // Fetch extra to account for mixed player/game results.
        pageSize: (current.pageSize * 3).clamp(20, 120),
      );

      if (!mounted || token != _token) return;

      bool matchesRule(Map<String, dynamic> row, GamebaseFilterRule rule) {
        Object? value = row[rule.field];
        // Back-compat aliases for mixed payloads.
        if (value == null) {
          if (rule.field == 'whiteName') value = row['white'] ?? row['whiteName'];
          if (rule.field == 'blackName') value = row['black'] ?? row['blackName'];
        }

        final op = rule.op.trim();
        if (op.isEmpty) return true;

        bool isNull(Object? v) => v == null || (v is String && v.trim().isEmpty);

        if (op == 'isNull') return isNull(value);
        if (op == 'isNotNull') return !isNull(value);

        // Numeric comparisons
        num? asNum(Object? v) {
          if (v is num) return v;
          return num.tryParse(v?.toString() ?? '');
        }

        // String comparisons (case-insensitive)
        String asStr(Object? v) => (v?.toString() ?? '').trim();

        if (op == 'eq') {
          if (value is num || num.tryParse(value?.toString() ?? '') != null) {
            final left = asNum(value);
            final right = asNum(rule.value);
            return left != null && right != null && left == right;
          }
          return asStr(value).toLowerCase() == asStr(rule.value).toLowerCase();
        }
        if (op == 'neq') {
          return !matchesRule(row, rule.copyWith(op: 'eq'));
        }
        if (op == 'contains') {
          final hay = asStr(value).toLowerCase();
          final needle = asStr(rule.value).toLowerCase();
          return needle.isNotEmpty && hay.contains(needle);
        }
        if (op == 'in' || op == 'nin') {
          final values = rule.values ?? const [];
          final needle = asStr(value).toLowerCase();
          final hit = values.any((v) => v.toLowerCase() == needle);
          return op == 'in' ? hit : !hit;
        }
        if (op == 'gt' || op == 'gte' || op == 'lt' || op == 'lte') {
          final left = asNum(value);
          final right = asNum(rule.value);
          if (left == null || right == null) return false;
          switch (op) {
            case 'gt':
              return left > right;
            case 'gte':
              return left >= right;
            case 'lt':
              return left < right;
            case 'lte':
              return left <= right;
          }
        }
        if (op == 'between') {
          final values = rule.values ?? const [];
          if (values.length < 2) return true;
          final left = asNum(value);
          final lo = asNum(values[0]);
          final hi = asNum(values[1]);
          if (left == null || lo == null || hi == null) return false;
          final min = lo < hi ? lo : hi;
          final max = lo < hi ? hi : lo;
          return left >= min && left <= max;
        }

        return true;
      }

      bool matchesAllFilters(Map<String, dynamic> row) {
        if (current.filters.isEmpty) return true;
        final checks =
            current.filters.map((rule) {
              final base = matchesRule(row, rule);
              return rule.negated ? !base : base;
            }).toList(growable: false);

        return current.filterMode == GamebaseFilterGroupMode.and
            ? checks.every((ok) => ok)
            : checks.any((ok) => ok);
      }

      final gameRows =
          response.results
              .where((r) => r.resource == 'game')
              .map((r) {
                final preview = r.preview ?? const <String, dynamic>{};
                final id = preview['id']?.toString() ?? r.id;
                return <String, dynamic>{
                  'id': id,
                  'label': r.label,
                  'snippet': r.snippet,
                  ...preview,
                };
              })
              .where(matchesAllFilters)
              .toList(growable: false);

      state = AsyncValue.data(
        current.copyWith(
          rows: gameRows,
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
          lastQueryError: e.toString(),
        ),
      );
      if (kDebugMode) {
        debugPrintStack(stackTrace: st);
      }
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
