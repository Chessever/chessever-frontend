import 'package:dart_mappable/dart_mappable.dart';

part 'search_models.mapper.dart';

/// Filter operators supported by the search API
@MappableEnum()
enum FilterOperator {
  @MappableValue('eq')
  eq,
  @MappableValue('ne')
  ne,
  @MappableValue('lt')
  lt,
  @MappableValue('lte')
  lte,
  @MappableValue('gt')
  gt,
  @MappableValue('gte')
  gte,
  @MappableValue('in')
  inList,
  @MappableValue('nin')
  notInList,
  @MappableValue('like')
  like,
  @MappableValue('ilike')
  ilike,
  @MappableValue('startsWith')
  startsWith,
  @MappableValue('endsWith')
  endsWith,
  @MappableValue('contains')
  contains,
  @MappableValue('between')
  between,
  @MappableValue('isNull')
  isNull,
  @MappableValue('isNotNull')
  isNotNull,
}

extension FilterOperatorExtension on FilterOperator {
  String get displayName {
    switch (this) {
      case FilterOperator.eq:
        return 'Equals';
      case FilterOperator.ne:
        return 'Not Equals';
      case FilterOperator.lt:
        return 'Less Than';
      case FilterOperator.lte:
        return 'Less or Equal';
      case FilterOperator.gt:
        return 'Greater Than';
      case FilterOperator.gte:
        return 'Greater or Equal';
      case FilterOperator.inList:
        return 'In List';
      case FilterOperator.notInList:
        return 'Not In List';
      case FilterOperator.like:
        return 'Like';
      case FilterOperator.ilike:
        return 'Like (Case Insensitive)';
      case FilterOperator.startsWith:
        return 'Starts With';
      case FilterOperator.endsWith:
        return 'Ends With';
      case FilterOperator.contains:
        return 'Contains';
      case FilterOperator.between:
        return 'Between';
      case FilterOperator.isNull:
        return 'Is Empty';
      case FilterOperator.isNotNull:
        return 'Is Not Empty';
    }
  }

  String get apiValue {
    switch (this) {
      case FilterOperator.eq:
        return 'eq';
      case FilterOperator.ne:
        return 'ne';
      case FilterOperator.lt:
        return 'lt';
      case FilterOperator.lte:
        return 'lte';
      case FilterOperator.gt:
        return 'gt';
      case FilterOperator.gte:
        return 'gte';
      case FilterOperator.inList:
        return 'in';
      case FilterOperator.notInList:
        return 'nin';
      case FilterOperator.like:
        return 'like';
      case FilterOperator.ilike:
        return 'ilike';
      case FilterOperator.startsWith:
        return 'startsWith';
      case FilterOperator.endsWith:
        return 'endsWith';
      case FilterOperator.contains:
        return 'contains';
      case FilterOperator.between:
        return 'between';
      case FilterOperator.isNull:
        return 'isNull';
      case FilterOperator.isNotNull:
        return 'isNotNull';
    }
  }

  bool get requiresValue {
    switch (this) {
      case FilterOperator.isNull:
      case FilterOperator.isNotNull:
        return false;
      default:
        return true;
    }
  }

  bool get requiresMultipleValues {
    switch (this) {
      case FilterOperator.inList:
      case FilterOperator.notInList:
      case FilterOperator.between:
        return true;
      default:
        return false;
    }
  }
}

/// Order direction for sorting
@MappableEnum()
enum OrderDirection {
  @MappableValue('asc')
  asc,
  @MappableValue('desc')
  desc,
}

extension OrderDirectionExtension on OrderDirection {
  String get displayName {
    switch (this) {
      case OrderDirection.asc:
        return 'Ascending';
      case OrderDirection.desc:
        return 'Descending';
    }
  }
}

/// Column data type from metadata
@MappableEnum()
enum ColumnDataType {
  @MappableValue('string')
  string,
  @MappableValue('integer')
  integer,
  @MappableValue('number')
  number,
  @MappableValue('boolean')
  boolean,
  @MappableValue('date')
  date,
  @MappableValue('datetime')
  datetime,
  @MappableValue('enum')
  enumType,
  @MappableValue('uuid')
  uuid,
}

/// Single filter condition
@MappableClass()
class FilterCondition with FilterConditionMappable {
  const FilterCondition({
    required this.field,
    required this.op,
    this.value,
    this.values,
  });

  final String field;
  final FilterOperator op;
  final dynamic value;
  final List<dynamic>? values;

  factory FilterCondition.fromJson(Map<String, dynamic> json) =>
      FilterConditionMapper.fromMap(json);

  Map<String, dynamic> toApiJson() {
    return {
      'field': field,
      'op': op.apiValue,
      if (value != null) 'value': value,
      if (values != null) 'values': values,
    };
  }
}

/// Filter group with boolean logic (and/or/not)
@MappableClass()
class FilterGroup with FilterGroupMappable {
  const FilterGroup({this.and, @MappableField(key: 'or') this.or_, this.not});

