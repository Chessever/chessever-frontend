// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'gamebase_repository.dart';

class GamebaseResponseMapper extends ClassMapperBase<GamebaseResponse> {
  GamebaseResponseMapper._();

  static GamebaseResponseMapper? _instance;
  static GamebaseResponseMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = GamebaseResponseMapper._());
      GamebaseDataMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'GamebaseResponse';

  static String _$status(GamebaseResponse v) => v.status;
  static const Field<GamebaseResponse, String> _f$status = Field(
    'status',
    _$status,
  );
  static GamebaseData _$data(GamebaseResponse v) => v.data;
  static const Field<GamebaseResponse, GamebaseData> _f$data = Field(
    'data',
    _$data,
  );

  @override
  final MappableFields<GamebaseResponse> fields = const {
    #status: _f$status,
    #data: _f$data,
  };

  static GamebaseResponse _instantiate(DecodingData data) {
    return GamebaseResponse(
      status: data.dec(_f$status),
      data: data.dec(_f$data),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static GamebaseResponse fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<GamebaseResponse>(map);
  }

  static GamebaseResponse fromJson(String json) {
    return ensureInitialized().decodeJson<GamebaseResponse>(json);
  }
}

mixin GamebaseResponseMappable {
  String toJson() {
    return GamebaseResponseMapper.ensureInitialized()
        .encodeJson<GamebaseResponse>(this as GamebaseResponse);
  }

  Map<String, dynamic> toMap() {
    return GamebaseResponseMapper.ensureInitialized()
        .encodeMap<GamebaseResponse>(this as GamebaseResponse);
  }

  GamebaseResponseCopyWith<GamebaseResponse, GamebaseResponse, GamebaseResponse>
  get copyWith =>
      _GamebaseResponseCopyWithImpl<GamebaseResponse, GamebaseResponse>(
        this as GamebaseResponse,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return GamebaseResponseMapper.ensureInitialized().stringifyValue(
      this as GamebaseResponse,
    );
  }

  @override
  bool operator ==(Object other) {
    return GamebaseResponseMapper.ensureInitialized().equalsValue(
      this as GamebaseResponse,
      other,
    );
  }

  @override
  int get hashCode {
    return GamebaseResponseMapper.ensureInitialized().hashValue(
      this as GamebaseResponse,
    );
  }
}

extension GamebaseResponseValueCopy<$R, $Out>
    on ObjectCopyWith<$R, GamebaseResponse, $Out> {
  GamebaseResponseCopyWith<$R, GamebaseResponse, $Out>
  get $asGamebaseResponse =>
      $base.as((v, t, t2) => _GamebaseResponseCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class GamebaseResponseCopyWith<$R, $In extends GamebaseResponse, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  GamebaseDataCopyWith<$R, GamebaseData, GamebaseData> get data;
  $R call({String? status, GamebaseData? data});
  GamebaseResponseCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _GamebaseResponseCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, GamebaseResponse, $Out>
    implements GamebaseResponseCopyWith<$R, GamebaseResponse, $Out> {
  _GamebaseResponseCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<GamebaseResponse> $mapper =
      GamebaseResponseMapper.ensureInitialized();
  @override
  GamebaseDataCopyWith<$R, GamebaseData, GamebaseData> get data =>
      $value.data.copyWith.$chain((v) => call(data: v));
  @override
  $R call({String? status, GamebaseData? data}) => $apply(
    FieldCopyWithData({
      if (status != null) #status: status,
      if (data != null) #data: data,
    }),
  );
  @override
  GamebaseResponse $make(CopyWithData data) => GamebaseResponse(
    status: data.get(#status, or: $value.status),
    data: data.get(#data, or: $value.data),
  );

  @override
  GamebaseResponseCopyWith<$R2, GamebaseResponse, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _GamebaseResponseCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class GamebaseDataMapper extends ClassMapperBase<GamebaseData> {
  GamebaseDataMapper._();

  static GamebaseDataMapper? _instance;
  static GamebaseDataMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = GamebaseDataMapper._());
      MoveAggregateMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'GamebaseData';

  static List<MoveAggregate> _$moves(GamebaseData v) => v.moves;
  static const Field<GamebaseData, List<MoveAggregate>> _f$moves = Field(
    'moves',
    _$moves,
  );

  @override
  final MappableFields<GamebaseData> fields = const {#moves: _f$moves};

  static GamebaseData _instantiate(DecodingData data) {
    return GamebaseData(moves: data.dec(_f$moves));
  }

  @override
  final Function instantiate = _instantiate;

  static GamebaseData fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<GamebaseData>(map);
  }

  static GamebaseData fromJson(String json) {
    return ensureInitialized().decodeJson<GamebaseData>(json);
  }
}

mixin GamebaseDataMappable {
  String toJson() {
    return GamebaseDataMapper.ensureInitialized().encodeJson<GamebaseData>(
      this as GamebaseData,
    );
  }

  Map<String, dynamic> toMap() {
    return GamebaseDataMapper.ensureInitialized().encodeMap<GamebaseData>(
      this as GamebaseData,
    );
  }

  GamebaseDataCopyWith<GamebaseData, GamebaseData, GamebaseData> get copyWith =>
      _GamebaseDataCopyWithImpl<GamebaseData, GamebaseData>(
        this as GamebaseData,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return GamebaseDataMapper.ensureInitialized().stringifyValue(
      this as GamebaseData,
    );
  }

  @override
  bool operator ==(Object other) {
    return GamebaseDataMapper.ensureInitialized().equalsValue(
      this as GamebaseData,
      other,
    );
  }

  @override
  int get hashCode {
    return GamebaseDataMapper.ensureInitialized().hashValue(
      this as GamebaseData,
    );
  }
}

extension GamebaseDataValueCopy<$R, $Out>
    on ObjectCopyWith<$R, GamebaseData, $Out> {
  GamebaseDataCopyWith<$R, GamebaseData, $Out> get $asGamebaseData =>
      $base.as((v, t, t2) => _GamebaseDataCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class GamebaseDataCopyWith<$R, $In extends GamebaseData, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    MoveAggregate,
    MoveAggregateCopyWith<$R, MoveAggregate, MoveAggregate>
  >
  get moves;
  $R call({List<MoveAggregate>? moves});
  GamebaseDataCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _GamebaseDataCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, GamebaseData, $Out>
    implements GamebaseDataCopyWith<$R, GamebaseData, $Out> {
  _GamebaseDataCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<GamebaseData> $mapper =
      GamebaseDataMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    MoveAggregate,
    MoveAggregateCopyWith<$R, MoveAggregate, MoveAggregate>
  >
  get moves => ListCopyWith(
    $value.moves,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(moves: v),
  );
  @override
  $R call({List<MoveAggregate>? moves}) =>
      $apply(FieldCopyWithData({if (moves != null) #moves: moves}));
  @override
  GamebaseData $make(CopyWithData data) =>
      GamebaseData(moves: data.get(#moves, or: $value.moves));

  @override
  GamebaseDataCopyWith<$R2, GamebaseData, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _GamebaseDataCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

