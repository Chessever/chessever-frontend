// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'engine_settings_model.dart';

class EngineSettingsModelMapper extends ClassMapperBase<EngineSettingsModel> {
  EngineSettingsModelMapper._();

  static EngineSettingsModelMapper? _instance;
  static EngineSettingsModelMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = EngineSettingsModelMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'EngineSettingsModel';

  static String _$id(EngineSettingsModel v) => v.id;
  static const Field<EngineSettingsModel, String> _f$id = Field('id', _$id);
  static String _$userId(EngineSettingsModel v) => v.userId;
  static const Field<EngineSettingsModel, String> _f$userId = Field(
    'userId',
    _$userId,
  );
  static bool _$showEngineGauge(EngineSettingsModel v) => v.showEngineGauge;
  static const Field<EngineSettingsModel, bool> _f$showEngineGauge = Field(
    'showEngineGauge',
    _$showEngineGauge,
  );
  static bool _$showDepthOverlay(EngineSettingsModel v) => v.showDepthOverlay;
  static const Field<EngineSettingsModel, bool> _f$showDepthOverlay = Field(
    'showDepthOverlay',
    _$showDepthOverlay,
  );
  static bool _$showPvArrows(EngineSettingsModel v) => v.showPvArrows;
  static const Field<EngineSettingsModel, bool> _f$showPvArrows = Field(
    'showPvArrows',
    _$showPvArrows,
  );
  static bool _$showEngineAnalysis(EngineSettingsModel v) =>
      v.showEngineAnalysis;
  static const Field<EngineSettingsModel, bool> _f$showEngineAnalysis = Field(
    'showEngineAnalysis',
    _$showEngineAnalysis,
  );
  static int _$searchTimeIndex(EngineSettingsModel v) => v.searchTimeIndex;
  static const Field<EngineSettingsModel, int> _f$searchTimeIndex = Field(
    'searchTimeIndex',
    _$searchTimeIndex,
  );
  static int _$principalVariationIndex(EngineSettingsModel v) =>
      v.principalVariationIndex;
  static const Field<EngineSettingsModel, int> _f$principalVariationIndex =
      Field('principalVariationIndex', _$principalVariationIndex);
  static int _$maxArrowsOnBoard(EngineSettingsModel v) => v.maxArrowsOnBoard;
  static const Field<EngineSettingsModel, int> _f$maxArrowsOnBoard = Field(
    'maxArrowsOnBoard',
    _$maxArrowsOnBoard,
  );
  static DateTime _$createdAt(EngineSettingsModel v) => v.createdAt;
  static const Field<EngineSettingsModel, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );
  static DateTime _$updatedAt(EngineSettingsModel v) => v.updatedAt;
  static const Field<EngineSettingsModel, DateTime> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
  );

  @override
  final MappableFields<EngineSettingsModel> fields = const {
    #id: _f$id,
    #userId: _f$userId,
    #showEngineGauge: _f$showEngineGauge,
    #showDepthOverlay: _f$showDepthOverlay,
    #showPvArrows: _f$showPvArrows,
    #showEngineAnalysis: _f$showEngineAnalysis,
    #searchTimeIndex: _f$searchTimeIndex,
    #principalVariationIndex: _f$principalVariationIndex,
    #maxArrowsOnBoard: _f$maxArrowsOnBoard,
    #createdAt: _f$createdAt,
    #updatedAt: _f$updatedAt,
  };

  static EngineSettingsModel _instantiate(DecodingData data) {
    return EngineSettingsModel(
      id: data.dec(_f$id),
      userId: data.dec(_f$userId),
      showEngineGauge: data.dec(_f$showEngineGauge),
      showDepthOverlay: data.dec(_f$showDepthOverlay),
      showPvArrows: data.dec(_f$showPvArrows),
      showEngineAnalysis: data.dec(_f$showEngineAnalysis),
      searchTimeIndex: data.dec(_f$searchTimeIndex),
      principalVariationIndex: data.dec(_f$principalVariationIndex),
      maxArrowsOnBoard: data.dec(_f$maxArrowsOnBoard),
      createdAt: data.dec(_f$createdAt),
      updatedAt: data.dec(_f$updatedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static EngineSettingsModel fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<EngineSettingsModel>(map);
  }

  static EngineSettingsModel fromJson(String json) {
    return ensureInitialized().decodeJson<EngineSettingsModel>(json);
  }
}

mixin EngineSettingsModelMappable {
  String toJson() {
    return EngineSettingsModelMapper.ensureInitialized()
        .encodeJson<EngineSettingsModel>(this as EngineSettingsModel);
  }

  Map<String, dynamic> toMap() {
    return EngineSettingsModelMapper.ensureInitialized()
        .encodeMap<EngineSettingsModel>(this as EngineSettingsModel);
  }

  EngineSettingsModelCopyWith<
    EngineSettingsModel,
    EngineSettingsModel,
    EngineSettingsModel
  >
  get copyWith =>
      _EngineSettingsModelCopyWithImpl<
        EngineSettingsModel,
        EngineSettingsModel
      >(this as EngineSettingsModel, $identity, $identity);
  @override
  String toString() {
    return EngineSettingsModelMapper.ensureInitialized().stringifyValue(
      this as EngineSettingsModel,
    );
  }

  @override
  bool operator ==(Object other) {
    return EngineSettingsModelMapper.ensureInitialized().equalsValue(
      this as EngineSettingsModel,
      other,
    );
  }

  @override
  int get hashCode {
    return EngineSettingsModelMapper.ensureInitialized().hashValue(
      this as EngineSettingsModel,
    );
  }
}

extension EngineSettingsModelValueCopy<$R, $Out>
    on ObjectCopyWith<$R, EngineSettingsModel, $Out> {
  EngineSettingsModelCopyWith<$R, EngineSettingsModel, $Out>
  get $asEngineSettingsModel => $base.as(
    (v, t, t2) => _EngineSettingsModelCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class EngineSettingsModelCopyWith<
  $R,
  $In extends EngineSettingsModel,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? id,
    String? userId,
    bool? showEngineGauge,
    bool? showDepthOverlay,
    bool? showPvArrows,
    bool? showEngineAnalysis,
    int? searchTimeIndex,
    int? principalVariationIndex,
    int? maxArrowsOnBoard,
    DateTime? createdAt,
    DateTime? updatedAt,
  });
  EngineSettingsModelCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _EngineSettingsModelCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, EngineSettingsModel, $Out>
    implements EngineSettingsModelCopyWith<$R, EngineSettingsModel, $Out> {
  _EngineSettingsModelCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<EngineSettingsModel> $mapper =
      EngineSettingsModelMapper.ensureInitialized();
  @override
  $R call({
    String? id,
    String? userId,
    bool? showEngineGauge,
    bool? showDepthOverlay,
    bool? showPvArrows,
    bool? showEngineAnalysis,
    int? searchTimeIndex,
    int? principalVariationIndex,
    int? maxArrowsOnBoard,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (userId != null) #userId: userId,
      if (showEngineGauge != null) #showEngineGauge: showEngineGauge,
      if (showDepthOverlay != null) #showDepthOverlay: showDepthOverlay,
      if (showPvArrows != null) #showPvArrows: showPvArrows,
      if (showEngineAnalysis != null) #showEngineAnalysis: showEngineAnalysis,
      if (searchTimeIndex != null) #searchTimeIndex: searchTimeIndex,
      if (principalVariationIndex != null)
        #principalVariationIndex: principalVariationIndex,
      if (maxArrowsOnBoard != null) #maxArrowsOnBoard: maxArrowsOnBoard,
      if (createdAt != null) #createdAt: createdAt,
      if (updatedAt != null) #updatedAt: updatedAt,
    }),
  );
  @override
  EngineSettingsModel $make(CopyWithData data) => EngineSettingsModel(
    id: data.get(#id, or: $value.id),
    userId: data.get(#userId, or: $value.userId),
    showEngineGauge: data.get(#showEngineGauge, or: $value.showEngineGauge),
    showDepthOverlay: data.get(#showDepthOverlay, or: $value.showDepthOverlay),
    showPvArrows: data.get(#showPvArrows, or: $value.showPvArrows),
    showEngineAnalysis: data.get(
      #showEngineAnalysis,
      or: $value.showEngineAnalysis,
    ),
    searchTimeIndex: data.get(#searchTimeIndex, or: $value.searchTimeIndex),
    principalVariationIndex: data.get(
      #principalVariationIndex,
      or: $value.principalVariationIndex,
    ),
    maxArrowsOnBoard: data.get(#maxArrowsOnBoard, or: $value.maxArrowsOnBoard),
    createdAt: data.get(#createdAt, or: $value.createdAt),
    updatedAt: data.get(#updatedAt, or: $value.updatedAt),
  );

  @override
  EngineSettingsModelCopyWith<$R2, EngineSettingsModel, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _EngineSettingsModelCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

