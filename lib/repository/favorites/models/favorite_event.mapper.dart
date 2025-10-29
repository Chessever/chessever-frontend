// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'favorite_event.dart';

class FavoriteEventMapper extends ClassMapperBase<FavoriteEvent> {
  FavoriteEventMapper._();

  static FavoriteEventMapper? _instance;
  static FavoriteEventMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = FavoriteEventMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'FavoriteEvent';

  static String _$id(FavoriteEvent v) => v.id;
  static const Field<FavoriteEvent, String> _f$id = Field('id', _$id);
  static String _$userId(FavoriteEvent v) => v.userId;
  static const Field<FavoriteEvent, String> _f$userId = Field(
    'userId',
    _$userId,
  );
  static String _$eventId(FavoriteEvent v) => v.eventId;
  static const Field<FavoriteEvent, String> _f$eventId = Field(
    'eventId',
    _$eventId,
  );
  static String _$eventName(FavoriteEvent v) => v.eventName;
  static const Field<FavoriteEvent, String> _f$eventName = Field(
    'eventName',
    _$eventName,
  );
  static Map<String, dynamic> _$metadata(FavoriteEvent v) => v.metadata;
  static const Field<FavoriteEvent, Map<String, dynamic>> _f$metadata = Field(
    'metadata',
    _$metadata,
  );
  static DateTime _$createdAt(FavoriteEvent v) => v.createdAt;
  static const Field<FavoriteEvent, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );
  static DateTime _$updatedAt(FavoriteEvent v) => v.updatedAt;
  static const Field<FavoriteEvent, DateTime> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
  );

  @override
  final MappableFields<FavoriteEvent> fields = const {
    #id: _f$id,
    #userId: _f$userId,
    #eventId: _f$eventId,
    #eventName: _f$eventName,
    #metadata: _f$metadata,
    #createdAt: _f$createdAt,
    #updatedAt: _f$updatedAt,
  };

  static FavoriteEvent _instantiate(DecodingData data) {
    return FavoriteEvent(
      id: data.dec(_f$id),
      userId: data.dec(_f$userId),
      eventId: data.dec(_f$eventId),
      eventName: data.dec(_f$eventName),
      metadata: data.dec(_f$metadata),
      createdAt: data.dec(_f$createdAt),
      updatedAt: data.dec(_f$updatedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static FavoriteEvent fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<FavoriteEvent>(map);
  }

  static FavoriteEvent fromJson(String json) {
    return ensureInitialized().decodeJson<FavoriteEvent>(json);
  }
}

mixin FavoriteEventMappable {
  String toJson() {
    return FavoriteEventMapper.ensureInitialized().encodeJson<FavoriteEvent>(
      this as FavoriteEvent,
    );
  }

  Map<String, dynamic> toMap() {
    return FavoriteEventMapper.ensureInitialized().encodeMap<FavoriteEvent>(
      this as FavoriteEvent,
    );
  }

  FavoriteEventCopyWith<FavoriteEvent, FavoriteEvent, FavoriteEvent>
  get copyWith => _FavoriteEventCopyWithImpl<FavoriteEvent, FavoriteEvent>(
    this as FavoriteEvent,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return FavoriteEventMapper.ensureInitialized().stringifyValue(
      this as FavoriteEvent,
    );
  }

  @override
  bool operator ==(Object other) {
    return FavoriteEventMapper.ensureInitialized().equalsValue(
      this as FavoriteEvent,
      other,
    );
  }

  @override
  int get hashCode {
    return FavoriteEventMapper.ensureInitialized().hashValue(
      this as FavoriteEvent,
    );
  }
}

extension FavoriteEventValueCopy<$R, $Out>
    on ObjectCopyWith<$R, FavoriteEvent, $Out> {
  FavoriteEventCopyWith<$R, FavoriteEvent, $Out> get $asFavoriteEvent =>
      $base.as((v, t, t2) => _FavoriteEventCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class FavoriteEventCopyWith<$R, $In extends FavoriteEvent, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, dynamic, ObjectCopyWith<$R, dynamic, dynamic>>
  get metadata;
  $R call({
    String? id,
    String? userId,
    String? eventId,
    String? eventName,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  });
  FavoriteEventCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _FavoriteEventCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, FavoriteEvent, $Out>
    implements FavoriteEventCopyWith<$R, FavoriteEvent, $Out> {
  _FavoriteEventCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<FavoriteEvent> $mapper =
      FavoriteEventMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, dynamic, ObjectCopyWith<$R, dynamic, dynamic>>
  get metadata => MapCopyWith(
    $value.metadata,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(metadata: v),
  );
  @override
  $R call({
    String? id,
    String? userId,
    String? eventId,
    String? eventName,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (userId != null) #userId: userId,
      if (eventId != null) #eventId: eventId,
      if (eventName != null) #eventName: eventName,
      if (metadata != null) #metadata: metadata,
      if (createdAt != null) #createdAt: createdAt,
      if (updatedAt != null) #updatedAt: updatedAt,
    }),
  );
  @override
  FavoriteEvent $make(CopyWithData data) => FavoriteEvent(
    id: data.get(#id, or: $value.id),
    userId: data.get(#userId, or: $value.userId),
    eventId: data.get(#eventId, or: $value.eventId),
    eventName: data.get(#eventName, or: $value.eventName),
    metadata: data.get(#metadata, or: $value.metadata),
    createdAt: data.get(#createdAt, or: $value.createdAt),
    updatedAt: data.get(#updatedAt, or: $value.updatedAt),
  );

  @override
  FavoriteEventCopyWith<$R2, FavoriteEvent, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _FavoriteEventCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

