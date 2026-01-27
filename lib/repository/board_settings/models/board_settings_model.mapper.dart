// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'board_settings_model.dart';

class BoardSettingsModelMapper extends ClassMapperBase<BoardSettingsModel> {
  BoardSettingsModelMapper._();

  static BoardSettingsModelMapper? _instance;
  static BoardSettingsModelMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = BoardSettingsModelMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'BoardSettingsModel';

  static String _$id(BoardSettingsModel v) => v.id;
  static const Field<BoardSettingsModel, String> _f$id = Field('id', _$id);
  static String _$userId(BoardSettingsModel v) => v.userId;
  static const Field<BoardSettingsModel, String> _f$userId = Field(
    'userId',
    _$userId,
  );
  static int _$boardColorIndex(BoardSettingsModel v) => v.boardColorIndex;
  static const Field<BoardSettingsModel, int> _f$boardColorIndex = Field(
    'boardColorIndex',
    _$boardColorIndex,
  );
  static int _$boardThemeIndex(BoardSettingsModel v) => v.boardThemeIndex;
  static const Field<BoardSettingsModel, int> _f$boardThemeIndex = Field(
    'boardThemeIndex',
    _$boardThemeIndex,
  );
  static bool _$showEvaluationBar(BoardSettingsModel v) => v.showEvaluationBar;
  static const Field<BoardSettingsModel, bool> _f$showEvaluationBar = Field(
    'showEvaluationBar',
    _$showEvaluationBar,
  );
  static bool _$soundEnabled(BoardSettingsModel v) => v.soundEnabled;
  static const Field<BoardSettingsModel, bool> _f$soundEnabled = Field(
    'soundEnabled',
    _$soundEnabled,
  );
  static bool _$chatEnabled(BoardSettingsModel v) => v.chatEnabled;
  static const Field<BoardSettingsModel, bool> _f$chatEnabled = Field(
    'chatEnabled',
    _$chatEnabled,
  );
  static int _$pieceStyleIndex(BoardSettingsModel v) => v.pieceStyleIndex;
  static const Field<BoardSettingsModel, int> _f$pieceStyleIndex = Field(
    'pieceStyleIndex',
    _$pieceStyleIndex,
  );
  static int _$gamesListViewModeIndex(BoardSettingsModel v) =>
      v.gamesListViewModeIndex;
  static const Field<BoardSettingsModel, int> _f$gamesListViewModeIndex = Field(
    'gamesListViewModeIndex',
    _$gamesListViewModeIndex,
  );
  static bool _$useFigurine(BoardSettingsModel v) => v.useFigurine;
  static const Field<BoardSettingsModel, bool> _f$useFigurine = Field(
    'useFigurine',
    _$useFigurine,
  );
  static DateTime _$createdAt(BoardSettingsModel v) => v.createdAt;
  static const Field<BoardSettingsModel, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );
  static DateTime _$updatedAt(BoardSettingsModel v) => v.updatedAt;
  static const Field<BoardSettingsModel, DateTime> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
  );

  @override
  final MappableFields<BoardSettingsModel> fields = const {
    #id: _f$id,
    #userId: _f$userId,
    #boardColorIndex: _f$boardColorIndex,
    #boardThemeIndex: _f$boardThemeIndex,
    #showEvaluationBar: _f$showEvaluationBar,
    #soundEnabled: _f$soundEnabled,
    #chatEnabled: _f$chatEnabled,
    #pieceStyleIndex: _f$pieceStyleIndex,
    #gamesListViewModeIndex: _f$gamesListViewModeIndex,
    #useFigurine: _f$useFigurine,
    #createdAt: _f$createdAt,
    #updatedAt: _f$updatedAt,
  };

  static BoardSettingsModel _instantiate(DecodingData data) {
    return BoardSettingsModel(
      id: data.dec(_f$id),
      userId: data.dec(_f$userId),
      boardColorIndex: data.dec(_f$boardColorIndex),
      boardThemeIndex: data.dec(_f$boardThemeIndex),
      showEvaluationBar: data.dec(_f$showEvaluationBar),
      soundEnabled: data.dec(_f$soundEnabled),
      chatEnabled: data.dec(_f$chatEnabled),
      pieceStyleIndex: data.dec(_f$pieceStyleIndex),
      gamesListViewModeIndex: data.dec(_f$gamesListViewModeIndex),
      useFigurine: data.dec(_f$useFigurine),
      createdAt: data.dec(_f$createdAt),
      updatedAt: data.dec(_f$updatedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static BoardSettingsModel fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<BoardSettingsModel>(map);
  }

  static BoardSettingsModel fromJson(String json) {
    return ensureInitialized().decodeJson<BoardSettingsModel>(json);
  }
}

mixin BoardSettingsModelMappable {
  String toJson() {
    return BoardSettingsModelMapper.ensureInitialized()
        .encodeJson<BoardSettingsModel>(this as BoardSettingsModel);
  }

  Map<String, dynamic> toMap() {
    return BoardSettingsModelMapper.ensureInitialized()
        .encodeMap<BoardSettingsModel>(this as BoardSettingsModel);
  }

  BoardSettingsModelCopyWith<
    BoardSettingsModel,
    BoardSettingsModel,
    BoardSettingsModel
  >
  get copyWith =>
      _BoardSettingsModelCopyWithImpl<BoardSettingsModel, BoardSettingsModel>(
        this as BoardSettingsModel,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return BoardSettingsModelMapper.ensureInitialized().stringifyValue(
      this as BoardSettingsModel,
    );
  }

  @override
  bool operator ==(Object other) {
    return BoardSettingsModelMapper.ensureInitialized().equalsValue(
      this as BoardSettingsModel,
      other,
    );
  }

  @override
  int get hashCode {
    return BoardSettingsModelMapper.ensureInitialized().hashValue(
      this as BoardSettingsModel,
    );
  }
}

extension BoardSettingsModelValueCopy<$R, $Out>
    on ObjectCopyWith<$R, BoardSettingsModel, $Out> {
  BoardSettingsModelCopyWith<$R, BoardSettingsModel, $Out>
  get $asBoardSettingsModel => $base.as(
    (v, t, t2) => _BoardSettingsModelCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class BoardSettingsModelCopyWith<
  $R,
  $In extends BoardSettingsModel,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? id,
    String? userId,
    int? boardColorIndex,
    int? boardThemeIndex,
    bool? showEvaluationBar,
    bool? soundEnabled,
    bool? chatEnabled,
    int? pieceStyleIndex,
    int? gamesListViewModeIndex,
    bool? useFigurine,
    DateTime? createdAt,
    DateTime? updatedAt,
  });
  BoardSettingsModelCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _BoardSettingsModelCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, BoardSettingsModel, $Out>
    implements BoardSettingsModelCopyWith<$R, BoardSettingsModel, $Out> {
  _BoardSettingsModelCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<BoardSettingsModel> $mapper =
      BoardSettingsModelMapper.ensureInitialized();
  @override
  $R call({
    String? id,
    String? userId,
    int? boardColorIndex,
    int? boardThemeIndex,
    bool? showEvaluationBar,
    bool? soundEnabled,
    bool? chatEnabled,
    int? pieceStyleIndex,
    int? gamesListViewModeIndex,
    bool? useFigurine,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (userId != null) #userId: userId,
      if (boardColorIndex != null) #boardColorIndex: boardColorIndex,
      if (boardThemeIndex != null) #boardThemeIndex: boardThemeIndex,
      if (showEvaluationBar != null) #showEvaluationBar: showEvaluationBar,
      if (soundEnabled != null) #soundEnabled: soundEnabled,
      if (chatEnabled != null) #chatEnabled: chatEnabled,
      if (pieceStyleIndex != null) #pieceStyleIndex: pieceStyleIndex,
      if (gamesListViewModeIndex != null)
        #gamesListViewModeIndex: gamesListViewModeIndex,
      if (useFigurine != null) #useFigurine: useFigurine,
      if (createdAt != null) #createdAt: createdAt,
      if (updatedAt != null) #updatedAt: updatedAt,
    }),
  );
  @override
  BoardSettingsModel $make(CopyWithData data) => BoardSettingsModel(
    id: data.get(#id, or: $value.id),
    userId: data.get(#userId, or: $value.userId),
    boardColorIndex: data.get(#boardColorIndex, or: $value.boardColorIndex),
    boardThemeIndex: data.get(#boardThemeIndex, or: $value.boardThemeIndex),
    showEvaluationBar: data.get(
      #showEvaluationBar,
      or: $value.showEvaluationBar,
    ),
    soundEnabled: data.get(#soundEnabled, or: $value.soundEnabled),
    chatEnabled: data.get(#chatEnabled, or: $value.chatEnabled),
    pieceStyleIndex: data.get(#pieceStyleIndex, or: $value.pieceStyleIndex),
    gamesListViewModeIndex: data.get(
      #gamesListViewModeIndex,
      or: $value.gamesListViewModeIndex,
    ),
    useFigurine: data.get(#useFigurine, or: $value.useFigurine),
    createdAt: data.get(#createdAt, or: $value.createdAt),
    updatedAt: data.get(#updatedAt, or: $value.updatedAt),
  );

  @override
  BoardSettingsModelCopyWith<$R2, BoardSettingsModel, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _BoardSettingsModelCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