  final List<FilterExpression>? and;
  @MappableField(key: 'or')
  final List<FilterExpression>? or_;
  final FilterExpression? not;

  factory FilterGroup.fromJson(Map<String, dynamic> json) =>
      FilterGroupMapper.fromMap(json);

  Map<String, dynamic> toApiJson() {
    return {
      if (and != null) 'and': and!.map((e) => e.toApiJson()).toList(),
      if (or_ != null) 'or': or_!.map((e) => e.toApiJson()).toList(),
      if (not != null) 'not': not!.toApiJson(),
    };
  }
}

/// Union type for filter expression (condition or group)
@MappableClass()
class FilterExpression with FilterExpressionMappable {
  const FilterExpression({this.condition, this.group})
    : assert(
        (condition != null && group == null) ||
            (condition == null && group != null),
        'Either condition or group must be set, but not both',
      );

  final FilterCondition? condition;
  final FilterGroup? group;

  factory FilterExpression.fromCondition(FilterCondition condition) =>
      FilterExpression(condition: condition);

  factory FilterExpression.fromGroup(FilterGroup group) =>
      FilterExpression(group: group);

  factory FilterExpression.fromJson(Map<String, dynamic> json) =>
      FilterExpressionMapper.fromMap(json);

  bool get isCondition => condition != null;
  bool get isGroup => group != null;

  Map<String, dynamic> toApiJson() {
    if (condition != null) {
      return condition!.toApiJson();
    }
    return group!.toApiJson();
  }
}

/// Order by specification
@MappableClass()
class OrderBy with OrderByMappable {
  const OrderBy({required this.field, required this.direction});

  final String field;
  final OrderDirection direction;

  factory OrderBy.fromJson(Map<String, dynamic> json) =>
      OrderByMapper.fromMap(json);

  Map<String, dynamic> toApiJson() {
    return {
      'field': field,
      'direction': direction == OrderDirection.asc ? 'asc' : 'desc',
    };
  }
}

/// Search query request for POST /api/search/query
@MappableClass()
class SearchQueryRequest with SearchQueryRequestMappable {
  const SearchQueryRequest({
    required this.resource,
    this.q,
    this.where,
    this.orderBy,
    this.select,
    this.pageNumber = 1,
    this.pageSize = 20,
    this.includeTotal = true,
  });

  final String resource;
  final String? q;
  final FilterExpression? where;
  final List<OrderBy>? orderBy;
  final List<String>? select;
  final int pageNumber;
  final int pageSize;
  final bool includeTotal;

  factory SearchQueryRequest.fromJson(Map<String, dynamic> json) =>
      SearchQueryRequestMapper.fromMap(json);

  Map<String, dynamic> toApiJson() {
    return {
      'resource': resource,
      if (q != null && q!.isNotEmpty) 'q': q,
      if (where != null) 'where': where!.toApiJson(),
      if (orderBy != null && orderBy!.isNotEmpty)
        'orderBy': orderBy!.map((e) => e.toApiJson()).toList(),
      if (select != null && select!.isNotEmpty) 'select': select,
      'pageNumber': pageNumber,
      'pageSize': pageSize,
      'includeTotal': includeTotal,
    };
  }
}

/// Column metadata from search/metadata endpoint
@MappableClass()
class SearchColumnMetadata with SearchColumnMetadataMappable {
  const SearchColumnMetadata({
    required this.name,
    required this.type,
    required this.nullable,
    required this.searchable,
    required this.filterable,
    required this.sortable,
    required this.operators,
    this.enumValues,
    this.label,
  });

  final String name;
  final ColumnDataType type;
  final bool nullable;
  final bool searchable;
  final bool filterable;
  final bool sortable;
  final List<String> operators;
  final List<String>? enumValues;
  final String? label;

  factory SearchColumnMetadata.fromJson(Map<String, dynamic> json) =>
      SearchColumnMetadataMapper.fromMap(json);

  String get displayName => label ?? _humanizeName(name);

  static String _humanizeName(String name) {
    return name
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : w)
        .join(' ');
  }

  List<FilterOperator> get availableOperators {
    return operators
        .map((op) {
          switch (op) {
            case 'eq':
              return FilterOperator.eq;
            case 'ne':
              return FilterOperator.ne;
            case 'lt':
              return FilterOperator.lt;
            case 'lte':
              return FilterOperator.lte;
            case 'gt':
              return FilterOperator.gt;
            case 'gte':
              return FilterOperator.gte;
            case 'in':
              return FilterOperator.inList;
            case 'nin':
              return FilterOperator.notInList;
            case 'like':
              return FilterOperator.like;
            case 'ilike':
              return FilterOperator.ilike;
            case 'startsWith':
              return FilterOperator.startsWith;
            case 'endsWith':
              return FilterOperator.endsWith;
            case 'contains':
              return FilterOperator.contains;
            case 'between':
              return FilterOperator.between;
            case 'isNull':
              return FilterOperator.isNull;
            case 'isNotNull':
              return FilterOperator.isNotNull;
            default:
              return null;
          }
        })
        .whereType<FilterOperator>()
        .toList();
  }
}

