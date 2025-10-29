// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'favorite_player.dart';

class FavoritePlayerMapper extends ClassMapperBase<FavoritePlayer> {
  FavoritePlayerMapper._();

  static FavoritePlayerMapper? _instance;
  static FavoritePlayerMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = FavoritePlayerMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'FavoritePlayer';

  static String _$id(FavoritePlayer v) => v.id;
  static const Field<FavoritePlayer, String> _f$id = Field('id', _$id);
  static String _$userId(FavoritePlayer v) => v.userId;
  static const Field<FavoritePlayer, String> _f$userId = Field(
    'userId',
    _$userId,
  );
  static String? _$fideId(FavoritePlayer v) => v.fideId;
  static const Field<FavoritePlayer, String> _f$fideId = Field(
    'fideId',
    _$fideId,
    opt: true,
  );
  static String _$playerName(FavoritePlayer v) => v.playerName;
  static const Field<FavoritePlayer, String> _f$playerName = Field(
    'playerName',
    _$playerName,
  );
  static Map<String, dynamic> _$metadata(FavoritePlayer v) => v.metadata;
  static const Field<FavoritePlayer, Map<String, dynamic>> _f$metadata = Field(
    'metadata',
    _$metadata,
  );
  static DateTime _$createdAt(FavoritePlayer v) => v.createdAt;
  static const Field<FavoritePlayer, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );
  static DateTime _$updatedAt(FavoritePlayer v) => v.updatedAt;
  static const Field<FavoritePlayer, DateTime> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
  );

  @override
  final MappableFields<FavoritePlayer> fields = const {
    #id: _f$id,
    #userId: _f$userId,
    #fideId: _f$fideId,
    #playerName: _f$playerName,
    #metadata: _f$metadata,
    #createdAt: _f$createdAt,
    #updatedAt: _f$updatedAt,
  };

  static FavoritePlayer _instantiate(DecodingData data) {
    return FavoritePlayer(
      id: data.dec(_f$id),
      userId: data.dec(_f$userId),
      fideId: data.dec(_f$fideId),
      playerName: data.dec(_f$playerName),
      metadata: data.dec(_f$metadata),
      createdAt: data.dec(_f$createdAt),
      updatedAt: data.dec(_f$updatedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static FavoritePlayer fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<FavoritePlayer>(map);
  }

  static FavoritePlayer fromJson(String json) {
    return ensureInitialized().decodeJson<FavoritePlayer>(json);
  }
}

mixin FavoritePlayerMappable {
  String toJson() {
    return FavoritePlayerMapper.ensureInitialized().encodeJson<FavoritePlayer>(
      this as FavoritePlayer,
    );
  }

  Map<String, dynamic> toMap() {
    return FavoritePlayerMapper.ensureInitialized().encodeMap<FavoritePlayer>(
      this as FavoritePlayer,
    );
  }

  FavoritePlayerCopyWith<FavoritePlayer, FavoritePlayer, FavoritePlayer>
  get copyWith => _FavoritePlayerCopyWithImpl<FavoritePlayer, FavoritePlayer>(
    this as FavoritePlayer,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return FavoritePlayerMapper.ensureInitialized().stringifyValue(
      this as FavoritePlayer,
    );
  }

  @override
  bool operator ==(Object other) {
    return FavoritePlayerMapper.ensureInitialized().equalsValue(
      this as FavoritePlayer,
      other,
    );
  }

  @override
  int get hashCode {
    return FavoritePlayerMapper.ensureInitialized().hashValue(
      this as FavoritePlayer,
    );
  }
}

extension FavoritePlayerValueCopy<$R, $Out>
    on ObjectCopyWith<$R, FavoritePlayer, $Out> {
  FavoritePlayerCopyWith<$R, FavoritePlayer, $Out> get $asFavoritePlayer =>
      $base.as((v, t, t2) => _FavoritePlayerCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class FavoritePlayerCopyWith<$R, $In extends FavoritePlayer, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, dynamic, ObjectCopyWith<$R, dynamic, dynamic>>
  get metadata;
  $R call({
    String? id,
    String? userId,
    String? fideId,
    String? playerName,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  });
  FavoritePlayerCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _FavoritePlayerCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, FavoritePlayer, $Out>
    implements FavoritePlayerCopyWith<$R, FavoritePlayer, $Out> {
  _FavoritePlayerCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<FavoritePlayer> $mapper =
      FavoritePlayerMapper.ensureInitialized();
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
    Object? fideId = $none,
    String? playerName,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (userId != null) #userId: userId,
      if (fideId != $none) #fideId: fideId,
      if (playerName != null) #playerName: playerName,
      if (metadata != null) #metadata: metadata,
      if (createdAt != null) #createdAt: createdAt,
      if (updatedAt != null) #updatedAt: updatedAt,
    }),
  );
  @override
  FavoritePlayer $make(CopyWithData data) => FavoritePlayer(
    id: data.get(#id, or: $value.id),
    userId: data.get(#userId, or: $value.userId),
    fideId: data.get(#fideId, or: $value.fideId),
    playerName: data.get(#playerName, or: $value.playerName),
    metadata: data.get(#metadata, or: $value.metadata),
    createdAt: data.get(#createdAt, or: $value.createdAt),
    updatedAt: data.get(#updatedAt, or: $value.updatedAt),
  );

  @override
  FavoritePlayerCopyWith<$R2, FavoritePlayer, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _FavoritePlayerCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

