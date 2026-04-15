// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'gamebase_explorer_state.dart';

class GamebaseFiltersMapper extends ClassMapperBase<GamebaseFilters> {
  GamebaseFiltersMapper._();

  static GamebaseFiltersMapper? _instance;
  static GamebaseFiltersMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = GamebaseFiltersMapper._());
      TimeControlMapper.ensureInitialized();
      GamebasePlayerMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'GamebaseFilters';

  static List<TimeControl> _$timeControls(GamebaseFilters v) => v.timeControls;
  static const Field<GamebaseFilters, List<TimeControl>> _f$timeControls =
      Field('timeControls', _$timeControls, opt: true, def: const []);
  static int? _$minRating(GamebaseFilters v) => v.minRating;
  static const Field<GamebaseFilters, int> _f$minRating = Field(
    'minRating',
    _$minRating,
    opt: true,
  );
  static int? _$maxRating(GamebaseFilters v) => v.maxRating;
  static const Field<GamebaseFilters, int> _f$maxRating = Field(
    'maxRating',
    _$maxRating,
    opt: true,
  );
  static List<String> _$playerIds(GamebaseFilters v) => v.playerIds;
  static const Field<GamebaseFilters, List<String>> _f$playerIds = Field(
    'playerIds',
    _$playerIds,
    opt: true,
    def: const [],
  );
  static List<GamebasePlayer> _$selectedPlayers(GamebaseFilters v) =>
      v.selectedPlayers;
  static const Field<GamebaseFilters, List<GamebasePlayer>> _f$selectedPlayers =
      Field('selectedPlayers', _$selectedPlayers, opt: true, def: const []);
  static GamebasePlayerColor? _$playerColor(GamebaseFilters v) => v.playerColor;
  static const Field<GamebaseFilters, GamebasePlayerColor> _f$playerColor =
      Field('playerColor', _$playerColor, opt: true);
  static GamebaseGameResult? _$gameResult(GamebaseFilters v) => v.gameResult;
  static const Field<GamebaseFilters, GamebaseGameResult> _f$gameResult = Field(
    'gameResult',
    _$gameResult,
    opt: true,
  );
  static bool? _$isOnline(GamebaseFilters v) => v.isOnline;
  static const Field<GamebaseFilters, bool> _f$isOnline = Field(
    'isOnline',
    _$isOnline,
    opt: true,
  );
  static int? _$yearFrom(GamebaseFilters v) => v.yearFrom;
  static const Field<GamebaseFilters, int> _f$yearFrom = Field(
    'yearFrom',
    _$yearFrom,
    opt: true,
  );
  static int? _$yearTo(GamebaseFilters v) => v.yearTo;
  static const Field<GamebaseFilters, int> _f$yearTo = Field(
    'yearTo',
    _$yearTo,
    opt: true,
  );
  static GamebaseSortField _$sortBy(GamebaseFilters v) => v.sortBy;
  static const Field<GamebaseFilters, GamebaseSortField> _f$sortBy = Field(
    'sortBy',
    _$sortBy,
    opt: true,
    def: GamebaseSortField.date,
  );
  static GamebaseSortDirection _$sortDirection(GamebaseFilters v) =>
      v.sortDirection;
  static const Field<GamebaseFilters, GamebaseSortDirection> _f$sortDirection =
      Field(
        'sortDirection',
        _$sortDirection,
        opt: true,
        def: GamebaseSortDirection.desc,
      );

  @override
  final MappableFields<GamebaseFilters> fields = const {
    #timeControls: _f$timeControls,
    #minRating: _f$minRating,
    #maxRating: _f$maxRating,
    #playerIds: _f$playerIds,
    #selectedPlayers: _f$selectedPlayers,
    #playerColor: _f$playerColor,
    #gameResult: _f$gameResult,
    #isOnline: _f$isOnline,
    #yearFrom: _f$yearFrom,
    #yearTo: _f$yearTo,
    #sortBy: _f$sortBy,
    #sortDirection: _f$sortDirection,
  };

  static GamebaseFilters _instantiate(DecodingData data) {
    return GamebaseFilters(
      timeControls: data.dec(_f$timeControls),
      minRating: data.dec(_f$minRating),
      maxRating: data.dec(_f$maxRating),
      playerIds: data.dec(_f$playerIds),
      selectedPlayers: data.dec(_f$selectedPlayers),
      playerColor: data.dec(_f$playerColor),
      gameResult: data.dec(_f$gameResult),
      isOnline: data.dec(_f$isOnline),
      yearFrom: data.dec(_f$yearFrom),
      yearTo: data.dec(_f$yearTo),
      sortBy: data.dec(_f$sortBy),
      sortDirection: data.dec(_f$sortDirection),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static GamebaseFilters fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<GamebaseFilters>(map);
  }

  static GamebaseFilters fromJson(String json) {
    return ensureInitialized().decodeJson<GamebaseFilters>(json);
  }
}

