// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'move_aggregate.dart';

class MoveAggregateMapper extends ClassMapperBase<MoveAggregate> {
  MoveAggregateMapper._();

  static MoveAggregateMapper? _instance;
  static MoveAggregateMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = MoveAggregateMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'MoveAggregate';

  static String _$uci(MoveAggregate v) => v.uci;
  static const Field<MoveAggregate, String> _f$uci = Field('uci', _$uci);
  static int _$white(MoveAggregate v) => v.white;
  static const Field<MoveAggregate, int> _f$white = Field('white', _$white);
  static int _$black(MoveAggregate v) => v.black;
  static const Field<MoveAggregate, int> _f$black = Field('black', _$black);
  static int _$draws(MoveAggregate v) => v.draws;
  static const Field<MoveAggregate, int> _f$draws = Field('draws', _$draws);
  static int _$total(MoveAggregate v) => v.total;
  static const Field<MoveAggregate, int> _f$total = Field('total', _$total);
  static String? _$gameId(MoveAggregate v) => v.gameId;
  static const Field<MoveAggregate, String> _f$gameId = Field(
    'gameId',
    _$gameId,
    opt: true,
  );
  static DateTime? _$lastPlayed(MoveAggregate v) => v.lastPlayed;
  static const Field<MoveAggregate, DateTime> _f$lastPlayed = Field(
    'lastPlayed',
    _$lastPlayed,
    opt: true,
  );

  @override
  final MappableFields<MoveAggregate> fields = const {
    #uci: _f$uci,
    #white: _f$white,
    #black: _f$black,
    #draws: _f$draws,
    #total: _f$total,
    #gameId: _f$gameId,
    #lastPlayed: _f$lastPlayed,
  };

  static MoveAggregate _instantiate(DecodingData data) {
    return MoveAggregate(
      uci: data.dec(_f$uci),
      white: data.dec(_f$white),
      black: data.dec(_f$black),
      draws: data.dec(_f$draws),
      total: data.dec(_f$total),
      gameId: data.dec(_f$gameId),
      lastPlayed: data.dec(_f$lastPlayed),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static MoveAggregate fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<MoveAggregate>(map);
  }

  static MoveAggregate fromJson(String json) {
    return ensureInitialized().decodeJson<MoveAggregate>(json);
  }
}

mixin MoveAggregateMappable {
  String toJson() {
    return MoveAggregateMapper.ensureInitialized().encodeJson<MoveAggregate>(
      this as MoveAggregate,
    );
  }

  Map<String, dynamic> toMap() {
    return MoveAggregateMapper.ensureInitialized().encodeMap<MoveAggregate>(
      this as MoveAggregate,
    );
  }

  MoveAggregateCopyWith<MoveAggregate, MoveAggregate, MoveAggregate>
  get copyWith => _MoveAggregateCopyWithImpl<MoveAggregate, MoveAggregate>(
    this as MoveAggregate,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return MoveAggregateMapper.ensureInitialized().stringifyValue(
      this as MoveAggregate,
    );
  }

  @override
  bool operator ==(Object other) {
    return MoveAggregateMapper.ensureInitialized().equalsValue(
      this as MoveAggregate,
      other,
    );
  }

  @override
  int get hashCode {
    return MoveAggregateMapper.ensureInitialized().hashValue(
      this as MoveAggregate,
    );
  }
}

extension MoveAggregateValueCopy<$R, $Out>
    on ObjectCopyWith<$R, MoveAggregate, $Out> {
  MoveAggregateCopyWith<$R, MoveAggregate, $Out> get $asMoveAggregate =>
      $base.as((v, t, t2) => _MoveAggregateCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class MoveAggregateCopyWith<$R, $In extends MoveAggregate, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? uci,
    int? white,
    int? black,
    int? draws,
    int? total,
    String? gameId,
    DateTime? lastPlayed,
  });
  MoveAggregateCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _MoveAggregateCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, MoveAggregate, $Out>
    implements MoveAggregateCopyWith<$R, MoveAggregate, $Out> {
  _MoveAggregateCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<MoveAggregate> $mapper =
      MoveAggregateMapper.ensureInitialized();
  @override
  $R call({
    String? uci,
    int? white,
    int? black,
    int? draws,
    int? total,
    Object? gameId = $none,
    Object? lastPlayed = $none,
  }) => $apply(
    FieldCopyWithData({
      if (uci != null) #uci: uci,
      if (white != null) #white: white,
      if (black != null) #black: black,
      if (draws != null) #draws: draws,
      if (total != null) #total: total,
      if (gameId != $none) #gameId: gameId,
      if (lastPlayed != $none) #lastPlayed: lastPlayed,
    }),
  );
  @override
  MoveAggregate $make(CopyWithData data) => MoveAggregate(
    uci: data.get(#uci, or: $value.uci),
    white: data.get(#white, or: $value.white),
    black: data.get(#black, or: $value.black),
    draws: data.get(#draws, or: $value.draws),
    total: data.get(#total, or: $value.total),
    gameId: data.get(#gameId, or: $value.gameId),
    lastPlayed: data.get(#lastPlayed, or: $value.lastPlayed),
  );

  @override
  MoveAggregateCopyWith<$R2, MoveAggregate, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _MoveAggregateCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

