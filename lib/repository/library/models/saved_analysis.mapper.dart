// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'saved_analysis.dart';

class SavedAnalysisMapper extends ClassMapperBase<SavedAnalysis> {
  SavedAnalysisMapper._();

  static SavedAnalysisMapper? _instance;
  static SavedAnalysisMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = SavedAnalysisMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'SavedAnalysis';

  static String _$id(SavedAnalysis v) => v.id;
  static const Field<SavedAnalysis, String> _f$id = Field('id', _$id);
  static String _$userId(SavedAnalysis v) => v.userId;
  static const Field<SavedAnalysis, String> _f$userId = Field(
    'userId',
    _$userId,
  );
  static String? _$folderId(SavedAnalysis v) => v.folderId;
  static const Field<SavedAnalysis, String> _f$folderId = Field(
    'folderId',
    _$folderId,
    opt: true,
  );
  static String _$title(SavedAnalysis v) => v.title;
  static const Field<SavedAnalysis, String> _f$title = Field('title', _$title);
  static String? _$sourceGameId(SavedAnalysis v) => v.sourceGameId;
  static const Field<SavedAnalysis, String> _f$sourceGameId = Field(
    'sourceGameId',
    _$sourceGameId,
    opt: true,
  );
  static String? _$sourceTournamentId(SavedAnalysis v) => v.sourceTournamentId;
  static const Field<SavedAnalysis, String> _f$sourceTournamentId = Field(
    'sourceTournamentId',
    _$sourceTournamentId,
    opt: true,
  );
  static ChessGame _$chessGame(SavedAnalysis v) => v.chessGame;
  static const Field<SavedAnalysis, ChessGame> _f$chessGame = Field(
    'chessGame',
    _$chessGame,
  );
  static Map<String, dynamic> _$analysisState(SavedAnalysis v) =>
      v.analysisState;
  static const Field<SavedAnalysis, Map<String, dynamic>> _f$analysisState =
      Field('analysisState', _$analysisState);
  static Map<String, String> _$variationComments(SavedAnalysis v) =>
      v.variationComments;
  static const Field<SavedAnalysis, Map<String, String>> _f$variationComments =
      Field('variationComments', _$variationComments);
  static Map<String, List<int>> _$moveNags(SavedAnalysis v) => v.moveNags;
  static const Field<SavedAnalysis, Map<String, List<int>>> _f$moveNags = Field(
    'moveNags',
    _$moveNags,
    opt: true,
    def: const <String, List<int>>{},
  );
  static int _$lastViewedPosition(SavedAnalysis v) => v.lastViewedPosition;
  static const Field<SavedAnalysis, int> _f$lastViewedPosition = Field(
    'lastViewedPosition',
    _$lastViewedPosition,
  );
  static List<String> _$tags(SavedAnalysis v) => v.tags;
  static const Field<SavedAnalysis, List<String>> _f$tags = Field(
    'tags',
    _$tags,
  );
  static String? _$notes(SavedAnalysis v) => v.notes;
  static const Field<SavedAnalysis, String> _f$notes = Field(
    'notes',
    _$notes,
    opt: true,
  );
  static bool _$isFavorite(SavedAnalysis v) => v.isFavorite;
  static const Field<SavedAnalysis, bool> _f$isFavorite = Field(
    'isFavorite',
    _$isFavorite,
  );
  static DateTime _$createdAt(SavedAnalysis v) => v.createdAt;
  static const Field<SavedAnalysis, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );
  static DateTime _$updatedAt(SavedAnalysis v) => v.updatedAt;
  static const Field<SavedAnalysis, DateTime> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
  );
  static DateTime? _$lastOpenedAt(SavedAnalysis v) => v.lastOpenedAt;
  static const Field<SavedAnalysis, DateTime> _f$lastOpenedAt = Field(
    'lastOpenedAt',
    _$lastOpenedAt,
    opt: true,
  );

  @override
  final MappableFields<SavedAnalysis> fields = const {
    #id: _f$id,
    #userId: _f$userId,
    #folderId: _f$folderId,
    #title: _f$title,
    #sourceGameId: _f$sourceGameId,
    #sourceTournamentId: _f$sourceTournamentId,
    #chessGame: _f$chessGame,
    #analysisState: _f$analysisState,
    #variationComments: _f$variationComments,
    #moveNags: _f$moveNags,
    #lastViewedPosition: _f$lastViewedPosition,
    #tags: _f$tags,
    #notes: _f$notes,
    #isFavorite: _f$isFavorite,
    #createdAt: _f$createdAt,
    #updatedAt: _f$updatedAt,
    #lastOpenedAt: _f$lastOpenedAt,
  };

  static SavedAnalysis _instantiate(DecodingData data) {
    return SavedAnalysis(
      id: data.dec(_f$id),
      userId: data.dec(_f$userId),
      folderId: data.dec(_f$folderId),
      title: data.dec(_f$title),
      sourceGameId: data.dec(_f$sourceGameId),
      sourceTournamentId: data.dec(_f$sourceTournamentId),
      chessGame: data.dec(_f$chessGame),
      analysisState: data.dec(_f$analysisState),
      variationComments: data.dec(_f$variationComments),
      moveNags: data.dec(_f$moveNags),
      lastViewedPosition: data.dec(_f$lastViewedPosition),
      tags: data.dec(_f$tags),
      notes: data.dec(_f$notes),
      isFavorite: data.dec(_f$isFavorite),
      createdAt: data.dec(_f$createdAt),
      updatedAt: data.dec(_f$updatedAt),
      lastOpenedAt: data.dec(_f$lastOpenedAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static SavedAnalysis fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<SavedAnalysis>(map);
  }

  static SavedAnalysis fromJson(String json) {
    return ensureInitialized().decodeJson<SavedAnalysis>(json);
  }
}

mixin SavedAnalysisMappable {
  String toJson() {
    return SavedAnalysisMapper.ensureInitialized().encodeJson<SavedAnalysis>(
      this as SavedAnalysis,
    );
  }

  Map<String, dynamic> toMap() {
    return SavedAnalysisMapper.ensureInitialized().encodeMap<SavedAnalysis>(
      this as SavedAnalysis,
    );
  }

  SavedAnalysisCopyWith<SavedAnalysis, SavedAnalysis, SavedAnalysis>
  get copyWith => _SavedAnalysisCopyWithImpl<SavedAnalysis, SavedAnalysis>(
    this as SavedAnalysis,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return SavedAnalysisMapper.ensureInitialized().stringifyValue(
      this as SavedAnalysis,
    );
  }

  @override
  bool operator ==(Object other) {
    return SavedAnalysisMapper.ensureInitialized().equalsValue(
      this as SavedAnalysis,
      other,
    );
  }

  @override
  int get hashCode {
    return SavedAnalysisMapper.ensureInitialized().hashValue(
      this as SavedAnalysis,
    );
  }
}

extension SavedAnalysisValueCopy<$R, $Out>
    on ObjectCopyWith<$R, SavedAnalysis, $Out> {
  SavedAnalysisCopyWith<$R, SavedAnalysis, $Out> get $asSavedAnalysis =>
      $base.as((v, t, t2) => _SavedAnalysisCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class SavedAnalysisCopyWith<$R, $In extends SavedAnalysis, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  MapCopyWith<$R, String, dynamic, ObjectCopyWith<$R, dynamic, dynamic>>
  get analysisState;
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>
  get variationComments;
  MapCopyWith<$R, String, List<int>, ObjectCopyWith<$R, List<int>, List<int>>>
  get moveNags;
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get tags;
  $R call({
    String? id,
    String? userId,
    String? folderId,
    String? title,
    String? sourceGameId,
    String? sourceTournamentId,
    ChessGame? chessGame,
    Map<String, dynamic>? analysisState,
    Map<String, String>? variationComments,
    Map<String, List<int>>? moveNags,
    int? lastViewedPosition,
    List<String>? tags,
    String? notes,
    bool? isFavorite,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastOpenedAt,
  });
  SavedAnalysisCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _SavedAnalysisCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, SavedAnalysis, $Out>
    implements SavedAnalysisCopyWith<$R, SavedAnalysis, $Out> {
  _SavedAnalysisCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<SavedAnalysis> $mapper =
      SavedAnalysisMapper.ensureInitialized();
  @override
  MapCopyWith<$R, String, dynamic, ObjectCopyWith<$R, dynamic, dynamic>>
  get analysisState => MapCopyWith(
    $value.analysisState,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(analysisState: v),
  );
  @override
  MapCopyWith<$R, String, String, ObjectCopyWith<$R, String, String>>
  get variationComments => MapCopyWith(
    $value.variationComments,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(variationComments: v),
  );
  @override
  MapCopyWith<$R, String, List<int>, ObjectCopyWith<$R, List<int>, List<int>>>
  get moveNags => MapCopyWith(
    $value.moveNags,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(moveNags: v),
  );
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get tags =>
      ListCopyWith(
        $value.tags,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(tags: v),
      );
  @override
  $R call({
    String? id,
    String? userId,
    Object? folderId = $none,
    String? title,
    Object? sourceGameId = $none,
    Object? sourceTournamentId = $none,
    ChessGame? chessGame,
    Map<String, dynamic>? analysisState,
    Map<String, String>? variationComments,
    Map<String, List<int>>? moveNags,
    int? lastViewedPosition,
    List<String>? tags,
    Object? notes = $none,
    bool? isFavorite,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? lastOpenedAt = $none,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (userId != null) #userId: userId,
      if (folderId != $none) #folderId: folderId,
      if (title != null) #title: title,
      if (sourceGameId != $none) #sourceGameId: sourceGameId,
      if (sourceTournamentId != $none) #sourceTournamentId: sourceTournamentId,
      if (chessGame != null) #chessGame: chessGame,
      if (analysisState != null) #analysisState: analysisState,
      if (variationComments != null) #variationComments: variationComments,
      if (moveNags != null) #moveNags: moveNags,
      if (lastViewedPosition != null) #lastViewedPosition: lastViewedPosition,
      if (tags != null) #tags: tags,
      if (notes != $none) #notes: notes,
      if (isFavorite != null) #isFavorite: isFavorite,
      if (createdAt != null) #createdAt: createdAt,
      if (updatedAt != null) #updatedAt: updatedAt,
      if (lastOpenedAt != $none) #lastOpenedAt: lastOpenedAt,
    }),
  );
  @override
  SavedAnalysis $make(CopyWithData data) => SavedAnalysis(
    id: data.get(#id, or: $value.id),
    userId: data.get(#userId, or: $value.userId),
    folderId: data.get(#folderId, or: $value.folderId),
    title: data.get(#title, or: $value.title),
    sourceGameId: data.get(#sourceGameId, or: $value.sourceGameId),
    sourceTournamentId: data.get(
      #sourceTournamentId,
      or: $value.sourceTournamentId,
    ),
    chessGame: data.get(#chessGame, or: $value.chessGame),
    analysisState: data.get(#analysisState, or: $value.analysisState),
    variationComments: data.get(
      #variationComments,
      or: $value.variationComments,
    ),
    moveNags: data.get(#moveNags, or: $value.moveNags),
    lastViewedPosition: data.get(
      #lastViewedPosition,
      or: $value.lastViewedPosition,
    ),
    tags: data.get(#tags, or: $value.tags),
    notes: data.get(#notes, or: $value.notes),
    isFavorite: data.get(#isFavorite, or: $value.isFavorite),
    createdAt: data.get(#createdAt, or: $value.createdAt),
    updatedAt: data.get(#updatedAt, or: $value.updatedAt),
    lastOpenedAt: data.get(#lastOpenedAt, or: $value.lastOpenedAt),
  );

  @override
  SavedAnalysisCopyWith<$R2, SavedAnalysis, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _SavedAnalysisCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

