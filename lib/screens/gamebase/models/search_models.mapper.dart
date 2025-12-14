// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'search_models.dart';

class FilterOperatorMapper extends EnumMapper<FilterOperator> {
  FilterOperatorMapper._();

  static FilterOperatorMapper? _instance;
  static FilterOperatorMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = FilterOperatorMapper._());
    }
    return _instance!;
  }

  static FilterOperator fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  FilterOperator decode(dynamic value) {
    switch (value) {
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
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(FilterOperator self) {
    switch (self) {
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
}

extension FilterOperatorMapperExtension on FilterOperator {
  dynamic toValue() {
    FilterOperatorMapper.ensureInitialized();
    return MapperContainer.globals.toValue<FilterOperator>(this);
  }
}

class OrderDirectionMapper extends EnumMapper<OrderDirection> {
  OrderDirectionMapper._();

  static OrderDirectionMapper? _instance;
  static OrderDirectionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = OrderDirectionMapper._());
    }
    return _instance!;
  }

  static OrderDirection fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  OrderDirection decode(dynamic value) {
    switch (value) {
      case 'asc':
        return OrderDirection.asc;
      case 'desc':
        return OrderDirection.desc;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(OrderDirection self) {
    switch (self) {
      case OrderDirection.asc:
        return 'asc';
      case OrderDirection.desc:
        return 'desc';
    }
  }
}

extension OrderDirectionMapperExtension on OrderDirection {
  dynamic toValue() {
    OrderDirectionMapper.ensureInitialized();
    return MapperContainer.globals.toValue<OrderDirection>(this);
  }
}

class ColumnDataTypeMapper extends EnumMapper<ColumnDataType> {
  ColumnDataTypeMapper._();

  static ColumnDataTypeMapper? _instance;
  static ColumnDataTypeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = ColumnDataTypeMapper._());
    }
    return _instance!;
  }

  static ColumnDataType fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  ColumnDataType decode(dynamic value) {
    switch (value) {
      case 'string':
        return ColumnDataType.string;
      case 'integer':
        return ColumnDataType.integer;
      case 'number':
        return ColumnDataType.number;
      case 'boolean':
        return ColumnDataType.boolean;
      case 'date':
        return ColumnDataType.date;
      case 'datetime':
        return ColumnDataType.datetime;
      case 'enum':
        return ColumnDataType.enumType;
      case 'uuid':
        return ColumnDataType.uuid;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(ColumnDataType self) {
    switch (self) {
      case ColumnDataType.string:
        return 'string';
      case ColumnDataType.integer:
        return 'integer';
      case ColumnDataType.number:
        return 'number';
      case ColumnDataType.boolean:
        return 'boolean';
      case ColumnDataType.date:
        return 'date';
      case ColumnDataType.datetime:
        return 'datetime';
      case ColumnDataType.enumType:
        return 'enum';
      case ColumnDataType.uuid:
        return 'uuid';
    }
  }
}

extension ColumnDataTypeMapperExtension on ColumnDataType {
  dynamic toValue() {
    ColumnDataTypeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<ColumnDataType>(this);
  }
}

class FilterConditionMapper extends ClassMapperBase<FilterCondition> {
  FilterConditionMapper._();

  static FilterConditionMapper? _instance;
  static FilterConditionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = FilterConditionMapper._());
      FilterOperatorMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'FilterCondition';

  static String _$field(FilterCondition v) => v.field;
  static const Field<FilterCondition, String> _f$field = Field(
    'field',
    _$field,
  );
  static FilterOperator _$op(FilterCondition v) => v.op;
  static const Field<FilterCondition, FilterOperator> _f$op = Field('op', _$op);
  static dynamic _$value(FilterCondition v) => v.value;
  static const Field<FilterCondition, dynamic> _f$value = Field(
    'value',
    _$value,
    opt: true,
  );
  static List<dynamic>? _$values(FilterCondition v) => v.values;
  static const Field<FilterCondition, List<dynamic>> _f$values = Field(
    'values',
    _$values,
    opt: true,
  );

  @override
  final MappableFields<FilterCondition> fields = const {
    #field: _f$field,
    #op: _f$op,
    #value: _f$value,
    #values: _f$values,
  };

  static FilterCondition _instantiate(DecodingData data) {
    return FilterCondition(
      field: data.dec(_f$field),
      op: data.dec(_f$op),
      value: data.dec(_f$value),
      values: data.dec(_f$values),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static FilterCondition fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<FilterCondition>(map);
  }

  static FilterCondition fromJson(String json) {
    return ensureInitialized().decodeJson<FilterCondition>(json);
  }
}

mixin FilterConditionMappable {
  String toJson() {
    return FilterConditionMapper.ensureInitialized()
        .encodeJson<FilterCondition>(this as FilterCondition);
  }

  Map<String, dynamic> toMap() {
    return FilterConditionMapper.ensureInitialized().encodeMap<FilterCondition>(
      this as FilterCondition,
    );
  }

  FilterConditionCopyWith<FilterCondition, FilterCondition, FilterCondition>
  get copyWith =>
      _FilterConditionCopyWithImpl<FilterCondition, FilterCondition>(
        this as FilterCondition,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return FilterConditionMapper.ensureInitialized().stringifyValue(
      this as FilterCondition,
    );
  }

  @override
  bool operator ==(Object other) {
    return FilterConditionMapper.ensureInitialized().equalsValue(
      this as FilterCondition,
      other,
    );
  }

  @override
  int get hashCode {
    return FilterConditionMapper.ensureInitialized().hashValue(
      this as FilterCondition,
    );
  }
}

extension FilterConditionValueCopy<$R, $Out>
    on ObjectCopyWith<$R, FilterCondition, $Out> {
  FilterConditionCopyWith<$R, FilterCondition, $Out> get $asFilterCondition =>
      $base.as((v, t, t2) => _FilterConditionCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class FilterConditionCopyWith<$R, $In extends FilterCondition, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, dynamic, ObjectCopyWith<$R, dynamic, dynamic>>? get values;
  $R call({
    String? field,
    FilterOperator? op,
    dynamic value,
    List<dynamic>? values,
  });
  FilterConditionCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _FilterConditionCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, FilterCondition, $Out>
    implements FilterConditionCopyWith<$R, FilterCondition, $Out> {
  _FilterConditionCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<FilterCondition> $mapper =
      FilterConditionMapper.ensureInitialized();
  @override
  ListCopyWith<$R, dynamic, ObjectCopyWith<$R, dynamic, dynamic>>? get values =>
      $value.values != null
      ? ListCopyWith(
          $value.values!,
          (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(values: v),
        )
      : null;
  @override
  $R call({
    String? field,
    FilterOperator? op,
    Object? value = $none,
    Object? values = $none,
  }) => $apply(
    FieldCopyWithData({
      if (field != null) #field: field,
      if (op != null) #op: op,
      if (value != $none) #value: value,
      if (values != $none) #values: values,
    }),
  );
  @override
  FilterCondition $make(CopyWithData data) => FilterCondition(
    field: data.get(#field, or: $value.field),
    op: data.get(#op, or: $value.op),
    value: data.get(#value, or: $value.value),
    values: data.get(#values, or: $value.values),
  );

  @override
  FilterConditionCopyWith<$R2, FilterCondition, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _FilterConditionCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class FilterGroupMapper extends ClassMapperBase<FilterGroup> {
  FilterGroupMapper._();

  static FilterGroupMapper? _instance;
  static FilterGroupMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = FilterGroupMapper._());
      FilterExpressionMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'FilterGroup';

  static List<FilterExpression>? _$and(FilterGroup v) => v.and;
  static const Field<FilterGroup, List<FilterExpression>> _f$and = Field(
    'and',
    _$and,
    opt: true,
  );
  static List<FilterExpression>? _$or_(FilterGroup v) => v.or_;
  static const Field<FilterGroup, List<FilterExpression>> _f$or_ = Field(
    'or_',
    _$or_,
    key: r'or',
    opt: true,
  );
  static FilterExpression? _$not(FilterGroup v) => v.not;
  static const Field<FilterGroup, FilterExpression> _f$not = Field(
    'not',
    _$not,
    opt: true,
  );

  @override
  final MappableFields<FilterGroup> fields = const {
    #and: _f$and,
    #or_: _f$or_,
    #not: _f$not,
  };

  static FilterGroup _instantiate(DecodingData data) {
    return FilterGroup(
      and: data.dec(_f$and),
      or_: data.dec(_f$or_),
      not: data.dec(_f$not),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static FilterGroup fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<FilterGroup>(map);
  }

  static FilterGroup fromJson(String json) {
    return ensureInitialized().decodeJson<FilterGroup>(json);
  }
}

mixin FilterGroupMappable {
  String toJson() {
    return FilterGroupMapper.ensureInitialized().encodeJson<FilterGroup>(
      this as FilterGroup,
    );
  }

  Map<String, dynamic> toMap() {
    return FilterGroupMapper.ensureInitialized().encodeMap<FilterGroup>(
      this as FilterGroup,
    );
  }

  FilterGroupCopyWith<FilterGroup, FilterGroup, FilterGroup> get copyWith =>
      _FilterGroupCopyWithImpl<FilterGroup, FilterGroup>(
        this as FilterGroup,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return FilterGroupMapper.ensureInitialized().stringifyValue(
      this as FilterGroup,
    );
  }

  @override
  bool operator ==(Object other) {
    return FilterGroupMapper.ensureInitialized().equalsValue(
      this as FilterGroup,
      other,
    );
  }

  @override
  int get hashCode {
    return FilterGroupMapper.ensureInitialized().hashValue(this as FilterGroup);
  }
}

extension FilterGroupValueCopy<$R, $Out>
    on ObjectCopyWith<$R, FilterGroup, $Out> {
  FilterGroupCopyWith<$R, FilterGroup, $Out> get $asFilterGroup =>
      $base.as((v, t, t2) => _FilterGroupCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class FilterGroupCopyWith<$R, $In extends FilterGroup, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    FilterExpression,
    FilterExpressionCopyWith<$R, FilterExpression, FilterExpression>
  >?
  get and;
  ListCopyWith<
    $R,
    FilterExpression,
    FilterExpressionCopyWith<$R, FilterExpression, FilterExpression>
  >?
  get or_;
  FilterExpressionCopyWith<$R, FilterExpression, FilterExpression>? get not;
  $R call({
    List<FilterExpression>? and,
    List<FilterExpression>? or_,
    FilterExpression? not,
  });
  FilterGroupCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _FilterGroupCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, FilterGroup, $Out>
    implements FilterGroupCopyWith<$R, FilterGroup, $Out> {
  _FilterGroupCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<FilterGroup> $mapper =
      FilterGroupMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    FilterExpression,
    FilterExpressionCopyWith<$R, FilterExpression, FilterExpression>
  >?
  get and => $value.and != null
      ? ListCopyWith(
          $value.and!,
          (v, t) => v.copyWith.$chain(t),
          (v) => call(and: v),
        )
      : null;
  @override
  ListCopyWith<
    $R,
    FilterExpression,
    FilterExpressionCopyWith<$R, FilterExpression, FilterExpression>
  >?
  get or_ => $value.or_ != null
      ? ListCopyWith(
          $value.or_!,
          (v, t) => v.copyWith.$chain(t),
          (v) => call(or_: v),
        )
      : null;
  @override
  FilterExpressionCopyWith<$R, FilterExpression, FilterExpression>? get not =>
      $value.not?.copyWith.$chain((v) => call(not: v));
  @override
  $R call({Object? and = $none, Object? or_ = $none, Object? not = $none}) =>
      $apply(
        FieldCopyWithData({
          if (and != $none) #and: and,
          if (or_ != $none) #or_: or_,
          if (not != $none) #not: not,
        }),
      );
  @override
  FilterGroup $make(CopyWithData data) => FilterGroup(
    and: data.get(#and, or: $value.and),
    or_: data.get(#or_, or: $value.or_),
    not: data.get(#not, or: $value.not),
  );

  @override
  FilterGroupCopyWith<$R2, FilterGroup, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _FilterGroupCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class FilterExpressionMapper extends ClassMapperBase<FilterExpression> {
  FilterExpressionMapper._();

  static FilterExpressionMapper? _instance;
  static FilterExpressionMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = FilterExpressionMapper._());
      FilterConditionMapper.ensureInitialized();
      FilterGroupMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'FilterExpression';

  static FilterCondition? _$condition(FilterExpression v) => v.condition;
  static const Field<FilterExpression, FilterCondition> _f$condition = Field(
    'condition',
    _$condition,
    opt: true,
  );
  static FilterGroup? _$group(FilterExpression v) => v.group;
  static const Field<FilterExpression, FilterGroup> _f$group = Field(
    'group',
    _$group,
    opt: true,
  );

  @override
  final MappableFields<FilterExpression> fields = const {
    #condition: _f$condition,
    #group: _f$group,
  };

  static FilterExpression _instantiate(DecodingData data) {
    return FilterExpression(
      condition: data.dec(_f$condition),
      group: data.dec(_f$group),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static FilterExpression fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<FilterExpression>(map);
  }

  static FilterExpression fromJson(String json) {
    return ensureInitialized().decodeJson<FilterExpression>(json);
  }
}

mixin FilterExpressionMappable {
  String toJson() {
    return FilterExpressionMapper.ensureInitialized()
        .encodeJson<FilterExpression>(this as FilterExpression);
  }

  Map<String, dynamic> toMap() {
    return FilterExpressionMapper.ensureInitialized()
        .encodeMap<FilterExpression>(this as FilterExpression);
  }

  FilterExpressionCopyWith<FilterExpression, FilterExpression, FilterExpression>
  get copyWith =>
      _FilterExpressionCopyWithImpl<FilterExpression, FilterExpression>(
        this as FilterExpression,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return FilterExpressionMapper.ensureInitialized().stringifyValue(
      this as FilterExpression,
    );
  }

  @override
  bool operator ==(Object other) {
    return FilterExpressionMapper.ensureInitialized().equalsValue(
      this as FilterExpression,
      other,
    );
  }

  @override
  int get hashCode {
    return FilterExpressionMapper.ensureInitialized().hashValue(
      this as FilterExpression,
    );
  }
}

extension FilterExpressionValueCopy<$R, $Out>
    on ObjectCopyWith<$R, FilterExpression, $Out> {
  FilterExpressionCopyWith<$R, FilterExpression, $Out>
  get $asFilterExpression =>
      $base.as((v, t, t2) => _FilterExpressionCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class FilterExpressionCopyWith<$R, $In extends FilterExpression, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  FilterConditionCopyWith<$R, FilterCondition, FilterCondition>? get condition;
  FilterGroupCopyWith<$R, FilterGroup, FilterGroup>? get group;
  $R call({FilterCondition? condition, FilterGroup? group});
  FilterExpressionCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _FilterExpressionCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, FilterExpression, $Out>
    implements FilterExpressionCopyWith<$R, FilterExpression, $Out> {
  _FilterExpressionCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<FilterExpression> $mapper =
      FilterExpressionMapper.ensureInitialized();
  @override
  FilterConditionCopyWith<$R, FilterCondition, FilterCondition>?
  get condition => $value.condition?.copyWith.$chain((v) => call(condition: v));
  @override
  FilterGroupCopyWith<$R, FilterGroup, FilterGroup>? get group =>
      $value.group?.copyWith.$chain((v) => call(group: v));
  @override
  $R call({Object? condition = $none, Object? group = $none}) => $apply(
    FieldCopyWithData({
      if (condition != $none) #condition: condition,
      if (group != $none) #group: group,
    }),
  );
  @override
  FilterExpression $make(CopyWithData data) => FilterExpression(
    condition: data.get(#condition, or: $value.condition),
    group: data.get(#group, or: $value.group),
  );

  @override
  FilterExpressionCopyWith<$R2, FilterExpression, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _FilterExpressionCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class OrderByMapper extends ClassMapperBase<OrderBy> {
  OrderByMapper._();

  static OrderByMapper? _instance;
  static OrderByMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = OrderByMapper._());
      OrderDirectionMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'OrderBy';

  static String _$field(OrderBy v) => v.field;
  static const Field<OrderBy, String> _f$field = Field('field', _$field);
  static OrderDirection _$direction(OrderBy v) => v.direction;
  static const Field<OrderBy, OrderDirection> _f$direction = Field(
    'direction',
    _$direction,
  );

  @override
  final MappableFields<OrderBy> fields = const {
    #field: _f$field,
    #direction: _f$direction,
  };

  static OrderBy _instantiate(DecodingData data) {
    return OrderBy(
      field: data.dec(_f$field),
      direction: data.dec(_f$direction),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static OrderBy fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<OrderBy>(map);
  }

  static OrderBy fromJson(String json) {
    return ensureInitialized().decodeJson<OrderBy>(json);
  }
}

mixin OrderByMappable {
  String toJson() {
    return OrderByMapper.ensureInitialized().encodeJson<OrderBy>(
      this as OrderBy,
    );
  }

  Map<String, dynamic> toMap() {
    return OrderByMapper.ensureInitialized().encodeMap<OrderBy>(
      this as OrderBy,
    );
  }

  OrderByCopyWith<OrderBy, OrderBy, OrderBy> get copyWith =>
      _OrderByCopyWithImpl<OrderBy, OrderBy>(
        this as OrderBy,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return OrderByMapper.ensureInitialized().stringifyValue(this as OrderBy);
  }

  @override
  bool operator ==(Object other) {
    return OrderByMapper.ensureInitialized().equalsValue(
      this as OrderBy,
      other,
    );
  }

  @override
  int get hashCode {
    return OrderByMapper.ensureInitialized().hashValue(this as OrderBy);
  }
}

extension OrderByValueCopy<$R, $Out> on ObjectCopyWith<$R, OrderBy, $Out> {
  OrderByCopyWith<$R, OrderBy, $Out> get $asOrderBy =>
      $base.as((v, t, t2) => _OrderByCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class OrderByCopyWith<$R, $In extends OrderBy, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? field, OrderDirection? direction});
  OrderByCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _OrderByCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, OrderBy, $Out>
    implements OrderByCopyWith<$R, OrderBy, $Out> {
  _OrderByCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<OrderBy> $mapper =
      OrderByMapper.ensureInitialized();
  @override
  $R call({String? field, OrderDirection? direction}) => $apply(
    FieldCopyWithData({
      if (field != null) #field: field,
      if (direction != null) #direction: direction,
    }),
  );
  @override
  OrderBy $make(CopyWithData data) => OrderBy(
    field: data.get(#field, or: $value.field),
    direction: data.get(#direction, or: $value.direction),
  );

  @override
  OrderByCopyWith<$R2, OrderBy, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _OrderByCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class SearchQueryRequestMapper extends ClassMapperBase<SearchQueryRequest> {
  SearchQueryRequestMapper._();

  static SearchQueryRequestMapper? _instance;
  static SearchQueryRequestMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SearchQueryRequestMapper._());
      FilterExpressionMapper.ensureInitialized();
      OrderByMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'SearchQueryRequest';

  static String _$resource(SearchQueryRequest v) => v.resource;
  static const Field<SearchQueryRequest, String> _f$resource = Field(
    'resource',
    _$resource,
  );
  static String? _$q(SearchQueryRequest v) => v.q;
  static const Field<SearchQueryRequest, String> _f$q = Field(
    'q',
    _$q,
    opt: true,
  );
  static FilterExpression? _$where(SearchQueryRequest v) => v.where;
  static const Field<SearchQueryRequest, FilterExpression> _f$where = Field(
    'where',
    _$where,
    opt: true,
  );
  static List<OrderBy>? _$orderBy(SearchQueryRequest v) => v.orderBy;
  static const Field<SearchQueryRequest, List<OrderBy>> _f$orderBy = Field(
    'orderBy',
    _$orderBy,
    opt: true,
  );
  static List<String>? _$select(SearchQueryRequest v) => v.select;
  static const Field<SearchQueryRequest, List<String>> _f$select = Field(
    'select',
    _$select,
    opt: true,
  );
  static int _$pageNumber(SearchQueryRequest v) => v.pageNumber;
  static const Field<SearchQueryRequest, int> _f$pageNumber = Field(
    'pageNumber',
    _$pageNumber,
    opt: true,
    def: 1,
  );
  static int _$pageSize(SearchQueryRequest v) => v.pageSize;
  static const Field<SearchQueryRequest, int> _f$pageSize = Field(
    'pageSize',
    _$pageSize,
    opt: true,
    def: 20,
  );
  static bool _$includeTotal(SearchQueryRequest v) => v.includeTotal;
  static const Field<SearchQueryRequest, bool> _f$includeTotal = Field(
    'includeTotal',
    _$includeTotal,
    opt: true,
    def: true,
  );

  @override
  final MappableFields<SearchQueryRequest> fields = const {
    #resource: _f$resource,
    #q: _f$q,
    #where: _f$where,
    #orderBy: _f$orderBy,
    #select: _f$select,
    #pageNumber: _f$pageNumber,
    #pageSize: _f$pageSize,
    #includeTotal: _f$includeTotal,
  };

  static SearchQueryRequest _instantiate(DecodingData data) {
    return SearchQueryRequest(
      resource: data.dec(_f$resource),
      q: data.dec(_f$q),
      where: data.dec(_f$where),
      orderBy: data.dec(_f$orderBy),
      select: data.dec(_f$select),
      pageNumber: data.dec(_f$pageNumber),
      pageSize: data.dec(_f$pageSize),
      includeTotal: data.dec(_f$includeTotal),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static SearchQueryRequest fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<SearchQueryRequest>(map);
  }

  static SearchQueryRequest fromJson(String json) {
    return ensureInitialized().decodeJson<SearchQueryRequest>(json);
  }
}

mixin SearchQueryRequestMappable {
  String toJson() {
    return SearchQueryRequestMapper.ensureInitialized()
        .encodeJson<SearchQueryRequest>(this as SearchQueryRequest);
  }

  Map<String, dynamic> toMap() {
    return SearchQueryRequestMapper.ensureInitialized()
        .encodeMap<SearchQueryRequest>(this as SearchQueryRequest);
  }

  SearchQueryRequestCopyWith<
    SearchQueryRequest,
    SearchQueryRequest,
    SearchQueryRequest
  >
  get copyWith =>
      _SearchQueryRequestCopyWithImpl<SearchQueryRequest, SearchQueryRequest>(
        this as SearchQueryRequest,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return SearchQueryRequestMapper.ensureInitialized().stringifyValue(
      this as SearchQueryRequest,
    );
  }

  @override
  bool operator ==(Object other) {
    return SearchQueryRequestMapper.ensureInitialized().equalsValue(
      this as SearchQueryRequest,
      other,
    );
  }

  @override
  int get hashCode {
    return SearchQueryRequestMapper.ensureInitialized().hashValue(
      this as SearchQueryRequest,
    );
  }
}

extension SearchQueryRequestValueCopy<$R, $Out>
    on ObjectCopyWith<$R, SearchQueryRequest, $Out> {
  SearchQueryRequestCopyWith<$R, SearchQueryRequest, $Out>
  get $asSearchQueryRequest => $base.as(
    (v, t, t2) => _SearchQueryRequestCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class SearchQueryRequestCopyWith<
  $R,
  $In extends SearchQueryRequest,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  FilterExpressionCopyWith<$R, FilterExpression, FilterExpression>? get where;
  ListCopyWith<$R, OrderBy, OrderByCopyWith<$R, OrderBy, OrderBy>>? get orderBy;
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>? get select;
  $R call({
    String? resource,
    String? q,
    FilterExpression? where,
    List<OrderBy>? orderBy,
    List<String>? select,
    int? pageNumber,
    int? pageSize,
    bool? includeTotal,
  });
  SearchQueryRequestCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _SearchQueryRequestCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, SearchQueryRequest, $Out>
    implements SearchQueryRequestCopyWith<$R, SearchQueryRequest, $Out> {
  _SearchQueryRequestCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<SearchQueryRequest> $mapper =
      SearchQueryRequestMapper.ensureInitialized();
  @override
  FilterExpressionCopyWith<$R, FilterExpression, FilterExpression>? get where =>
      $value.where?.copyWith.$chain((v) => call(where: v));
  @override
  ListCopyWith<$R, OrderBy, OrderByCopyWith<$R, OrderBy, OrderBy>>?
  get orderBy => $value.orderBy != null
      ? ListCopyWith(
          $value.orderBy!,
          (v, t) => v.copyWith.$chain(t),
          (v) => call(orderBy: v),
        )
      : null;
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>? get select =>
      $value.select != null
      ? ListCopyWith(
          $value.select!,
          (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(select: v),
        )
      : null;
  @override
  $R call({
    String? resource,
    Object? q = $none,
    Object? where = $none,
    Object? orderBy = $none,
    Object? select = $none,
    int? pageNumber,
    int? pageSize,
    bool? includeTotal,
  }) => $apply(
    FieldCopyWithData({
      if (resource != null) #resource: resource,
      if (q != $none) #q: q,
      if (where != $none) #where: where,
      if (orderBy != $none) #orderBy: orderBy,
      if (select != $none) #select: select,
      if (pageNumber != null) #pageNumber: pageNumber,
      if (pageSize != null) #pageSize: pageSize,
      if (includeTotal != null) #includeTotal: includeTotal,
    }),
  );
  @override
  SearchQueryRequest $make(CopyWithData data) => SearchQueryRequest(
    resource: data.get(#resource, or: $value.resource),
    q: data.get(#q, or: $value.q),
    where: data.get(#where, or: $value.where),
    orderBy: data.get(#orderBy, or: $value.orderBy),
    select: data.get(#select, or: $value.select),
    pageNumber: data.get(#pageNumber, or: $value.pageNumber),
    pageSize: data.get(#pageSize, or: $value.pageSize),
    includeTotal: data.get(#includeTotal, or: $value.includeTotal),
  );

  @override
  SearchQueryRequestCopyWith<$R2, SearchQueryRequest, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _SearchQueryRequestCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class SearchColumnMetadataMapper extends ClassMapperBase<SearchColumnMetadata> {
  SearchColumnMetadataMapper._();

  static SearchColumnMetadataMapper? _instance;
  static SearchColumnMetadataMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SearchColumnMetadataMapper._());
      ColumnDataTypeMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'SearchColumnMetadata';

  static String _$name(SearchColumnMetadata v) => v.name;
  static const Field<SearchColumnMetadata, String> _f$name = Field(
    'name',
    _$name,
  );
  static ColumnDataType _$type(SearchColumnMetadata v) => v.type;
  static const Field<SearchColumnMetadata, ColumnDataType> _f$type = Field(
    'type',
    _$type,
  );
  static bool _$nullable(SearchColumnMetadata v) => v.nullable;
  static const Field<SearchColumnMetadata, bool> _f$nullable = Field(
    'nullable',
    _$nullable,
  );
  static bool _$searchable(SearchColumnMetadata v) => v.searchable;
  static const Field<SearchColumnMetadata, bool> _f$searchable = Field(
    'searchable',
    _$searchable,
  );
  static bool _$filterable(SearchColumnMetadata v) => v.filterable;
  static const Field<SearchColumnMetadata, bool> _f$filterable = Field(
    'filterable',
    _$filterable,
  );
  static bool _$sortable(SearchColumnMetadata v) => v.sortable;
  static const Field<SearchColumnMetadata, bool> _f$sortable = Field(
    'sortable',
    _$sortable,
  );
  static List<String> _$operators(SearchColumnMetadata v) => v.operators;
  static const Field<SearchColumnMetadata, List<String>> _f$operators = Field(
    'operators',
    _$operators,
  );
  static List<String>? _$enumValues(SearchColumnMetadata v) => v.enumValues;
  static const Field<SearchColumnMetadata, List<String>> _f$enumValues = Field(
    'enumValues',
    _$enumValues,
    opt: true,
  );
  static String? _$label(SearchColumnMetadata v) => v.label;
  static const Field<SearchColumnMetadata, String> _f$label = Field(
    'label',
    _$label,
    opt: true,
  );

  @override
  final MappableFields<SearchColumnMetadata> fields = const {
    #name: _f$name,
    #type: _f$type,
    #nullable: _f$nullable,
    #searchable: _f$searchable,
    #filterable: _f$filterable,
    #sortable: _f$sortable,
    #operators: _f$operators,
    #enumValues: _f$enumValues,
    #label: _f$label,
  };

  static SearchColumnMetadata _instantiate(DecodingData data) {
    return SearchColumnMetadata(
      name: data.dec(_f$name),
      type: data.dec(_f$type),
      nullable: data.dec(_f$nullable),
      searchable: data.dec(_f$searchable),
      filterable: data.dec(_f$filterable),
      sortable: data.dec(_f$sortable),
      operators: data.dec(_f$operators),
      enumValues: data.dec(_f$enumValues),
      label: data.dec(_f$label),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static SearchColumnMetadata fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<SearchColumnMetadata>(map);
  }

  static SearchColumnMetadata fromJson(String json) {
    return ensureInitialized().decodeJson<SearchColumnMetadata>(json);
  }
}

mixin SearchColumnMetadataMappable {
  String toJson() {
    return SearchColumnMetadataMapper.ensureInitialized()
        .encodeJson<SearchColumnMetadata>(this as SearchColumnMetadata);
  }

  Map<String, dynamic> toMap() {
    return SearchColumnMetadataMapper.ensureInitialized()
        .encodeMap<SearchColumnMetadata>(this as SearchColumnMetadata);
  }

  SearchColumnMetadataCopyWith<
    SearchColumnMetadata,
    SearchColumnMetadata,
    SearchColumnMetadata
  >
  get copyWith =>
      _SearchColumnMetadataCopyWithImpl<
        SearchColumnMetadata,
        SearchColumnMetadata
      >(this as SearchColumnMetadata, $identity, $identity);
  @override
  String toString() {
    return SearchColumnMetadataMapper.ensureInitialized().stringifyValue(
      this as SearchColumnMetadata,
    );
  }

  @override
  bool operator ==(Object other) {
    return SearchColumnMetadataMapper.ensureInitialized().equalsValue(
      this as SearchColumnMetadata,
      other,
    );
  }

  @override
  int get hashCode {
    return SearchColumnMetadataMapper.ensureInitialized().hashValue(
      this as SearchColumnMetadata,
    );
  }
}

extension SearchColumnMetadataValueCopy<$R, $Out>
    on ObjectCopyWith<$R, SearchColumnMetadata, $Out> {
  SearchColumnMetadataCopyWith<$R, SearchColumnMetadata, $Out>
  get $asSearchColumnMetadata => $base.as(
    (v, t, t2) => _SearchColumnMetadataCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class SearchColumnMetadataCopyWith<
  $R,
  $In extends SearchColumnMetadata,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get operators;
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>? get enumValues;
  $R call({
    String? name,
    ColumnDataType? type,
    bool? nullable,
    bool? searchable,
    bool? filterable,
    bool? sortable,
    List<String>? operators,
    List<String>? enumValues,
    String? label,
  });
  SearchColumnMetadataCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _SearchColumnMetadataCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, SearchColumnMetadata, $Out>
    implements SearchColumnMetadataCopyWith<$R, SearchColumnMetadata, $Out> {
  _SearchColumnMetadataCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<SearchColumnMetadata> $mapper =
      SearchColumnMetadataMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get operators =>
      ListCopyWith(
        $value.operators,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(operators: v),
      );
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>?
  get enumValues => $value.enumValues != null
      ? ListCopyWith(
          $value.enumValues!,
          (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(enumValues: v),
        )
      : null;
  @override
  $R call({
    String? name,
    ColumnDataType? type,
    bool? nullable,
    bool? searchable,
    bool? filterable,
    bool? sortable,
    List<String>? operators,
    Object? enumValues = $none,
    Object? label = $none,
  }) => $apply(
    FieldCopyWithData({
      if (name != null) #name: name,
      if (type != null) #type: type,
      if (nullable != null) #nullable: nullable,
      if (searchable != null) #searchable: searchable,
      if (filterable != null) #filterable: filterable,
      if (sortable != null) #sortable: sortable,
      if (operators != null) #operators: operators,
      if (enumValues != $none) #enumValues: enumValues,
      if (label != $none) #label: label,
    }),
  );
  @override
  SearchColumnMetadata $make(CopyWithData data) => SearchColumnMetadata(
    name: data.get(#name, or: $value.name),
    type: data.get(#type, or: $value.type),
    nullable: data.get(#nullable, or: $value.nullable),
    searchable: data.get(#searchable, or: $value.searchable),
    filterable: data.get(#filterable, or: $value.filterable),
    sortable: data.get(#sortable, or: $value.sortable),
    operators: data.get(#operators, or: $value.operators),
    enumValues: data.get(#enumValues, or: $value.enumValues),
    label: data.get(#label, or: $value.label),
  );

  @override
  SearchColumnMetadataCopyWith<$R2, SearchColumnMetadata, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _SearchColumnMetadataCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class SearchResourceMetadataMapper
    extends ClassMapperBase<SearchResourceMetadata> {
  SearchResourceMetadataMapper._();

  static SearchResourceMetadataMapper? _instance;
  static SearchResourceMetadataMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SearchResourceMetadataMapper._());
      SearchColumnMetadataMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'SearchResourceMetadata';

  static String _$name(SearchResourceMetadata v) => v.name;
  static const Field<SearchResourceMetadata, String> _f$name = Field(
    'name',
    _$name,
  );
  static String _$label(SearchResourceMetadata v) => v.label;
  static const Field<SearchResourceMetadata, String> _f$label = Field(
    'label',
    _$label,
  );
  static String _$primaryKey(SearchResourceMetadata v) => v.primaryKey;
  static const Field<SearchResourceMetadata, String> _f$primaryKey = Field(
    'primaryKey',
    _$primaryKey,
  );
  static List<String> _$defaultSearchColumns(SearchResourceMetadata v) =>
      v.defaultSearchColumns;
  static const Field<SearchResourceMetadata, List<String>>
  _f$defaultSearchColumns = Field(
    'defaultSearchColumns',
    _$defaultSearchColumns,
  );
  static List<SearchColumnMetadata> _$columns(SearchResourceMetadata v) =>
      v.columns;
  static const Field<SearchResourceMetadata, List<SearchColumnMetadata>>
  _f$columns = Field('columns', _$columns);

  @override
  final MappableFields<SearchResourceMetadata> fields = const {
    #name: _f$name,
    #label: _f$label,
    #primaryKey: _f$primaryKey,
    #defaultSearchColumns: _f$defaultSearchColumns,
    #columns: _f$columns,
  };

  static SearchResourceMetadata _instantiate(DecodingData data) {
    return SearchResourceMetadata(
      name: data.dec(_f$name),
      label: data.dec(_f$label),
      primaryKey: data.dec(_f$primaryKey),
      defaultSearchColumns: data.dec(_f$defaultSearchColumns),
      columns: data.dec(_f$columns),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static SearchResourceMetadata fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<SearchResourceMetadata>(map);
  }

  static SearchResourceMetadata fromJson(String json) {
    return ensureInitialized().decodeJson<SearchResourceMetadata>(json);
  }
}

mixin SearchResourceMetadataMappable {
  String toJson() {
    return SearchResourceMetadataMapper.ensureInitialized()
        .encodeJson<SearchResourceMetadata>(this as SearchResourceMetadata);
  }

  Map<String, dynamic> toMap() {
    return SearchResourceMetadataMapper.ensureInitialized()
        .encodeMap<SearchResourceMetadata>(this as SearchResourceMetadata);
  }

  SearchResourceMetadataCopyWith<
    SearchResourceMetadata,
    SearchResourceMetadata,
    SearchResourceMetadata
  >
  get copyWith =>
      _SearchResourceMetadataCopyWithImpl<
        SearchResourceMetadata,
        SearchResourceMetadata
      >(this as SearchResourceMetadata, $identity, $identity);
  @override
  String toString() {
    return SearchResourceMetadataMapper.ensureInitialized().stringifyValue(
      this as SearchResourceMetadata,
    );
  }

  @override
  bool operator ==(Object other) {
    return SearchResourceMetadataMapper.ensureInitialized().equalsValue(
      this as SearchResourceMetadata,
      other,
    );
  }

  @override
  int get hashCode {
    return SearchResourceMetadataMapper.ensureInitialized().hashValue(
      this as SearchResourceMetadata,
    );
  }
}

extension SearchResourceMetadataValueCopy<$R, $Out>
    on ObjectCopyWith<$R, SearchResourceMetadata, $Out> {
  SearchResourceMetadataCopyWith<$R, SearchResourceMetadata, $Out>
  get $asSearchResourceMetadata => $base.as(
    (v, t, t2) => _SearchResourceMetadataCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class SearchResourceMetadataCopyWith<
  $R,
  $In extends SearchResourceMetadata,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>
  get defaultSearchColumns;
  ListCopyWith<
    $R,
    SearchColumnMetadata,
    SearchColumnMetadataCopyWith<$R, SearchColumnMetadata, SearchColumnMetadata>
  >
  get columns;
  $R call({
    String? name,
    String? label,
    String? primaryKey,
    List<String>? defaultSearchColumns,
    List<SearchColumnMetadata>? columns,
  });
  SearchResourceMetadataCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _SearchResourceMetadataCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, SearchResourceMetadata, $Out>
    implements
        SearchResourceMetadataCopyWith<$R, SearchResourceMetadata, $Out> {
  _SearchResourceMetadataCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<SearchResourceMetadata> $mapper =
      SearchResourceMetadataMapper.ensureInitialized();
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>>
  get defaultSearchColumns => ListCopyWith(
    $value.defaultSearchColumns,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(defaultSearchColumns: v),
  );
  @override
  ListCopyWith<
    $R,
    SearchColumnMetadata,
    SearchColumnMetadataCopyWith<$R, SearchColumnMetadata, SearchColumnMetadata>
  >
  get columns => ListCopyWith(
    $value.columns,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(columns: v),
  );
  @override
  $R call({
    String? name,
    String? label,
    String? primaryKey,
    List<String>? defaultSearchColumns,
    List<SearchColumnMetadata>? columns,
  }) => $apply(
    FieldCopyWithData({
      if (name != null) #name: name,
      if (label != null) #label: label,
      if (primaryKey != null) #primaryKey: primaryKey,
      if (defaultSearchColumns != null)
        #defaultSearchColumns: defaultSearchColumns,
      if (columns != null) #columns: columns,
    }),
  );
  @override
  SearchResourceMetadata $make(CopyWithData data) => SearchResourceMetadata(
    name: data.get(#name, or: $value.name),
    label: data.get(#label, or: $value.label),
    primaryKey: data.get(#primaryKey, or: $value.primaryKey),
    defaultSearchColumns: data.get(
      #defaultSearchColumns,
      or: $value.defaultSearchColumns,
    ),
    columns: data.get(#columns, or: $value.columns),
  );

  @override
  SearchResourceMetadataCopyWith<$R2, SearchResourceMetadata, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _SearchResourceMetadataCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class SearchMetadataResponseMapper
    extends ClassMapperBase<SearchMetadataResponse> {
  SearchMetadataResponseMapper._();

  static SearchMetadataResponseMapper? _instance;
  static SearchMetadataResponseMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SearchMetadataResponseMapper._());
      SearchMetadataDataMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'SearchMetadataResponse';

  static String _$status(SearchMetadataResponse v) => v.status;
  static const Field<SearchMetadataResponse, String> _f$status = Field(
    'status',
    _$status,
  );
  static SearchMetadataData _$data(SearchMetadataResponse v) => v.data;
  static const Field<SearchMetadataResponse, SearchMetadataData> _f$data =
      Field('data', _$data);

  @override
  final MappableFields<SearchMetadataResponse> fields = const {
    #status: _f$status,
    #data: _f$data,
  };

  static SearchMetadataResponse _instantiate(DecodingData data) {
    return SearchMetadataResponse(
      status: data.dec(_f$status),
      data: data.dec(_f$data),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static SearchMetadataResponse fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<SearchMetadataResponse>(map);
  }

  static SearchMetadataResponse fromJson(String json) {
    return ensureInitialized().decodeJson<SearchMetadataResponse>(json);
  }
}

mixin SearchMetadataResponseMappable {
  String toJson() {
    return SearchMetadataResponseMapper.ensureInitialized()
        .encodeJson<SearchMetadataResponse>(this as SearchMetadataResponse);
  }

  Map<String, dynamic> toMap() {
    return SearchMetadataResponseMapper.ensureInitialized()
        .encodeMap<SearchMetadataResponse>(this as SearchMetadataResponse);
  }

  SearchMetadataResponseCopyWith<
    SearchMetadataResponse,
    SearchMetadataResponse,
    SearchMetadataResponse
  >
  get copyWith =>
      _SearchMetadataResponseCopyWithImpl<
        SearchMetadataResponse,
        SearchMetadataResponse
      >(this as SearchMetadataResponse, $identity, $identity);
  @override
  String toString() {
    return SearchMetadataResponseMapper.ensureInitialized().stringifyValue(
      this as SearchMetadataResponse,
    );
  }

  @override
  bool operator ==(Object other) {
    return SearchMetadataResponseMapper.ensureInitialized().equalsValue(
      this as SearchMetadataResponse,
      other,
    );
  }

  @override
  int get hashCode {
    return SearchMetadataResponseMapper.ensureInitialized().hashValue(
      this as SearchMetadataResponse,
    );
  }
}

extension SearchMetadataResponseValueCopy<$R, $Out>
    on ObjectCopyWith<$R, SearchMetadataResponse, $Out> {
  SearchMetadataResponseCopyWith<$R, SearchMetadataResponse, $Out>
  get $asSearchMetadataResponse => $base.as(
    (v, t, t2) => _SearchMetadataResponseCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class SearchMetadataResponseCopyWith<
  $R,
  $In extends SearchMetadataResponse,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  SearchMetadataDataCopyWith<$R, SearchMetadataData, SearchMetadataData>
  get data;
  $R call({String? status, SearchMetadataData? data});
  SearchMetadataResponseCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _SearchMetadataResponseCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, SearchMetadataResponse, $Out>
    implements
        SearchMetadataResponseCopyWith<$R, SearchMetadataResponse, $Out> {
  _SearchMetadataResponseCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<SearchMetadataResponse> $mapper =
      SearchMetadataResponseMapper.ensureInitialized();
  @override
  SearchMetadataDataCopyWith<$R, SearchMetadataData, SearchMetadataData>
  get data => $value.data.copyWith.$chain((v) => call(data: v));
  @override
  $R call({String? status, SearchMetadataData? data}) => $apply(
    FieldCopyWithData({
      if (status != null) #status: status,
      if (data != null) #data: data,
    }),
  );
  @override
  SearchMetadataResponse $make(CopyWithData data) => SearchMetadataResponse(
    status: data.get(#status, or: $value.status),
    data: data.get(#data, or: $value.data),
  );

  @override
  SearchMetadataResponseCopyWith<$R2, SearchMetadataResponse, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _SearchMetadataResponseCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class SearchMetadataDataMapper extends ClassMapperBase<SearchMetadataData> {
  SearchMetadataDataMapper._();

  static SearchMetadataDataMapper? _instance;
  static SearchMetadataDataMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SearchMetadataDataMapper._());
      SearchResourceMetadataMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'SearchMetadataData';

  static List<SearchResourceMetadata> _$resources(SearchMetadataData v) =>
      v.resources;
  static const Field<SearchMetadataData, List<SearchResourceMetadata>>
  _f$resources = Field('resources', _$resources);

  @override
  final MappableFields<SearchMetadataData> fields = const {
    #resources: _f$resources,
  };

  static SearchMetadataData _instantiate(DecodingData data) {
    return SearchMetadataData(resources: data.dec(_f$resources));
  }

  @override
  final Function instantiate = _instantiate;

  static SearchMetadataData fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<SearchMetadataData>(map);
  }

  static SearchMetadataData fromJson(String json) {
    return ensureInitialized().decodeJson<SearchMetadataData>(json);
  }
}

mixin SearchMetadataDataMappable {
  String toJson() {
    return SearchMetadataDataMapper.ensureInitialized()
        .encodeJson<SearchMetadataData>(this as SearchMetadataData);
  }

  Map<String, dynamic> toMap() {
    return SearchMetadataDataMapper.ensureInitialized()
        .encodeMap<SearchMetadataData>(this as SearchMetadataData);
  }

  SearchMetadataDataCopyWith<
    SearchMetadataData,
    SearchMetadataData,
    SearchMetadataData
  >
  get copyWith =>
      _SearchMetadataDataCopyWithImpl<SearchMetadataData, SearchMetadataData>(
        this as SearchMetadataData,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return SearchMetadataDataMapper.ensureInitialized().stringifyValue(
      this as SearchMetadataData,
    );
  }

  @override
  bool operator ==(Object other) {
    return SearchMetadataDataMapper.ensureInitialized().equalsValue(
      this as SearchMetadataData,
      other,
    );
  }

  @override
  int get hashCode {
    return SearchMetadataDataMapper.ensureInitialized().hashValue(
      this as SearchMetadataData,
    );
  }
}

extension SearchMetadataDataValueCopy<$R, $Out>
    on ObjectCopyWith<$R, SearchMetadataData, $Out> {
  SearchMetadataDataCopyWith<$R, SearchMetadataData, $Out>
  get $asSearchMetadataData => $base.as(
    (v, t, t2) => _SearchMetadataDataCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class SearchMetadataDataCopyWith<
  $R,
  $In extends SearchMetadataData,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    SearchResourceMetadata,
    SearchResourceMetadataCopyWith<
      $R,
      SearchResourceMetadata,
      SearchResourceMetadata
    >
  >
  get resources;
  $R call({List<SearchResourceMetadata>? resources});
  SearchMetadataDataCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _SearchMetadataDataCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, SearchMetadataData, $Out>
    implements SearchMetadataDataCopyWith<$R, SearchMetadataData, $Out> {
  _SearchMetadataDataCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<SearchMetadataData> $mapper =
      SearchMetadataDataMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    SearchResourceMetadata,
    SearchResourceMetadataCopyWith<
      $R,
      SearchResourceMetadata,
      SearchResourceMetadata
    >
  >
  get resources => ListCopyWith(
    $value.resources,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(resources: v),
  );
  @override
  $R call({List<SearchResourceMetadata>? resources}) =>
      $apply(FieldCopyWithData({if (resources != null) #resources: resources}));
  @override
  SearchMetadataData $make(CopyWithData data) =>
      SearchMetadataData(resources: data.get(#resources, or: $value.resources));

  @override
  SearchMetadataDataCopyWith<$R2, SearchMetadataData, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _SearchMetadataDataCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class SearchResultItemMapper extends ClassMapperBase<SearchResultItem> {
  SearchResultItemMapper._();

  static SearchResultItemMapper? _instance;
  static SearchResultItemMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SearchResultItemMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'SearchResultItem';

  static Map<String, dynamic> _$data(SearchResultItem v) => v.data;
  static const Field<SearchResultItem, Map<String, dynamic>> _f$data = Field(
    'data',
    _$data,
  );

  @override
  final MappableFields<SearchResultItem> fields = const {#data: _f$data};

  static SearchResultItem _instantiate(DecodingData data) {
    return SearchResultItem(data: data.dec(_f$data));
  }

  @override
  final Function instantiate = _instantiate;

  static SearchResultItem fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<SearchResultItem>(map);
  }

  static SearchResultItem fromJson(String json) {
    return ensureInitialized().decodeJson<SearchResultItem>(json);
  }
}

mixin SearchResultItemMappable {
  String toJson() {
    return SearchResultItemMapper.ensureInitialized()
        .encodeJson<SearchResultItem>(this as SearchResultItem);
  }

  Map<String, dynamic> toMap() {
    return SearchResultItemMapper.ensureInitialized()
        .encodeMap<SearchResultItem>(this as SearchResultItem);
  }

  SearchResultItemCopyWith<SearchResultItem, SearchResultItem, SearchResultItem>
  get copyWith =>
      _SearchResultItemCopyWithImpl<SearchResultItem, SearchResultItem>(
        this as SearchResultItem,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return SearchResultItemMapper.ensureInitialized().stringifyValue(
      this as SearchResultItem,
    );
  }

  @override
  bool operator ==(Object other) {
    return SearchResultItemMapper.ensureInitialized().equalsValue(
      this as SearchResultItem,
      other,
    );
  }

  @override
  int get hashCode {
    return SearchResultItemMapper.ensureInitialized().hashValue(
      this as SearchResultItem,
    );
  }
}

extension SearchResultItemValueCopy<$R, $Out>
    on ObjectCopyWith<$R, SearchResultItem, $Out> {
  SearchResultItemCopyWith<$R, SearchResultItem, $Out>
  get $asSearchResultItem =>
      $base.as((v, t, t2) => _SearchResultItemCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class SearchResultItemCopyWith<$R, $In extends SearchResultItem, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, dynamic, ObjectCopyWith<$R, dynamic, dynamic>>
  get data;
  $R call({Map<String, dynamic>? data});
  SearchResultItemCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _SearchResultItemCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, SearchResultItem, $Out>
    implements SearchResultItemCopyWith<$R, SearchResultItem, $Out> {
  _SearchResultItemCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<SearchResultItem> $mapper =
      SearchResultItemMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, dynamic, ObjectCopyWith<$R, dynamic, dynamic>>
  get data => MapCopyWith(
    $value.data,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(data: v),
  );
  @override
  $R call({Map<String, dynamic>? data}) =>
      $apply(FieldCopyWithData({if (data != null) #data: data}));
  @override
  SearchResultItem $make(CopyWithData data) =>
      SearchResultItem(data: data.get(#data, or: $value.data));

  @override
  SearchResultItemCopyWith<$R2, SearchResultItem, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _SearchResultItemCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class SearchQueryResponseMapper extends ClassMapperBase<SearchQueryResponse> {
  SearchQueryResponseMapper._();

  static SearchQueryResponseMapper? _instance;
  static SearchQueryResponseMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SearchQueryResponseMapper._());
      SearchQueryDataMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'SearchQueryResponse';

  static String _$status(SearchQueryResponse v) => v.status;
  static const Field<SearchQueryResponse, String> _f$status = Field(
    'status',
    _$status,
  );
  static SearchQueryData _$data(SearchQueryResponse v) => v.data;
  static const Field<SearchQueryResponse, SearchQueryData> _f$data = Field(
    'data',
    _$data,
  );

  @override
  final MappableFields<SearchQueryResponse> fields = const {
    #status: _f$status,
    #data: _f$data,
  };

  static SearchQueryResponse _instantiate(DecodingData data) {
    return SearchQueryResponse(
      status: data.dec(_f$status),
      data: data.dec(_f$data),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static SearchQueryResponse fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<SearchQueryResponse>(map);
  }

  static SearchQueryResponse fromJson(String json) {
    return ensureInitialized().decodeJson<SearchQueryResponse>(json);
  }
}

mixin SearchQueryResponseMappable {
  String toJson() {
    return SearchQueryResponseMapper.ensureInitialized()
        .encodeJson<SearchQueryResponse>(this as SearchQueryResponse);
  }

  Map<String, dynamic> toMap() {
    return SearchQueryResponseMapper.ensureInitialized()
        .encodeMap<SearchQueryResponse>(this as SearchQueryResponse);
  }

  SearchQueryResponseCopyWith<
    SearchQueryResponse,
    SearchQueryResponse,
    SearchQueryResponse
  >
  get copyWith =>
      _SearchQueryResponseCopyWithImpl<
        SearchQueryResponse,
        SearchQueryResponse
      >(this as SearchQueryResponse, $identity, $identity);
  @override
  String toString() {
    return SearchQueryResponseMapper.ensureInitialized().stringifyValue(
      this as SearchQueryResponse,
    );
  }

  @override
  bool operator ==(Object other) {
    return SearchQueryResponseMapper.ensureInitialized().equalsValue(
      this as SearchQueryResponse,
      other,
    );
  }

  @override
  int get hashCode {
    return SearchQueryResponseMapper.ensureInitialized().hashValue(
      this as SearchQueryResponse,
    );
  }
}

extension SearchQueryResponseValueCopy<$R, $Out>
    on ObjectCopyWith<$R, SearchQueryResponse, $Out> {
  SearchQueryResponseCopyWith<$R, SearchQueryResponse, $Out>
  get $asSearchQueryResponse => $base.as(
    (v, t, t2) => _SearchQueryResponseCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class SearchQueryResponseCopyWith<
  $R,
  $In extends SearchQueryResponse,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  SearchQueryDataCopyWith<$R, SearchQueryData, SearchQueryData> get data;
  $R call({String? status, SearchQueryData? data});
  SearchQueryResponseCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _SearchQueryResponseCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, SearchQueryResponse, $Out>
    implements SearchQueryResponseCopyWith<$R, SearchQueryResponse, $Out> {
  _SearchQueryResponseCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<SearchQueryResponse> $mapper =
      SearchQueryResponseMapper.ensureInitialized();
  @override
  SearchQueryDataCopyWith<$R, SearchQueryData, SearchQueryData> get data =>
      $value.data.copyWith.$chain((v) => call(data: v));
  @override
  $R call({String? status, SearchQueryData? data}) => $apply(
    FieldCopyWithData({
      if (status != null) #status: status,
      if (data != null) #data: data,
    }),
  );
  @override
  SearchQueryResponse $make(CopyWithData data) => SearchQueryResponse(
    status: data.get(#status, or: $value.status),
    data: data.get(#data, or: $value.data),
  );

  @override
  SearchQueryResponseCopyWith<$R2, SearchQueryResponse, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _SearchQueryResponseCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class SearchQueryDataMapper extends ClassMapperBase<SearchQueryData> {
  SearchQueryDataMapper._();

  static SearchQueryDataMapper? _instance;
  static SearchQueryDataMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SearchQueryDataMapper._());
      SearchResultItemMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'SearchQueryData';

  static List<SearchResultItem> _$items(SearchQueryData v) => v.items;
  static const Field<SearchQueryData, List<SearchResultItem>> _f$items = Field(
    'items',
    _$items,
  );
  static int _$pageNumber(SearchQueryData v) => v.pageNumber;
  static const Field<SearchQueryData, int> _f$pageNumber = Field(
    'pageNumber',
    _$pageNumber,
  );
  static int _$pageSize(SearchQueryData v) => v.pageSize;
  static const Field<SearchQueryData, int> _f$pageSize = Field(
    'pageSize',
    _$pageSize,
  );
  static int? _$totalCount(SearchQueryData v) => v.totalCount;
  static const Field<SearchQueryData, int> _f$totalCount = Field(
    'totalCount',
    _$totalCount,
    opt: true,
  );

  @override
  final MappableFields<SearchQueryData> fields = const {
    #items: _f$items,
    #pageNumber: _f$pageNumber,
    #pageSize: _f$pageSize,
    #totalCount: _f$totalCount,
  };

  static SearchQueryData _instantiate(DecodingData data) {
    return SearchQueryData(
      items: data.dec(_f$items),
      pageNumber: data.dec(_f$pageNumber),
      pageSize: data.dec(_f$pageSize),
      totalCount: data.dec(_f$totalCount),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static SearchQueryData fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<SearchQueryData>(map);
  }

  static SearchQueryData fromJson(String json) {
    return ensureInitialized().decodeJson<SearchQueryData>(json);
  }
}

mixin SearchQueryDataMappable {
  String toJson() {
    return SearchQueryDataMapper.ensureInitialized()
        .encodeJson<SearchQueryData>(this as SearchQueryData);
  }

  Map<String, dynamic> toMap() {
    return SearchQueryDataMapper.ensureInitialized().encodeMap<SearchQueryData>(
      this as SearchQueryData,
    );
  }

  SearchQueryDataCopyWith<SearchQueryData, SearchQueryData, SearchQueryData>
  get copyWith =>
      _SearchQueryDataCopyWithImpl<SearchQueryData, SearchQueryData>(
        this as SearchQueryData,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return SearchQueryDataMapper.ensureInitialized().stringifyValue(
      this as SearchQueryData,
    );
  }

  @override
  bool operator ==(Object other) {
    return SearchQueryDataMapper.ensureInitialized().equalsValue(
      this as SearchQueryData,
      other,
    );
  }

  @override
  int get hashCode {
    return SearchQueryDataMapper.ensureInitialized().hashValue(
      this as SearchQueryData,
    );
  }
}

extension SearchQueryDataValueCopy<$R, $Out>
    on ObjectCopyWith<$R, SearchQueryData, $Out> {
  SearchQueryDataCopyWith<$R, SearchQueryData, $Out> get $asSearchQueryData =>
      $base.as((v, t, t2) => _SearchQueryDataCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class SearchQueryDataCopyWith<$R, $In extends SearchQueryData, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    SearchResultItem,
    SearchResultItemCopyWith<$R, SearchResultItem, SearchResultItem>
  >
  get items;
  $R call({
    List<SearchResultItem>? items,
    int? pageNumber,
    int? pageSize,
    int? totalCount,
  });
  SearchQueryDataCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _SearchQueryDataCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, SearchQueryData, $Out>
    implements SearchQueryDataCopyWith<$R, SearchQueryData, $Out> {
  _SearchQueryDataCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<SearchQueryData> $mapper =
      SearchQueryDataMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    SearchResultItem,
    SearchResultItemCopyWith<$R, SearchResultItem, SearchResultItem>
  >
  get items => ListCopyWith(
    $value.items,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(items: v),
  );
  @override
  $R call({
    List<SearchResultItem>? items,
    int? pageNumber,
    int? pageSize,
    Object? totalCount = $none,
  }) => $apply(
    FieldCopyWithData({
      if (items != null) #items: items,
      if (pageNumber != null) #pageNumber: pageNumber,
      if (pageSize != null) #pageSize: pageSize,
      if (totalCount != $none) #totalCount: totalCount,
    }),
  );
  @override
  SearchQueryData $make(CopyWithData data) => SearchQueryData(
    items: data.get(#items, or: $value.items),
    pageNumber: data.get(#pageNumber, or: $value.pageNumber),
    pageSize: data.get(#pageSize, or: $value.pageSize),
    totalCount: data.get(#totalCount, or: $value.totalCount),
  );

  @override
  SearchQueryDataCopyWith<$R2, SearchQueryData, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _SearchQueryDataCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class GlobalSearchResponseMapper extends ClassMapperBase<GlobalSearchResponse> {
  GlobalSearchResponseMapper._();

  static GlobalSearchResponseMapper? _instance;
  static GlobalSearchResponseMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = GlobalSearchResponseMapper._());
      GlobalSearchDataMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'GlobalSearchResponse';

  static String _$status(GlobalSearchResponse v) => v.status;
  static const Field<GlobalSearchResponse, String> _f$status = Field(
    'status',
    _$status,
  );
  static GlobalSearchData _$data(GlobalSearchResponse v) => v.data;
  static const Field<GlobalSearchResponse, GlobalSearchData> _f$data = Field(
    'data',
    _$data,
  );

  @override
  final MappableFields<GlobalSearchResponse> fields = const {
    #status: _f$status,
    #data: _f$data,
  };

  static GlobalSearchResponse _instantiate(DecodingData data) {
    return GlobalSearchResponse(
      status: data.dec(_f$status),
      data: data.dec(_f$data),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static GlobalSearchResponse fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<GlobalSearchResponse>(map);
  }

  static GlobalSearchResponse fromJson(String json) {
    return ensureInitialized().decodeJson<GlobalSearchResponse>(json);
  }
}

mixin GlobalSearchResponseMappable {
  String toJson() {
    return GlobalSearchResponseMapper.ensureInitialized()
        .encodeJson<GlobalSearchResponse>(this as GlobalSearchResponse);
  }

  Map<String, dynamic> toMap() {
    return GlobalSearchResponseMapper.ensureInitialized()
        .encodeMap<GlobalSearchResponse>(this as GlobalSearchResponse);
  }

  GlobalSearchResponseCopyWith<
    GlobalSearchResponse,
    GlobalSearchResponse,
    GlobalSearchResponse
  >
  get copyWith =>
      _GlobalSearchResponseCopyWithImpl<
        GlobalSearchResponse,
        GlobalSearchResponse
      >(this as GlobalSearchResponse, $identity, $identity);
  @override
  String toString() {
    return GlobalSearchResponseMapper.ensureInitialized().stringifyValue(
      this as GlobalSearchResponse,
    );
  }

  @override
  bool operator ==(Object other) {
    return GlobalSearchResponseMapper.ensureInitialized().equalsValue(
      this as GlobalSearchResponse,
      other,
    );
  }

  @override
  int get hashCode {
    return GlobalSearchResponseMapper.ensureInitialized().hashValue(
      this as GlobalSearchResponse,
    );
  }
}

extension GlobalSearchResponseValueCopy<$R, $Out>
    on ObjectCopyWith<$R, GlobalSearchResponse, $Out> {
  GlobalSearchResponseCopyWith<$R, GlobalSearchResponse, $Out>
  get $asGlobalSearchResponse => $base.as(
    (v, t, t2) => _GlobalSearchResponseCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class GlobalSearchResponseCopyWith<
  $R,
  $In extends GlobalSearchResponse,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  GlobalSearchDataCopyWith<$R, GlobalSearchData, GlobalSearchData> get data;
  $R call({String? status, GlobalSearchData? data});
  GlobalSearchResponseCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _GlobalSearchResponseCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, GlobalSearchResponse, $Out>
    implements GlobalSearchResponseCopyWith<$R, GlobalSearchResponse, $Out> {
  _GlobalSearchResponseCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<GlobalSearchResponse> $mapper =
      GlobalSearchResponseMapper.ensureInitialized();
  @override
  GlobalSearchDataCopyWith<$R, GlobalSearchData, GlobalSearchData> get data =>
      $value.data.copyWith.$chain((v) => call(data: v));
  @override
  $R call({String? status, GlobalSearchData? data}) => $apply(
    FieldCopyWithData({
      if (status != null) #status: status,
      if (data != null) #data: data,
    }),
  );
  @override
  GlobalSearchResponse $make(CopyWithData data) => GlobalSearchResponse(
    status: data.get(#status, or: $value.status),
    data: data.get(#data, or: $value.data),
  );

  @override
  GlobalSearchResponseCopyWith<$R2, GlobalSearchResponse, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _GlobalSearchResponseCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class GlobalSearchDataMapper extends ClassMapperBase<GlobalSearchData> {
  GlobalSearchDataMapper._();

  static GlobalSearchDataMapper? _instance;
  static GlobalSearchDataMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = GlobalSearchDataMapper._());
      GlobalSearchResourceResultMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'GlobalSearchData';

  static Map<String, GlobalSearchResourceResult> _$results(
    GlobalSearchData v,
  ) => v.results;
  static const Field<GlobalSearchData, Map<String, GlobalSearchResourceResult>>
  _f$results = Field('results', _$results);

  @override
  final MappableFields<GlobalSearchData> fields = const {#results: _f$results};

  static GlobalSearchData _instantiate(DecodingData data) {
    return GlobalSearchData(results: data.dec(_f$results));
  }

  @override
  final Function instantiate = _instantiate;

  static GlobalSearchData fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<GlobalSearchData>(map);
  }

  static GlobalSearchData fromJson(String json) {
    return ensureInitialized().decodeJson<GlobalSearchData>(json);
  }
}

mixin GlobalSearchDataMappable {
  String toJson() {
    return GlobalSearchDataMapper.ensureInitialized()
        .encodeJson<GlobalSearchData>(this as GlobalSearchData);
  }

  Map<String, dynamic> toMap() {
    return GlobalSearchDataMapper.ensureInitialized()
        .encodeMap<GlobalSearchData>(this as GlobalSearchData);
  }

  GlobalSearchDataCopyWith<GlobalSearchData, GlobalSearchData, GlobalSearchData>
  get copyWith =>
      _GlobalSearchDataCopyWithImpl<GlobalSearchData, GlobalSearchData>(
        this as GlobalSearchData,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return GlobalSearchDataMapper.ensureInitialized().stringifyValue(
      this as GlobalSearchData,
    );
  }

  @override
  bool operator ==(Object other) {
    return GlobalSearchDataMapper.ensureInitialized().equalsValue(
      this as GlobalSearchData,
      other,
    );
  }

  @override
  int get hashCode {
    return GlobalSearchDataMapper.ensureInitialized().hashValue(
      this as GlobalSearchData,
    );
  }
}

extension GlobalSearchDataValueCopy<$R, $Out>
    on ObjectCopyWith<$R, GlobalSearchData, $Out> {
  GlobalSearchDataCopyWith<$R, GlobalSearchData, $Out>
  get $asGlobalSearchData =>
      $base.as((v, t, t2) => _GlobalSearchDataCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class GlobalSearchDataCopyWith<$R, $In extends GlobalSearchData, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<
    $R,
    String,
    GlobalSearchResourceResult,
    GlobalSearchResourceResultCopyWith<
      $R,
      GlobalSearchResourceResult,
      GlobalSearchResourceResult
    >
  >
  get results;
  $R call({Map<String, GlobalSearchResourceResult>? results});
  GlobalSearchDataCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _GlobalSearchDataCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, GlobalSearchData, $Out>
    implements GlobalSearchDataCopyWith<$R, GlobalSearchData, $Out> {
  _GlobalSearchDataCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<GlobalSearchData> $mapper =
      GlobalSearchDataMapper.ensureInitialized();
  @override
  MapCopyWith<
    $R,
    String,
    GlobalSearchResourceResult,
    GlobalSearchResourceResultCopyWith<
      $R,
      GlobalSearchResourceResult,
      GlobalSearchResourceResult
    >
  >
  get results => MapCopyWith(
    $value.results,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(results: v),
  );
  @override
  $R call({Map<String, GlobalSearchResourceResult>? results}) =>
      $apply(FieldCopyWithData({if (results != null) #results: results}));
  @override
  GlobalSearchData $make(CopyWithData data) =>
      GlobalSearchData(results: data.get(#results, or: $value.results));

  @override
  GlobalSearchDataCopyWith<$R2, GlobalSearchData, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _GlobalSearchDataCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class GlobalSearchResourceResultMapper
    extends ClassMapperBase<GlobalSearchResourceResult> {
  GlobalSearchResourceResultMapper._();

  static GlobalSearchResourceResultMapper? _instance;
  static GlobalSearchResourceResultMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(
        _instance = GlobalSearchResourceResultMapper._(),
      );
      SearchResultItemMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'GlobalSearchResourceResult';

  static List<SearchResultItem> _$items(GlobalSearchResourceResult v) =>
      v.items;
  static const Field<GlobalSearchResourceResult, List<SearchResultItem>>
  _f$items = Field('items', _$items);
  static int _$totalCount(GlobalSearchResourceResult v) => v.totalCount;
  static const Field<GlobalSearchResourceResult, int> _f$totalCount = Field(
    'totalCount',
    _$totalCount,
  );

  @override
  final MappableFields<GlobalSearchResourceResult> fields = const {
    #items: _f$items,
    #totalCount: _f$totalCount,
  };

  static GlobalSearchResourceResult _instantiate(DecodingData data) {
    return GlobalSearchResourceResult(
      items: data.dec(_f$items),
      totalCount: data.dec(_f$totalCount),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static GlobalSearchResourceResult fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<GlobalSearchResourceResult>(map);
  }

  static GlobalSearchResourceResult fromJson(String json) {
    return ensureInitialized().decodeJson<GlobalSearchResourceResult>(json);
  }
}

mixin GlobalSearchResourceResultMappable {
  String toJson() {
    return GlobalSearchResourceResultMapper.ensureInitialized()
        .encodeJson<GlobalSearchResourceResult>(
          this as GlobalSearchResourceResult,
        );
  }

  Map<String, dynamic> toMap() {
    return GlobalSearchResourceResultMapper.ensureInitialized()
        .encodeMap<GlobalSearchResourceResult>(
          this as GlobalSearchResourceResult,
        );
  }

  GlobalSearchResourceResultCopyWith<
    GlobalSearchResourceResult,
    GlobalSearchResourceResult,
    GlobalSearchResourceResult
  >
  get copyWith =>
      _GlobalSearchResourceResultCopyWithImpl<
        GlobalSearchResourceResult,
        GlobalSearchResourceResult
      >(this as GlobalSearchResourceResult, $identity, $identity);
  @override
  String toString() {
    return GlobalSearchResourceResultMapper.ensureInitialized().stringifyValue(
      this as GlobalSearchResourceResult,
    );
  }

  @override
  bool operator ==(Object other) {
    return GlobalSearchResourceResultMapper.ensureInitialized().equalsValue(
      this as GlobalSearchResourceResult,
      other,
    );
  }

  @override
  int get hashCode {
    return GlobalSearchResourceResultMapper.ensureInitialized().hashValue(
      this as GlobalSearchResourceResult,
    );
  }
}

extension GlobalSearchResourceResultValueCopy<$R, $Out>
    on ObjectCopyWith<$R, GlobalSearchResourceResult, $Out> {
  GlobalSearchResourceResultCopyWith<$R, GlobalSearchResourceResult, $Out>
  get $asGlobalSearchResourceResult => $base.as(
    (v, t, t2) => _GlobalSearchResourceResultCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class GlobalSearchResourceResultCopyWith<
  $R,
  $In extends GlobalSearchResourceResult,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    SearchResultItem,
    SearchResultItemCopyWith<$R, SearchResultItem, SearchResultItem>
  >
  get items;
  $R call({List<SearchResultItem>? items, int? totalCount});
  GlobalSearchResourceResultCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _GlobalSearchResourceResultCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, GlobalSearchResourceResult, $Out>
    implements
        GlobalSearchResourceResultCopyWith<
          $R,
          GlobalSearchResourceResult,
          $Out
        > {
  _GlobalSearchResourceResultCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<GlobalSearchResourceResult> $mapper =
      GlobalSearchResourceResultMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    SearchResultItem,
    SearchResultItemCopyWith<$R, SearchResultItem, SearchResultItem>
  >
  get items => ListCopyWith(
    $value.items,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(items: v),
  );
  @override
  $R call({List<SearchResultItem>? items, int? totalCount}) => $apply(
    FieldCopyWithData({
      if (items != null) #items: items,
      if (totalCount != null) #totalCount: totalCount,
    }),
  );
  @override
  GlobalSearchResourceResult $make(CopyWithData data) =>
      GlobalSearchResourceResult(
        items: data.get(#items, or: $value.items),
        totalCount: data.get(#totalCount, or: $value.totalCount),
      );

  @override
  GlobalSearchResourceResultCopyWith<$R2, GlobalSearchResourceResult, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _GlobalSearchResourceResultCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