/// Resource metadata from search/metadata endpoint
@MappableClass()
class SearchResourceMetadata with SearchResourceMetadataMappable {
  const SearchResourceMetadata({
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
  final List<SearchColumnMetadata> columns;

  factory SearchResourceMetadata.fromJson(Map<String, dynamic> json) =>
      SearchResourceMetadataMapper.fromMap(json);

  SearchColumnMetadata? getColumn(String name) {
    try {
      return columns.firstWhere((c) => c.name == name);
    } catch (_) {
      return null;
    }
  }

  List<SearchColumnMetadata> get filterableColumns =>
      columns.where((c) => c.filterable).toList();

  List<SearchColumnMetadata> get searchableColumns =>
      columns.where((c) => c.searchable).toList();

  List<SearchColumnMetadata> get sortableColumns =>
      columns.where((c) => c.sortable).toList();
}

/// Response from GET /api/search/metadata
@MappableClass()
class SearchMetadataResponse with SearchMetadataResponseMappable {
  const SearchMetadataResponse({required this.status, required this.data});

  final String status;
  final SearchMetadataData data;

  factory SearchMetadataResponse.fromJson(Map<String, dynamic> json) =>
      SearchMetadataResponseMapper.fromMap(json);
}

@MappableClass()
class SearchMetadataData with SearchMetadataDataMappable {
  const SearchMetadataData({required this.resources});

  final List<SearchResourceMetadata> resources;

  factory SearchMetadataData.fromJson(Map<String, dynamic> json) =>
      SearchMetadataDataMapper.fromMap(json);

  SearchResourceMetadata? getResource(String name) {
    try {
      return resources.firstWhere((r) => r.name == name);
    } catch (_) {
      return null;
    }
  }
}

/// Search result item (generic map since columns vary by resource)
@MappableClass()
class SearchResultItem with SearchResultItemMappable {
  const SearchResultItem({required this.data});

  final Map<String, dynamic> data;

  factory SearchResultItem.fromJson(Map<String, dynamic> json) =>
      SearchResultItem(data: json);

  T? get<T>(String key) => data[key] as T?;

  String? getString(String key) => data[key]?.toString();
  int? getInt(String key) {
    final val = data[key];
    if (val is int) return val;
    if (val is String) return int.tryParse(val);
    return null;
  }

  double? getDouble(String key) {
    final val = data[key];
    if (val is double) return val;
    if (val is int) return val.toDouble();
    if (val is String) return double.tryParse(val);
    return null;
  }

  DateTime? getDateTime(String key) {
    final val = data[key];
    if (val is DateTime) return val;
    if (val is String) return DateTime.tryParse(val);
    return null;
  }

  bool? getBool(String key) {
    final val = data[key];
    if (val is bool) return val;
    if (val is String) return val.toLowerCase() == 'true';
    return null;
  }
}

/// Response from POST /api/search/query
@MappableClass()
class SearchQueryResponse with SearchQueryResponseMappable {
  const SearchQueryResponse({required this.status, required this.data});

  final String status;
  final SearchQueryData data;

  factory SearchQueryResponse.fromJson(Map<String, dynamic> json) =>
      SearchQueryResponseMapper.fromMap(json);
}

@MappableClass()
class SearchQueryData with SearchQueryDataMappable {
  const SearchQueryData({
    required this.items,
    required this.pageNumber,
    required this.pageSize,
    this.totalCount,
  });

  final List<SearchResultItem> items;
  final int pageNumber;
  final int pageSize;
  final int? totalCount;

  factory SearchQueryData.fromJson(Map<String, dynamic> json) =>
      SearchQueryDataMapper.fromMap(json);

  bool get hasMore {
    if (totalCount == null) return items.length >= pageSize;
    return pageNumber * pageSize < totalCount!;
  }

  int get totalPages {
    if (totalCount == null) return 0;
    return (totalCount! / pageSize).ceil();
  }
}

/// Response from GET /api/search (global search)
@MappableClass()
class GlobalSearchResponse with GlobalSearchResponseMappable {
  const GlobalSearchResponse({required this.status, required this.data});

  final String status;
  final GlobalSearchData data;

  factory GlobalSearchResponse.fromJson(Map<String, dynamic> json) =>
      GlobalSearchResponseMapper.fromMap(json);
}

@MappableClass()
class GlobalSearchData with GlobalSearchDataMappable {
  const GlobalSearchData({required this.results});

  final Map<String, GlobalSearchResourceResult> results;

  factory GlobalSearchData.fromJson(Map<String, dynamic> json) =>
      GlobalSearchDataMapper.fromMap(json);
}

@MappableClass()
class GlobalSearchResourceResult with GlobalSearchResourceResultMappable {
  const GlobalSearchResourceResult({
    required this.items,
    required this.totalCount,
  });

  final List<SearchResultItem> items;
  final int totalCount;

  factory GlobalSearchResourceResult.fromJson(Map<String, dynamic> json) =>
      GlobalSearchResourceResultMapper.fromMap(json);
}