mixin GamebaseFiltersMappable {
  String toJson() {
    return GamebaseFiltersMapper.ensureInitialized()
        .encodeJson<GamebaseFilters>(this as GamebaseFilters);
  }

  Map<String, dynamic> toMap() {
    return GamebaseFiltersMapper.ensureInitialized().encodeMap<GamebaseFilters>(
      this as GamebaseFilters,
    );
  }

  GamebaseFiltersCopyWith<GamebaseFilters, GamebaseFilters, GamebaseFilters>
  get copyWith =>
      _GamebaseFiltersCopyWithImpl<GamebaseFilters, GamebaseFilters>(
        this as GamebaseFilters,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return GamebaseFiltersMapper.ensureInitialized().stringifyValue(
      this as GamebaseFilters,
    );
  }

  @override
  bool operator ==(Object other) {
    return GamebaseFiltersMapper.ensureInitialized().equalsValue(
      this as GamebaseFilters,
      other,
    );
  }

  @override
  int get hashCode {
    return GamebaseFiltersMapper.ensureInitialized().hashValue(
      this as GamebaseFilters,
    );
  }
}

extension GamebaseFiltersValueCopy<$R, $Out>
    on ObjectCopyWith<$R, GamebaseFilters, $Out> {
  GamebaseFiltersCopyWith<$R, GamebaseFilters, $Out> get $asGamebaseFilters =>
      $base.as((v, t, t2) => _GamebaseFiltersCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class GamebaseFiltersCopyWith<$R, $In extends GamebaseFilters, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, TimeControl, ObjectCopyWith<$R, TimeControl, TimeControl>>
  get timeControls;
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get playerIds;
  ListCopyWith<
    $R,
    GamebasePlayer,
    GamebasePlayerCopyWith<$R, GamebasePlayer, GamebasePlayer>
  >
  get selectedPlayers;
  $R call({
    List<TimeControl>? timeControls,
    int? minRating,
    int? maxRating,
    List<String>? playerIds,
    List<GamebasePlayer>? selectedPlayers,
    GamebasePlayerColor? playerColor,
    GamebaseGameResult? gameResult,
    bool? isOnline,
    int? yearFrom,
    int? yearTo,
    GamebaseSortField? sortBy,
    GamebaseSortDirection? sortDirection,
  });
  GamebaseFiltersCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _GamebaseFiltersCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, GamebaseFilters, $Out>
    implements GamebaseFiltersCopyWith<$R, GamebaseFilters, $Out> {
  _GamebaseFiltersCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<GamebaseFilters> $mapper =
      GamebaseFiltersMapper.ensureInitialized();
  @override
  ListCopyWith<$R, TimeControl, ObjectCopyWith<$R, TimeControl, TimeControl>>
  get timeControls => ListCopyWith(
    $value.timeControls,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(timeControls: v),
  );
  @override
  ListCopyWith<$R, String, ObjectCopyWith<$R, String, String>> get playerIds =>
      ListCopyWith(
        $value.playerIds,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(playerIds: v),
      );
  @override
  ListCopyWith<
    $R,
    GamebasePlayer,
    GamebasePlayerCopyWith<$R, GamebasePlayer, GamebasePlayer>
  >
  get selectedPlayers => ListCopyWith(
    $value.selectedPlayers,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(selectedPlayers: v),
  );
  @override
  $R call({
    List<TimeControl>? timeControls,
    Object? minRating = $none,
    Object? maxRating = $none,
    List<String>? playerIds,
    List<GamebasePlayer>? selectedPlayers,
    Object? playerColor = $none,
    Object? gameResult = $none,
    Object? isOnline = $none,
    Object? yearFrom = $none,
    Object? yearTo = $none,
    GamebaseSortField? sortBy,
    GamebaseSortDirection? sortDirection,
  }) => $apply(
    FieldCopyWithData({
      if (timeControls != null) #timeControls: timeControls,
      if (minRating != $none) #minRating: minRating,
      if (maxRating != $none) #maxRating: maxRating,
      if (playerIds != null) #playerIds: playerIds,
      if (selectedPlayers != null) #selectedPlayers: selectedPlayers,
      if (playerColor != $none) #playerColor: playerColor,
      if (gameResult != $none) #gameResult: gameResult,
      if (isOnline != $none) #isOnline: isOnline,
      if (yearFrom != $none) #yearFrom: yearFrom,
      if (yearTo != $none) #yearTo: yearTo,
      if (sortBy != null) #sortBy: sortBy,
      if (sortDirection != null) #sortDirection: sortDirection,
    }),
  );
  @override
  GamebaseFilters $make(CopyWithData data) => GamebaseFilters(
    timeControls: data.get(#timeControls, or: $value.timeControls),
    minRating: data.get(#minRating, or: $value.minRating),
    maxRating: data.get(#maxRating, or: $value.maxRating),
    playerIds: data.get(#playerIds, or: $value.playerIds),
    selectedPlayers: data.get(#selectedPlayers, or: $value.selectedPlayers),
    playerColor: data.get(#playerColor, or: $value.playerColor),
    gameResult: data.get(#gameResult, or: $value.gameResult),
    isOnline: data.get(#isOnline, or: $value.isOnline),
    yearFrom: data.get(#yearFrom, or: $value.yearFrom),
    yearTo: data.get(#yearTo, or: $value.yearTo),
    sortBy: data.get(#sortBy, or: $value.sortBy),
    sortDirection: data.get(#sortDirection, or: $value.sortDirection),
  );

  @override
  GamebaseFiltersCopyWith<$R2, GamebaseFilters, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _GamebaseFiltersCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class GamebaseExplorerStateMapper
    extends ClassMapperBase<GamebaseExplorerState> {
  GamebaseExplorerStateMapper._();

  static GamebaseExplorerStateMapper? _instance;
  static GamebaseExplorerStateMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = GamebaseExplorerStateMapper._());
      MoveAggregateMapper.ensureInitialized();
      GamebaseFiltersMapper.ensureInitialized();
      GamebaseGameMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'GamebaseExplorerState';

  static String _$currentFen(GamebaseExplorerState v) => v.currentFen;
  static const Field<GamebaseExplorerState, String> _f$currentFen = Field(
    'currentFen',
    _$currentFen,
    opt: true,
    def: '',
  );
  static List<MoveAggregate> _$moveAggregates(GamebaseExplorerState v) =>
      v.moveAggregates;
  static const Field<GamebaseExplorerState, List<MoveAggregate>>
  _f$moveAggregates = Field(
    'moveAggregates',
    _$moveAggregates,
    opt: true,
    def: const [],
  );
  static bool _$isLoading(GamebaseExplorerState v) => v.isLoading;
  static const Field<GamebaseExplorerState, bool> _f$isLoading = Field(
    'isLoading',
    _$isLoading,
    opt: true,
    def: false,
  );
  static String? _$error(GamebaseExplorerState v) => v.error;
  static const Field<GamebaseExplorerState, String> _f$error = Field(
    'error',
    _$error,
    opt: true,
  );
  static GamebaseFilters _$filters(GamebaseExplorerState v) => v.filters;
  static const Field<GamebaseExplorerState, GamebaseFilters> _f$filters = Field(
    'filters',
    _$filters,
    opt: true,
    def: const GamebaseFilters(),
  );
  static GamebaseGame? _$selectedGame(GamebaseExplorerState v) =>
      v.selectedGame;
  static const Field<GamebaseExplorerState, GamebaseGame> _f$selectedGame =
      Field('selectedGame', _$selectedGame, opt: true);
  static ChessGame? _$game(GamebaseExplorerState v) => v.game;
  static const Field<GamebaseExplorerState, ChessGame> _f$game = Field(
    'game',
    _$game,
    opt: true,
  );
  static List<int> _$movePointer(GamebaseExplorerState v) => v.movePointer;
  static const Field<GamebaseExplorerState, List<int>> _f$movePointer = Field(
    'movePointer',
    _$movePointer,
    opt: true,
    def: const [],
  );

  @override
  final MappableFields<GamebaseExplorerState> fields = const {
    #currentFen: _f$currentFen,
    #moveAggregates: _f$moveAggregates,
    #isLoading: _f$isLoading,
    #error: _f$error,
    #filters: _f$filters,
    #selectedGame: _f$selectedGame,
    #game: _f$game,
    #movePointer: _f$movePointer,
  };

  static GamebaseExplorerState _instantiate(DecodingData data) {
    return GamebaseExplorerState(
      currentFen: data.dec(_f$currentFen),
      moveAggregates: data.dec(_f$moveAggregates),
      isLoading: data.dec(_f$isLoading),
      error: data.dec(_f$error),
      filters: data.dec(_f$filters),
      selectedGame: data.dec(_f$selectedGame),
      game: data.dec(_f$game),
      movePointer: data.dec(_f$movePointer),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static GamebaseExplorerState fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<GamebaseExplorerState>(map);
  }

  static GamebaseExplorerState fromJson(String json) {
    return ensureInitialized().decodeJson<GamebaseExplorerState>(json);
  }
}

mixin GamebaseExplorerStateMappable {
  String toJson() {
    return GamebaseExplorerStateMapper.ensureInitialized()
        .encodeJson<GamebaseExplorerState>(this as GamebaseExplorerState);
  }

  Map<String, dynamic> toMap() {
    return GamebaseExplorerStateMapper.ensureInitialized()
        .encodeMap<GamebaseExplorerState>(this as GamebaseExplorerState);
  }

  GamebaseExplorerStateCopyWith<
    GamebaseExplorerState,
    GamebaseExplorerState,
    GamebaseExplorerState
  >
  get copyWith =>
      _GamebaseExplorerStateCopyWithImpl<
        GamebaseExplorerState,
        GamebaseExplorerState
      >(this as GamebaseExplorerState, $identity, $identity);
  @override
  String toString() {
    return GamebaseExplorerStateMapper.ensureInitialized().stringifyValue(
      this as GamebaseExplorerState,
    );
  }

  @override
  bool operator ==(Object other) {
    return GamebaseExplorerStateMapper.ensureInitialized().equalsValue(
      this as GamebaseExplorerState,
      other,
    );
  }

  @override
  int get hashCode {
    return GamebaseExplorerStateMapper.ensureInitialized().hashValue(
      this as GamebaseExplorerState,
    );
  }
}

extension GamebaseExplorerStateValueCopy<$R, $Out>
    on ObjectCopyWith<$R, GamebaseExplorerState, $Out> {
  GamebaseExplorerStateCopyWith<$R, GamebaseExplorerState, $Out>
  get $asGamebaseExplorerState => $base.as(
    (v, t, t2) => _GamebaseExplorerStateCopyWithImpl<$R, $Out>(v, t, t2),
  );
}

abstract class GamebaseExplorerStateCopyWith<
  $R,
  $In extends GamebaseExplorerState,
  $Out
>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    MoveAggregate,
    MoveAggregateCopyWith<$R, MoveAggregate, MoveAggregate>
  >
  get moveAggregates;
  GamebaseFiltersCopyWith<$R, GamebaseFilters, GamebaseFilters> get filters;
  GamebaseGameCopyWith<$R, GamebaseGame, GamebaseGame>? get selectedGame;
  ListCopyWith<$R, int, ObjectCopyWith<$R, int, int>> get movePointer;
  $R call({
    String? currentFen,
    List<MoveAggregate>? moveAggregates,
    bool? isLoading,
    String? error,
    GamebaseFilters? filters,
    GamebaseGame? selectedGame,
    ChessGame? game,
    List<int>? movePointer,
  });
  GamebaseExplorerStateCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _GamebaseExplorerStateCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, GamebaseExplorerState, $Out>
    implements GamebaseExplorerStateCopyWith<$R, GamebaseExplorerState, $Out> {
  _GamebaseExplorerStateCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<GamebaseExplorerState> $mapper =
      GamebaseExplorerStateMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    MoveAggregate,
    MoveAggregateCopyWith<$R, MoveAggregate, MoveAggregate>
  >
  get moveAggregates => ListCopyWith(
    $value.moveAggregates,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(moveAggregates: v),
  );
  @override
  GamebaseFiltersCopyWith<$R, GamebaseFilters, GamebaseFilters> get filters =>
      $value.filters.copyWith.$chain((v) => call(filters: v));
  @override
  GamebaseGameCopyWith<$R, GamebaseGame, GamebaseGame>? get selectedGame =>
      $value.selectedGame?.copyWith.$chain((v) => call(selectedGame: v));
  @override
  ListCopyWith<$R, int, ObjectCopyWith<$R, int, int>> get movePointer =>
      ListCopyWith(
        $value.movePointer,
        (v, t) => ObjectCopyWith(v, $identity, t),
        (v) => call(movePointer: v),
      );
  @override
  $R call({
    String? currentFen,
    List<MoveAggregate>? moveAggregates,
    bool? isLoading,
    Object? error = $none,
    GamebaseFilters? filters,
    Object? selectedGame = $none,
    Object? game = $none,
    List<int>? movePointer,
  }) => $apply(
    FieldCopyWithData({
      if (currentFen != null) #currentFen: currentFen,
      if (moveAggregates != null) #moveAggregates: moveAggregates,
      if (isLoading != null) #isLoading: isLoading,
      if (error != $none) #error: error,
      if (filters != null) #filters: filters,
      if (selectedGame != $none) #selectedGame: selectedGame,
      if (game != $none) #game: game,
      if (movePointer != null) #movePointer: movePointer,
    }),
  );
  @override
  GamebaseExplorerState $make(CopyWithData data) => GamebaseExplorerState(
    currentFen: data.get(#currentFen, or: $value.currentFen),
    moveAggregates: data.get(#moveAggregates, or: $value.moveAggregates),
    isLoading: data.get(#isLoading, or: $value.isLoading),
    error: data.get(#error, or: $value.error),
    filters: data.get(#filters, or: $value.filters),
    selectedGame: data.get(#selectedGame, or: $value.selectedGame),
    game: data.get(#game, or: $value.game),
    movePointer: data.get(#movePointer, or: $value.movePointer),
  );

  @override
  GamebaseExplorerStateCopyWith<$R2, GamebaseExplorerState, $Out2>
  $chain<$R2, $Out2>(Then<$Out2, $R2> t) =>
      _GamebaseExplorerStateCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

