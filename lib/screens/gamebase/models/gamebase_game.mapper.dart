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

class GamebaseGameWithPgnMapper extends ClassMapperBase<GamebaseGameWithPgn> {
  GamebaseGameWithPgnMapper._();

  static GamebaseGameWithPgnMapper? _instance;
  static GamebaseGameWithPgnMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = GamebaseGameWithPgnMapper._());
      GameResultMapper.ensureInitialized();
      TimeControlMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'GamebaseGameWithPgn';

  static String _$id(GamebaseGameWithPgn v) => v.id;
  static const Field<GamebaseGameWithPgn, String> _f$id = Field('id', _$id);
  static DateTime _$date(GamebaseGameWithPgn v) => v.date;
  static const Field<GamebaseGameWithPgn, DateTime> _f$date = Field(
    'date',
    _$date,
  );
  static GameResult _$result(GamebaseGameWithPgn v) => v.result;
  static const Field<GamebaseGameWithPgn, GameResult> _f$result = Field(
    'result',
    _$result,
  );
  static TimeControl _$timeControl(GamebaseGameWithPgn v) => v.timeControl;
  static const Field<GamebaseGameWithPgn, TimeControl> _f$timeControl = Field(
    'timeControl',
    _$timeControl,
  );
  static String? _$whitePlayerId(GamebaseGameWithPgn v) => v.whitePlayerId;
  static const Field<GamebaseGameWithPgn, String> _f$whitePlayerId = Field(
    'whitePlayerId',
    _$whitePlayerId,
    opt: true,
  );
  static String? _$blackPlayerId(GamebaseGameWithPgn v) => v.blackPlayerId;
  static const Field<GamebaseGameWithPgn, String> _f$blackPlayerId = Field(
    'blackPlayerId',
    _$blackPlayerId,
    opt: true,
  );
  static Map<String, dynamic>? _$data(GamebaseGameWithPgn v) => v.data;
  static const Field<GamebaseGameWithPgn, Map<String, dynamic>> _f$data = Field(
    'data',
    _$data,
    opt: true,
  );
  static String? _$pgn(GamebaseGameWithPgn v) => v.pgn;
  static const Field<GamebaseGameWithPgn, String> _f$pgn = Field(
    'pgn',
    _$pgn,
    opt: true,
  );
  static String? _$eco(GamebaseGameWithPgn v) => v.eco;
  static const Field<GamebaseGameWithPgn, String> _f$eco = Field(
    'eco',
    _$eco,
    opt: true,
  );
  static String? _$opening(GamebaseGameWithPgn v) => v.opening;
  static const Field<GamebaseGameWithPgn, String> _f$opening = Field(
    'opening',
    _$opening,
    opt: true,
  );
  static String? _$variation(GamebaseGameWithPgn v) => v.variation;
  static const Field<GamebaseGameWithPgn, String> _f$variation = Field(
    'variation',
    _$variation,
    opt: true,
  );
  static String? _$event(GamebaseGameWithPgn v) => v.event;
  static const Field<GamebaseGameWithPgn, String> _f$event = Field(
    'event',
    _$event,
    opt: true,
  );
  static String? _$site(GamebaseGameWithPgn v) => v.site;
  static const Field<GamebaseGameWithPgn, String> _f$site = Field(
    'site',
    _$site,
    opt: true,
  );
  static String? _$whiteName(GamebaseGameWithPgn v) => v.whiteName;
  static const Field<GamebaseGameWithPgn, String> _f$whiteName = Field(
    'whiteName',
    _$whiteName,
    opt: true,
  );
  static String? _$blackName(GamebaseGameWithPgn v) => v.blackName;
  static const Field<GamebaseGameWithPgn, String> _f$blackName = Field(
    'blackName',
    _$blackName,
    opt: true,
  );
  static int? _$whiteElo(GamebaseGameWithPgn v) => v.whiteElo;
  static const Field<GamebaseGameWithPgn, int> _f$whiteElo = Field(
    'whiteElo',
    _$whiteElo,
    opt: true,
  );
  static int? _$blackElo(GamebaseGameWithPgn v) => v.blackElo;
  static const Field<GamebaseGameWithPgn, int> _f$blackElo = Field(
    'blackElo',
    _$blackElo,
    opt: true,
  );

  @override
  final MappableFields<GamebaseGameWithPgn> fields = const {
    #id: _f$id,
    #date: _f$date,
    #result: _f$result,
    #timeControl: _f$timeControl,
    #whitePlayerId: _f$whitePlayerId,
    #blackPlayerId: _f$blackPlayerId,
    #data: _f$data,
    #pgn: _f$pgn,
    #eco: _f$eco,
    #opening: _f$opening,
    #variation: _f$variation,
    #event: _f$event,
    #site: _f$site,
    #whiteName: _f$whiteName,
    #blackName: _f$blackName,
    #whiteElo: _f$whiteElo,
    #blackElo: _f$blackElo,
  };

  static GamebaseGameWithPgn _instantiate(DecodingData data) {
    return GamebaseGameWithPgn(
      id: data.dec(_f$id),
      date: data.dec(_f$date),
      result: data.dec(_f$result),
      timeControl: data.dec(_f$timeControl),
      whitePlayerId: data.dec(_f$whitePlayerId),
      blackPlayerId: data.dec(_f$blackPlayerId),
      data: data.dec(_f$data),
      pgn: data.dec(_f$pgn),
      eco: data.dec(_f$eco),
      opening: data.dec(_f$opening),
      variation: data.dec(_f$variation),
      event: data.dec(_f$event),
      site: data.dec(_f$site),
      whiteName: data.dec(_f$whiteName),
      blackName: data.dec(_f$blackName),
      whiteElo: data.dec(_f$whiteElo),
      blackElo: data.dec(_f$blackElo),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static GamebaseGameWithPgn fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<GamebaseGameWithPgn>(map);
  }

  static GamebaseGameWithPgn fromJson(String json) {
    return ensureInitialized().decodeJson<GamebaseGameWithPgn>(json);
  }
}

