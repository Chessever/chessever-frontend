class GamebasePaginationMetadata {
  const GamebasePaginationMetadata({
    required this.pageNumber,
    required this.pageSize,
    this.totalCount,
    this.hasMoreValue,
    this.totalCountIsEstimate = false,
  });

  final int pageNumber;
  final int pageSize;
  final int? totalCount;
  final bool? hasMoreValue;
  final bool totalCountIsEstimate;

  factory GamebasePaginationMetadata.fromJson(Map<String, dynamic> json) {
    return GamebasePaginationMetadata(
      pageNumber: (json['pageNumber'] as num?)?.toInt() ?? 1,
      pageSize: (json['pageSize'] as num?)?.toInt() ?? 20,
      totalCount: (json['totalCount'] as num?)?.toInt(),
      hasMoreValue: json['hasMore'] as bool?,
      totalCountIsEstimate: json['totalCountIsEstimate'] as bool? ?? false,
    );
  }

  bool get hasTotal => totalCount != null;

  bool get hasMore {
    // Prefer server-provided hasMore when available (avoids expensive COUNT(*) queries).
    if (hasMoreValue != null) return hasMoreValue!;
    if (totalCount == null) return true;
    return pageNumber * pageSize < totalCount!;
  }
}

class GamebaseSearchColumnMetadata {
  const GamebaseSearchColumnMetadata({
    required this.name,
    required this.type,
    required this.nullable,
    required this.searchable,
    required this.filterable,
    required this.sortable,
    required this.operators,
    this.description,
    this.enumValues,
  });

  final String name;
  final String type;
  final bool nullable;
  final String? description;
  final bool searchable;
  final bool filterable;
  final bool sortable;
  final List<String> operators;
  final List<String>? enumValues;

  factory GamebaseSearchColumnMetadata.fromJson(Map<String, dynamic> json) {
    return GamebaseSearchColumnMetadata(
      name: (json['name'] as String?)?.trim() ?? '',
      type: (json['type'] as String?)?.trim() ?? 'string',
      nullable: json['nullable'] as bool? ?? false,
      description: json['description'] as String?,
      searchable: json['searchable'] as bool? ?? false,
      filterable: json['filterable'] as bool? ?? false,
      sortable: json['sortable'] as bool? ?? false,
      operators:
          (json['operators'] as List?)
              ?.whereType<String>()
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const [],
      enumValues:
          (json['enumValues'] as List?)
              ?.whereType<String>()
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList(),
    );
  }
}

class GamebaseSearchResourceMetadata {
  const GamebaseSearchResourceMetadata({
    required this.name,
    required this.label,
    required this.primaryKey,
    required this.defaultSearchColumns,
    required this.columns,
  });

  final String name;
  final String label;
  final String primaryKey;
  final List<String> defaultSearchColumns;
  final List<GamebaseSearchColumnMetadata> columns;

  factory GamebaseSearchResourceMetadata.fromJson(Map<String, dynamic> json) {
    return GamebaseSearchResourceMetadata(
      name: (json['name'] as String?)?.trim() ?? '',
      label: (json['label'] as String?)?.trim() ?? '',
      primaryKey: (json['primaryKey'] as String?)?.trim() ?? 'id',
      defaultSearchColumns:
          (json['defaultSearchColumns'] as List?)
              ?.whereType<String>()
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const [],
      columns:
          (json['columns'] as List?)
              ?.whereType<Map>()
              .map((e) => GamebaseSearchColumnMetadata.fromJson(
                    Map<String, dynamic>.from(e),
                  ))
              .where((c) => c.name.isNotEmpty)
              .toList() ??
          const [],
    );
  }

  GamebaseSearchColumnMetadata? columnByName(String name) {
    try {
      return columns.firstWhere((c) => c.name == name);
    } catch (_) {
      return null;
    }
  }

  List<GamebaseSearchColumnMetadata> get filterableColumns =>
      columns.where((c) => c.filterable).toList();

  List<GamebaseSearchColumnMetadata> get sortableColumns =>
      columns.where((c) => c.sortable).toList();

  List<GamebaseSearchColumnMetadata> get searchableColumns =>
      columns.where((c) => c.searchable).toList();
}

class GamebaseSearchMetadata {
  const GamebaseSearchMetadata({required this.resources});

  final List<GamebaseSearchResourceMetadata> resources;

  factory GamebaseSearchMetadata.fromJson(Map<String, dynamic> json) {
    return GamebaseSearchMetadata(
      resources:
          (json['resources'] as List?)
              ?.whereType<Map>()
              .map((e) => GamebaseSearchResourceMetadata.fromJson(
                    Map<String, dynamic>.from(e),
                  ))
              .where((r) => r.name.isNotEmpty)
              .toList() ??
          const [],
    );
  }

  GamebaseSearchResourceMetadata? resourceByName(String name) {
    try {
      return resources.firstWhere((r) => r.name == name);
    } catch (_) {
      return null;
    }
  }
}

class GamebaseSearchQueryResponse {
  const GamebaseSearchQueryResponse({
    required this.status,
    required this.data,
    required this.metadata,
  });

  final String status;
  final List<Map<String, dynamic>> data;
  final GamebasePaginationMetadata metadata;

  factory GamebaseSearchQueryResponse.fromJson(Map<String, dynamic> json) {
    return GamebaseSearchQueryResponse(
      status: (json['status'] as String?)?.trim() ?? 'unknown',
      data:
          (json['data'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          const [],
      metadata: GamebasePaginationMetadata.fromJson(
        Map<String, dynamic>.from(json['metadata'] as Map? ?? const {}),
      ),
    );
  }
}
