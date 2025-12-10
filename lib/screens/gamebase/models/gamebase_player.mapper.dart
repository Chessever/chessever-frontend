// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'gamebase_player.dart';

class PlayerGenderMapper extends EnumMapper<PlayerGender> {
  PlayerGenderMapper._();

  static PlayerGenderMapper? _instance;
  static PlayerGenderMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PlayerGenderMapper._());
    }
    return _instance!;
  }

  static PlayerGender fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  PlayerGender decode(dynamic value) {
    switch (value) {
      case 'MALE':
        return PlayerGender.male;
      case 'FEMALE':
        return PlayerGender.female;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(PlayerGender self) {
    switch (self) {
      case PlayerGender.male:
        return 'MALE';
      case PlayerGender.female:
        return 'FEMALE';
    }
  }
}

extension PlayerGenderMapperExtension on PlayerGender {
  dynamic toValue() {
    PlayerGenderMapper.ensureInitialized();
    return MapperContainer.globals.toValue<PlayerGender>(this);
  }
}

class GamebasePlayerMapper extends ClassMapperBase<GamebasePlayer> {
  GamebasePlayerMapper._();

  static GamebasePlayerMapper? _instance;
  static GamebasePlayerMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = GamebasePlayerMapper._());
      PlayerGenderMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'GamebasePlayer';

  static String _$id(GamebasePlayer v) => v.id;
  static const Field<GamebasePlayer, String> _f$id = Field('id', _$id);
  static String _$fideId(GamebasePlayer v) => v.fideId;
  static const Field<GamebasePlayer, String> _f$fideId = Field(
    'fideId',
    _$fideId,
  );
  static String _$name(GamebasePlayer v) => v.name;
  static const Field<GamebasePlayer, String> _f$name = Field('name', _$name);
  static PlayerGender _$gender(GamebasePlayer v) => v.gender;
  static const Field<GamebasePlayer, PlayerGender> _f$gender = Field(
    'gender',
    _$gender,
  );
  static String _$fed(GamebasePlayer v) => v.fed;
  static const Field<GamebasePlayer, String> _f$fed = Field('fed', _$fed);
  static String? _$title(GamebasePlayer v) => v.title;
  static const Field<GamebasePlayer, String> _f$title = Field(
    'title',
    _$title,
    opt: true,
  );
  static int? _$ratingClassical(GamebasePlayer v) => v.ratingClassical;
  static const Field<GamebasePlayer, int> _f$ratingClassical = Field(
    'ratingClassical',
    _$ratingClassical,
    opt: true,
  );
  static int? _$ratingRapid(GamebasePlayer v) => v.ratingRapid;
  static const Field<GamebasePlayer, int> _f$ratingRapid = Field(
    'ratingRapid',
    _$ratingRapid,
    opt: true,
  );
  static int? _$ratingBlitz(GamebasePlayer v) => v.ratingBlitz;
  static const Field<GamebasePlayer, int> _f$ratingBlitz = Field(
    'ratingBlitz',
    _$ratingBlitz,
    opt: true,
  );

  @override
  final MappableFields<GamebasePlayer> fields = const {
    #id: _f$id,
    #fideId: _f$fideId,
    #name: _f$name,
    #gender: _f$gender,
    #fed: _f$fed,
    #title: _f$title,
    #ratingClassical: _f$ratingClassical,
    #ratingRapid: _f$ratingRapid,
    #ratingBlitz: _f$ratingBlitz,
  };

  static GamebasePlayer _instantiate(DecodingData data) {
    return GamebasePlayer(
      id: data.dec(_f$id),
      fideId: data.dec(_f$fideId),
      name: data.dec(_f$name),
      gender: data.dec(_f$gender),
      fed: data.dec(_f$fed),
      title: data.dec(_f$title),
      ratingClassical: data.dec(_f$ratingClassical),
      ratingRapid: data.dec(_f$ratingRapid),
      ratingBlitz: data.dec(_f$ratingBlitz),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static GamebasePlayer fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<GamebasePlayer>(map);
  }

  static GamebasePlayer fromJson(String json) {
    return ensureInitialized().decodeJson<GamebasePlayer>(json);
  }
}

mixin GamebasePlayerMappable {
  String toJson() {
    return GamebasePlayerMapper.ensureInitialized().encodeJson<GamebasePlayer>(
      this as GamebasePlayer,
    );
  }

  Map<String, dynamic> toMap() {
    return GamebasePlayerMapper.ensureInitialized().encodeMap<GamebasePlayer>(
      this as GamebasePlayer,
    );
  }

  GamebasePlayerCopyWith<GamebasePlayer, GamebasePlayer, GamebasePlayer>
  get copyWith => _GamebasePlayerCopyWithImpl<GamebasePlayer, GamebasePlayer>(
    this as GamebasePlayer,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return GamebasePlayerMapper.ensureInitialized().stringifyValue(
      this as GamebasePlayer,
    );
  }

  @override
  bool operator ==(Object other) {
    return GamebasePlayerMapper.ensureInitialized().equalsValue(
      this as GamebasePlayer,
      other,
    );
  }

  @override
  int get hashCode {
    return GamebasePlayerMapper.ensureInitialized().hashValue(
      this as GamebasePlayer,
    );
  }
}

extension GamebasePlayerValueCopy<$R, $Out>
    on ObjectCopyWith<$R, GamebasePlayer, $Out> {
  GamebasePlayerCopyWith<$R, GamebasePlayer, $Out> get $asGamebasePlayer =>
      $base.as((v, t, t2) => _GamebasePlayerCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class GamebasePlayerCopyWith<$R, $In extends GamebasePlayer, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? id,
    String? fideId,
    String? name,
    PlayerGender? gender,
    String? fed,
    String? title,
    int? ratingClassical,
    int? ratingRapid,
    int? ratingBlitz,
  });
  GamebasePlayerCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _GamebasePlayerCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, GamebasePlayer, $Out>
    implements GamebasePlayerCopyWith<$R, GamebasePlayer, $Out> {
  _GamebasePlayerCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<GamebasePlayer> $mapper =
      GamebasePlayerMapper.ensureInitialized();
  @override
  $R call({
    String? id,
    String? fideId,
    String? name,
    PlayerGender? gender,
    String? fed,
    Object? title = $none,
    Object? ratingClassical = $none,
    Object? ratingRapid = $none,
    Object? ratingBlitz = $none,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (fideId != null) #fideId: fideId,
      if (name != null) #name: name,
      if (gender != null) #gender: gender,
      if (fed != null) #fed: fed,
      if (title != $none) #title: title,
      if (ratingClassical != $none) #ratingClassical: ratingClassical,
      if (ratingRapid != $none) #ratingRapid: ratingRapid,
      if (ratingBlitz != $none) #ratingBlitz: ratingBlitz,
    }),
  );
  @override
  GamebasePlayer $make(CopyWithData data) => GamebasePlayer(
    id: data.get(#id, or: $value.id),
    fideId: data.get(#fideId, or: $value.fideId),
    name: data.get(#name, or: $value.name),
    gender: data.get(#gender, or: $value.gender),
    fed: data.get(#fed, or: $value.fed),
    title: data.get(#title, or: $value.title),
    ratingClassical: data.get(#ratingClassical, or: $value.ratingClassical),
    ratingRapid: data.get(#ratingRapid, or: $value.ratingRapid),
    ratingBlitz: data.get(#ratingBlitz, or: $value.ratingBlitz),
  );

  @override
  GamebasePlayerCopyWith<$R2, GamebasePlayer, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _GamebasePlayerCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

