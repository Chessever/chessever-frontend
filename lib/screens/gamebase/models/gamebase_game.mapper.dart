// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'gamebase_game.dart';

class TimeControlMapper extends EnumMapper<TimeControl> {
  TimeControlMapper._();

  static TimeControlMapper? _instance;
  static TimeControlMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TimeControlMapper._());
    }
    return _instance!;
  }

  static TimeControl fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  TimeControl decode(dynamic value) {
    switch (value) {
      case 'CLASSICAL':
        return TimeControl.classical;
      case 'RAPID':
        return TimeControl.rapid;
      case 'BLITZ':
        return TimeControl.blitz;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(TimeControl self) {
    switch (self) {
      case TimeControl.classical:
        return 'CLASSICAL';
      case TimeControl.rapid:
        return 'RAPID';
      case TimeControl.blitz:
        return 'BLITZ';
    }
  }
}

extension TimeControlMapperExtension on TimeControl {
  dynamic toValue() {
    TimeControlMapper.ensureInitialized();
    return MapperContainer.globals.toValue<TimeControl>(this);
  }
}

class GameResultMapper extends EnumMapper<GameResult> {
  GameResultMapper._();

  static GameResultMapper? _instance;
  static GameResultMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = GameResultMapper._());
    }
    return _instance!;
  }

  static GameResult fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  GameResult decode(dynamic value) {
    switch (value) {
      case 'W':
        return GameResult.whiteWins;
      case 'B':
        return GameResult.blackWins;
      case 'D':
        return GameResult.draw;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(GameResult self) {
    switch (self) {
      case GameResult.whiteWins:
        return 'W';
      case GameResult.blackWins:
        return 'B';
      case GameResult.draw:
        return 'D';
    }
  }
}

extension GameResultMapperExtension on GameResult {
  dynamic toValue() {
    GameResultMapper.ensureInitialized();
    return MapperContainer.globals.toValue<GameResult>(this);
  }
}

class GamebaseGameMapper extends ClassMapperBase<GamebaseGame> {
  GamebaseGameMapper._();

  static GamebaseGameMapper? _instance;
  static GamebaseGameMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = GamebaseGameMapper._());
      GameResultMapper.ensureInitialized();
      TimeControlMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'GamebaseGame';

  static String _$id(GamebaseGame v) => v.id;
  static const Field<GamebaseGame, String> _f$id = Field('id', _$id);
  static DateTime _$date(GamebaseGame v) => v.date;
  static const Field<GamebaseGame, DateTime> _f$date = Field('date', _$date);
  static GameResult _$result(GamebaseGame v) => v.result;
  static const Field<GamebaseGame, GameResult> _f$result = Field(
    'result',
    _$result,
  );
  static TimeControl _$timeControl(GamebaseGame v) => v.timeControl;
  static const Field<GamebaseGame, TimeControl> _f$timeControl = Field(
    'timeControl',
    _$timeControl,
  );
  static String? _$whitePlayerId(GamebaseGame v) => v.whitePlayerId;
  static const Field<GamebaseGame, String> _f$whitePlayerId = Field(
    'whitePlayerId',
    _$whitePlayerId,
    opt: true,
  );
  static String? _$blackPlayerId(GamebaseGame v) => v.blackPlayerId;
  static const Field<GamebaseGame, String> _f$blackPlayerId = Field(
    'blackPlayerId',
    _$blackPlayerId,
    opt: true,
  );
  static Map<String, dynamic>? _$data(GamebaseGame v) => v.data;
  static const Field<GamebaseGame, Map<String, dynamic>> _f$data = Field(
    'data',
    _$data,
    opt: true,
  );

  @override
  final MappableFields<GamebaseGame> fields = const {
    #id: _f$id,
    #date: _f$date,
    #result: _f$result,
    #timeControl: _f$timeControl,
    #whitePlayerId: _f$whitePlayerId,
    #blackPlayerId: _f$blackPlayerId,
    #data: _f$data,
  };

  static GamebaseGame _instantiate(DecodingData data) {
    return GamebaseGame(
      id: data.dec(_f$id),
      date: data.dec(_f$date),
      result: data.dec(_f$result),
      timeControl: data.dec(_f$timeControl),
      whitePlayerId: data.dec(_f$whitePlayerId),
      blackPlayerId: data.dec(_f$blackPlayerId),
      data: data.dec(_f$data),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static GamebaseGame fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<GamebaseGame>(map);
  }

  static GamebaseGame fromJson(String json) {
    return ensureInitialized().decodeJson<GamebaseGame>(json);
  }
}

mixin GamebaseGameMappable {
  String toJson() {
    return GamebaseGameMapper.ensureInitialized().encodeJson<GamebaseGame>(
      this as GamebaseGame,
    );
  }

  Map<String, dynamic> toMap() {
    return GamebaseGameMapper.ensureInitialized().encodeMap<GamebaseGame>(
      this as GamebaseGame,
    );
  }

  GamebaseGameCopyWith<GamebaseGame, GamebaseGame, GamebaseGame> get copyWith =>
      _GamebaseGameCopyWithImpl<GamebaseGame, GamebaseGame>(
        this as GamebaseGame,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return GamebaseGameMapper.ensureInitialized().stringifyValue(
      this as GamebaseGame,
    );
  }

  @override
  bool operator ==(Object other) {
    return GamebaseGameMapper.ensureInitialized().equalsValue(
      this as GamebaseGame,
      other,
    );
  }

  @override
  int get hashCode {
    return GamebaseGameMapper.ensureInitialized().hashValue(
      this as GamebaseGame,
    );
  }
}

extension GamebaseGameValueCopy<$R, $Out>
    on ObjectCopyWith<$R, GamebaseGame, $Out> {
  GamebaseGameCopyWith<$R, GamebaseGame, $Out> get $asGamebaseGame =>
      $base.as((v, t, t2) => _GamebaseGameCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class GamebaseGameCopyWith<$R, $In extends GamebaseGame, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, dynamic, ObjectCopyWith<$R, dynamic, dynamic>>?
  get data;
  $R call({
    String? id,
    DateTime? date,
    GameResult? result,
    TimeControl? timeControl,
    String? whitePlayerId,
    String? blackPlayerId,
    Map<String, dynamic>? data,
  });
  GamebaseGameCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _GamebaseGameCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, GamebaseGame, $Out>
    implements GamebaseGameCopyWith<$R, GamebaseGame, $Out> {
  _GamebaseGameCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<GamebaseGame> $mapper =
      GamebaseGameMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, dynamic, ObjectCopyWith<$R, dynamic, dynamic>>?
  get data => $value.data != null
      ? MapCopyWith(
          $value.data!,
          (v, t) => ObjectCopyWith(v, $identity, t),
          (v) => call(data: v),
        )
      : null;
  @override
  $R call({
    String? id,
    DateTime? date,
    GameResult? result,
    TimeControl? timeControl,
    Object? whitePlayerId = $none,
    Object? blackPlayerId = $none,
    Object? data = $none,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (date != null) #date: date,
      if (result != null) #result: result,
      if (timeControl != null) #timeControl: timeControl,
      if (whitePlayerId != $none) #whitePlayerId: whitePlayerId,
      if (blackPlayerId != $none) #blackPlayerId: blackPlayerId,
      if (data != $none) #data: data,
    }),
  );
  @override
  GamebaseGame $make(CopyWithData data) => GamebaseGame(
    id: data.get(#id, or: $value.id),
    date: data.get(#date, or: $value.date),
    result: data.get(#result, or: $value.result),
    timeControl: data.get(#timeControl, or: $value.timeControl),
    whitePlayerId: data.get(#whitePlayerId, or: $value.whitePlayerId),
    blackPlayerId: data.get(#blackPlayerId, or: $value.blackPlayerId),
    data: data.get(#data, or: $value.data),
  );

  @override
  GamebaseGameCopyWith<$R2, GamebaseGame, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _GamebaseGameCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