mixin GamebaseGameWithPgnMappable {
  String toJson() {
    return GamebaseGameWithPgnMapper.ensureInitialized()
        .encodeJson<GamebaseGameWithPgn>(this as GamebaseGameWithPgn);
  }

  Map<String, dynamic> toMap() {
    return GamebaseGameWithPgnMapper.ensureInitialized()
        .encodeMap<GamebaseGameWithPgn>(this as GamebaseGameWithPgn);
  }

  GamebaseGameWithPgnCopyWith<
    GamebaseGameWithPgn,
    GamebaseGameWithPgn,
    GamebaseGameWithPgn
  >
  get copyWith =>
      _GamebaseGameWithPgnCopyWithImpl<
        GamebaseGameWithPgn,
        GamebaseGameWithPgn
      >(this as GamebaseGameWithPgn, $identity, $identity);
  @override
  String toString() {
    return GamebaseGameWithPgnMapper.ensureInitialized().stringifyValue(
      this as GamebaseGameWithPgn,
    );
  }

  @override
  bool operator ==(Object other) {
    return GamebaseGameWithPgnMapper.ensureInitialized().equalsValue(
      this as GamebaseGameWithPgn,
      other,
    );
  }

  @override
  int get hashCode {
    return GamebaseGameWithPgnMapper.ensureInitialized().hashValue(
      this as GamebaseGameWithPgn,
    );
  }
}

extension GamebaseGameWithPgnValueCopy<$R, $Out>
    on ObjectCopyWith<$R, GamebaseGameWithPgn, $Out> {
  GamebaseGameWithPgnCopyWith<$R, GamebaseGameWithPgn, $Out>
  get $asGamebaseGameWithPgn => $base.as(
    (v, t, t2) => _GamebaseGameWithPgnCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class GamebaseGameWithPgnCopyWith<
  $R,
  $In extends GamebaseGameWithPgn,
  $Out
>
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
    String? pgn,
    String? eco,
    String? opening,
    String? variation,
    String? event,
    String? site,
    String? whiteName,
    String? blackName,
    int? whiteElo,
    int? blackElo,
  });
  GamebaseGameWithPgnCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _GamebaseGameWithPgnCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, GamebaseGameWithPgn, $Out>
    implements GamebaseGameWithPgnCopyWith<$R, GamebaseGameWithPgn, $Out> {
  _GamebaseGameWithPgnCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<GamebaseGameWithPgn> $mapper =
      GamebaseGameWithPgnMapper.ensureInitialized();
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
    Object? pgn = $none,
    Object? eco = $none,
    Object? opening = $none,
    Object? variation = $none,
    Object? event = $none,
    Object? site = $none,
    Object? whiteName = $none,
    Object? blackName = $none,
    Object? whiteElo = $none,
    Object? blackElo = $none,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (date != null) #date: date,
      if (result != null) #result: result,
      if (timeControl != null) #timeControl: timeControl,
      if (whitePlayerId != $none) #whitePlayerId: whitePlayerId,
      if (blackPlayerId != $none) #blackPlayerId: blackPlayerId,
      if (data != $none) #data: data,
      if (pgn != $none) #pgn: pgn,
      if (eco != $none) #eco: eco,
      if (opening != $none) #opening: opening,
      if (variation != $none) #variation: variation,
      if (event != $none) #event: event,
      if (site != $none) #site: site,
      if (whiteName != $none) #whiteName: whiteName,
      if (blackName != $none) #blackName: blackName,
      if (whiteElo != $none) #whiteElo: whiteElo,
      if (blackElo != $none) #blackElo: blackElo,
    }),
  );
  @override
  GamebaseGameWithPgn $make(CopyWithData data) => GamebaseGameWithPgn(
    id: data.get(#id, or: $value.id),
    date: data.get(#date, or: $value.date),
    result: data.get(#result, or: $value.result),
    timeControl: data.get(#timeControl, or: $value.timeControl),
    whitePlayerId: data.get(#whitePlayerId, or: $value.whitePlayerId),
    blackPlayerId: data.get(#blackPlayerId, or: $value.blackPlayerId),
    data: data.get(#data, or: $value.data),
    pgn: data.get(#pgn, or: $value.pgn),
    eco: data.get(#eco, or: $value.eco),
    opening: data.get(#opening, or: $value.opening),
    variation: data.get(#variation, or: $value.variation),
    event: data.get(#event, or: $value.event),
    site: data.get(#site, or: $value.site),
    whiteName: data.get(#whiteName, or: $value.whiteName),
    blackName: data.get(#blackName, or: $value.blackName),
    whiteElo: data.get(#whiteElo, or: $value.whiteElo),
    blackElo: data.get(#blackElo, or: $value.blackElo),
  );

  @override
  GamebaseGameWithPgnCopyWith<$R2, GamebaseGameWithPgn, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _GamebaseGameWithPgnCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

