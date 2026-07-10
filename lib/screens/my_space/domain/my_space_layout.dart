enum MySpaceShelfSize {
  compact('compact'),
  standard('standard'),
  featured('featured');

  const MySpaceShelfSize(this.rawValue);

  final String rawValue;

  static MySpaceShelfSize fromJson(Object? value, {String path = 'size'}) {
    final rawValue = _readNonBlankString(value, path);
    for (final size in values) {
      if (size.rawValue == rawValue) {
        return size;
      }
    }
    throw FormatException(
      '$path has unsupported shelf size "$rawValue". '
      'Expected one of: ${values.map((size) => size.rawValue).join(', ')}.',
    );
  }

  String toJson() => rawValue;
}

const Set<MySpaceShelfSize> _collectionShelfSizes = {
  MySpaceShelfSize.compact,
  MySpaceShelfSize.standard,
};

const Set<MySpaceShelfSize> _prominentShelfSizes = {
  MySpaceShelfSize.standard,
  MySpaceShelfSize.featured,
};

/// A shelf type from the version 1 My Space wire contract.
///
/// Known values are exposed as constants. A future value is represented by
/// [MySpaceUnsupportedShelfType], which retains its exact [rawType] but is not
/// eligible for serialization in a saveable layout.
sealed class MySpaceShelfType {
  const MySpaceShelfType._(this.rawType);

  static const MySpaceSupportedShelfType continueShelf =
      MySpaceSupportedShelfType._(
        'continue',
        isPinned: false,
        supportedSizes: _prominentShelfSizes,
      );
  static const MySpaceSupportedShelfType myLikes = MySpaceSupportedShelfType._(
    'my_likes',
    isPinned: false,
    supportedSizes: _collectionShelfSizes,
  );
  static const MySpaceSupportedShelfType savedEvents =
      MySpaceSupportedShelfType._(
        'saved_events',
        isPinned: false,
        supportedSizes: _collectionShelfSizes,
      );
  static const MySpaceSupportedShelfType databases =
      MySpaceSupportedShelfType._(
        'databases',
        isPinned: false,
        supportedSizes: _collectionShelfSizes,
      );
  static const MySpaceSupportedShelfType savedStudies =
      MySpaceSupportedShelfType._(
        'saved_studies',
        isPinned: false,
        supportedSizes: _collectionShelfSizes,
      );
  static const MySpaceSupportedShelfType favoritePlayers =
      MySpaceSupportedShelfType._(
        'favorite_players',
        isPinned: false,
        supportedSizes: _collectionShelfSizes,
      );
  static const MySpaceSupportedShelfType libraryRecents =
      MySpaceSupportedShelfType._(
        'library_recents',
        isPinned: false,
        supportedSizes: _collectionShelfSizes,
      );
  static const MySpaceSupportedShelfType miniatures =
      MySpaceSupportedShelfType._(
        'miniatures',
        isPinned: false,
        supportedSizes: _collectionShelfSizes,
      );
  static const MySpaceSupportedShelfType studyDiscovery =
      MySpaceSupportedShelfType._(
        'study_discovery',
        isPinned: false,
        supportedSizes: _collectionShelfSizes,
      );
  static const MySpaceSupportedShelfType pinnedEvent =
      MySpaceSupportedShelfType._(
        'pinned_event',
        isPinned: true,
        supportedSizes: _prominentShelfSizes,
      );
  static const MySpaceSupportedShelfType pinnedDatabase =
      MySpaceSupportedShelfType._(
        'pinned_database',
        isPinned: true,
        supportedSizes: _prominentShelfSizes,
      );
  static const MySpaceSupportedShelfType pinnedFolder =
      MySpaceSupportedShelfType._(
        'pinned_folder',
        isPinned: true,
        supportedSizes: _prominentShelfSizes,
      );
  static const MySpaceSupportedShelfType pinnedStudy =
      MySpaceSupportedShelfType._(
        'pinned_study',
        isPinned: true,
        supportedSizes: _prominentShelfSizes,
      );
  static const MySpaceSupportedShelfType pinnedStudyChapter =
      MySpaceSupportedShelfType._(
        'pinned_study_chapter',
        isPinned: true,
        supportedSizes: _prominentShelfSizes,
      );
  static const MySpaceSupportedShelfType pinnedPlayer =
      MySpaceSupportedShelfType._(
        'pinned_player',
        isPinned: true,
        supportedSizes: _prominentShelfSizes,
      );
  static const MySpaceSupportedShelfType pinnedGame =
      MySpaceSupportedShelfType._(
        'pinned_game',
        isPinned: true,
        supportedSizes: _prominentShelfSizes,
      );

  static const List<MySpaceSupportedShelfType> supportedValues = [
    continueShelf,
    myLikes,
    savedEvents,
    databases,
    savedStudies,
    favoritePlayers,
    libraryRecents,
    miniatures,
    studyDiscovery,
    pinnedEvent,
    pinnedDatabase,
    pinnedFolder,
    pinnedStudy,
    pinnedStudyChapter,
    pinnedPlayer,
    pinnedGame,
  ];

  static const Map<String, MySpaceSupportedShelfType> _supportedByRawType = {
    'continue': continueShelf,
    'my_likes': myLikes,
    'saved_events': savedEvents,
    'databases': databases,
    'saved_studies': savedStudies,
    'favorite_players': favoritePlayers,
    'library_recents': libraryRecents,
    'miniatures': miniatures,
    'study_discovery': studyDiscovery,
    'pinned_event': pinnedEvent,
    'pinned_database': pinnedDatabase,
    'pinned_folder': pinnedFolder,
    'pinned_study': pinnedStudy,
    'pinned_study_chapter': pinnedStudyChapter,
    'pinned_player': pinnedPlayer,
    'pinned_game': pinnedGame,
  };

  factory MySpaceShelfType.fromJson(Object? value, {String path = 'type'}) {
    final rawType = _readNonBlankString(value, path);
    return _supportedByRawType[rawType] ??
        MySpaceUnsupportedShelfType._(rawType);
  }

  /// The exact string read from, or written to, the wire contract.
  final String rawType;

  bool get isSupported;

  bool get isPinned;

  bool get isDynamic => isSupported && !isPinned;

  Set<MySpaceShelfSize> get supportedSizes;

  bool supportsSize(MySpaceShelfSize size) => supportedSizes.contains(size);

  String toJson() {
    if (!isSupported) {
      throw FormatException(
        'Unsupported shelf type "$rawType" cannot be serialized for saving.',
      );
    }
    return rawType;
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other.runtimeType == runtimeType &&
            other is MySpaceShelfType &&
            other.rawType == rawType;
  }

  @override
  int get hashCode => Object.hash(runtimeType, rawType);

  @override
  String toString() => rawType;
}

final class MySpaceSupportedShelfType extends MySpaceShelfType {
  const MySpaceSupportedShelfType._(
    super.rawType, {
    required this.isPinned,
    required this.supportedSizes,
  }) : super._();

  @override
  bool get isSupported => true;

  @override
  final bool isPinned;

  @override
  final Set<MySpaceShelfSize> supportedSizes;
}

final class MySpaceUnsupportedShelfType extends MySpaceShelfType {
  factory MySpaceUnsupportedShelfType(String rawType) {
    final validatedRawType = _readNonBlankString(rawType, 'rawType');
    if (MySpaceShelfType._supportedByRawType.containsKey(validatedRawType)) {
      throw FormatException(
        '"$validatedRawType" is a supported shelf type and cannot be '
        'represented as unsupported.',
      );
    }
    return MySpaceUnsupportedShelfType._(validatedRawType);
  }

  const MySpaceUnsupportedShelfType._(super.rawType) : super._();

  @override
  bool get isSupported => false;

  @override
  bool get isPinned => false;

  @override
  Set<MySpaceShelfSize> get supportedSizes => const {};
}

final class MySpaceShelfDescriptor {
  factory MySpaceShelfDescriptor({
    required String id,
    required MySpaceShelfType type,
    String? targetId,
    required MySpaceShelfSize size,
    bool visible = true,
  }) {
    final descriptor = MySpaceShelfDescriptor._(
      id: _readNonBlankString(id, 'descriptor.id'),
      type: type,
      targetId: _readNullableNonBlankString(targetId, 'descriptor.targetId'),
      size: size,
      visible: visible,
    );
    descriptor._validate(path: 'descriptor', requireSupported: false);
    return descriptor;
  }

  const MySpaceShelfDescriptor._({
    required this.id,
    required this.type,
    required this.targetId,
    required this.size,
    required this.visible,
  });

  factory MySpaceShelfDescriptor.fromJson(
    Map<String, dynamic> json, {
    String path = 'descriptor',
  }) {
    _validateExactKeys(json, const {
      'id',
      'type',
      'targetId',
      'size',
      'visible',
    }, path);

    final visible = json['visible'];
    if (visible is! bool) {
      throw FormatException('$path.visible must be a boolean.');
    }

    final descriptor = MySpaceShelfDescriptor._(
      id: _readNonBlankString(json['id'], '$path.id'),
      type: MySpaceShelfType.fromJson(json['type'], path: '$path.type'),
      targetId: _readNullableNonBlankString(json['targetId'], '$path.targetId'),
      size: MySpaceShelfSize.fromJson(json['size'], path: '$path.size'),
      visible: visible,
    );
    descriptor._validate(path: path, requireSupported: false);
    return descriptor;
  }

  final String id;
  final MySpaceShelfType type;
  final String? targetId;
  final MySpaceShelfSize size;
  final bool visible;

  bool get isSaveable => type.isSupported;

  void validateForSave() {
    _validate(path: 'descriptor', requireSupported: true);
  }

  Map<String, dynamic> toJson() {
    validateForSave();
    return {
      'id': id,
      'type': type.toJson(),
      'targetId': targetId,
      'size': size.toJson(),
      'visible': visible,
    };
  }

  void _validate({required String path, required bool requireSupported}) {
    if (!type.isSupported) {
      if (requireSupported) {
        throw FormatException(
          '$path.type "${type.rawType}" is unsupported and cannot be saved.',
        );
      }
      return;
    }

    if (type.isPinned && targetId == null) {
      throw FormatException(
        '$path.targetId is required for pinned type "${type.rawType}".',
      );
    }
    if (type.isDynamic && targetId != null) {
      throw FormatException(
        '$path.targetId must be null for dynamic type "${type.rawType}".',
      );
    }
    if (!type.supportsSize(size)) {
      throw FormatException(
        '$path.size "${size.rawValue}" is not supported for type '
        '"${type.rawType}". Expected one of: '
        '${type.supportedSizes.map((value) => value.rawValue).join(', ')}.',
      );
    }
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MySpaceShelfDescriptor &&
            other.id == id &&
            other.type == type &&
            other.targetId == targetId &&
            other.size == size &&
            other.visible == visible;
  }

  @override
  int get hashCode => Object.hash(id, type, targetId, size, visible);
}

final class MySpaceLayout {
  factory MySpaceLayout({
    int schemaVersion = currentSchemaVersion,
    required Iterable<MySpaceShelfDescriptor> shelves,
  }) {
    final layout = MySpaceLayout._(
      schemaVersion: schemaVersion,
      shelves: List<MySpaceShelfDescriptor>.unmodifiable(shelves),
    );
    layout._validate(path: 'layout', requireSupported: false);
    return layout;
  }

  const MySpaceLayout._({required this.schemaVersion, required this.shelves});

  factory MySpaceLayout.fromJson(Map<String, dynamic> json) {
    _validateExactKeys(json, const {'schema_version', 'shelves'}, 'layout');

    final schemaVersion = json['schema_version'];
    if (schemaVersion is! int) {
      throw const FormatException('layout.schema_version must be an integer.');
    }

    final rawShelves = json['shelves'];
    if (rawShelves is! List) {
      throw const FormatException('layout.shelves must be a JSON array.');
    }
    if (rawShelves.length > maxShelfCount) {
      throw FormatException(
        'layout.shelves contains ${rawShelves.length} shelves; the maximum is '
        '$maxShelfCount.',
      );
    }

    final shelves = <MySpaceShelfDescriptor>[];
    for (var index = 0; index < rawShelves.length; index++) {
      final path = 'layout.shelves[$index]';
      final shelfJson = _readJsonObject(rawShelves[index], path);
      shelves.add(MySpaceShelfDescriptor.fromJson(shelfJson, path: path));
    }

    final layout = MySpaceLayout._(
      schemaVersion: schemaVersion,
      shelves: List<MySpaceShelfDescriptor>.unmodifiable(shelves),
    );
    layout._validate(path: 'layout', requireSupported: false);
    return layout;
  }

  static const int currentSchemaVersion = 1;
  static const int maxShelfCount = 24;

  static final MySpaceLayout curatedDefault = MySpaceLayout(
    shelves: [
      MySpaceShelfDescriptor(
        id: 'default_continue',
        type: MySpaceShelfType.continueShelf,
        size: MySpaceShelfSize.standard,
      ),
      MySpaceShelfDescriptor(
        id: 'default_miniatures',
        type: MySpaceShelfType.miniatures,
        size: MySpaceShelfSize.standard,
      ),
      MySpaceShelfDescriptor(
        id: 'default_study_discovery',
        type: MySpaceShelfType.studyDiscovery,
        size: MySpaceShelfSize.standard,
      ),
      MySpaceShelfDescriptor(
        id: 'default_my_likes',
        type: MySpaceShelfType.myLikes,
        size: MySpaceShelfSize.standard,
      ),
      MySpaceShelfDescriptor(
        id: 'default_saved_events',
        type: MySpaceShelfType.savedEvents,
        size: MySpaceShelfSize.standard,
      ),
      MySpaceShelfDescriptor(
        id: 'default_databases',
        type: MySpaceShelfType.databases,
        size: MySpaceShelfSize.standard,
      ),
      MySpaceShelfDescriptor(
        id: 'default_saved_studies',
        type: MySpaceShelfType.savedStudies,
        size: MySpaceShelfSize.standard,
      ),
      MySpaceShelfDescriptor(
        id: 'default_favorite_players',
        type: MySpaceShelfType.favoritePlayers,
        size: MySpaceShelfSize.standard,
      ),
    ],
  );

  final int schemaVersion;
  final List<MySpaceShelfDescriptor> shelves;

  bool get isSaveable => shelves.every((shelf) => shelf.isSaveable);

  void validateForSave() {
    _validate(path: 'layout', requireSupported: true);
  }

  Map<String, dynamic> toJson() {
    validateForSave();
    return {
      'schema_version': schemaVersion,
      'shelves': shelves.map((shelf) => shelf.toJson()).toList(growable: false),
    };
  }

  void _validate({required String path, required bool requireSupported}) {
    if (schemaVersion != currentSchemaVersion) {
      throw FormatException(
        '$path.schema_version has unsupported version $schemaVersion; '
        'expected $currentSchemaVersion.',
      );
    }
    if (shelves.length > maxShelfCount) {
      throw FormatException(
        '$path.shelves contains ${shelves.length} shelves; the maximum is '
        '$maxShelfCount.',
      );
    }

    final descriptorIds = <String>{};
    final dynamicTypes = <String>{};
    final pinnedTargets = <(String, String)>{};

    for (var index = 0; index < shelves.length; index++) {
      final shelfPath = '$path.shelves[$index]';
      final shelf = shelves[index];
      shelf._validate(path: shelfPath, requireSupported: requireSupported);

      if (!descriptorIds.add(shelf.id)) {
        throw FormatException(
          '$shelfPath.id duplicates shelf id "${shelf.id}".',
        );
      }

      if (shelf.type.isDynamic && !dynamicTypes.add(shelf.type.rawType)) {
        throw FormatException(
          '$shelfPath.type "${shelf.type.rawType}" is a singleton dynamic '
          'shelf and is already present.',
        );
      }

      final targetId = shelf.targetId;
      if (shelf.type.isPinned && targetId != null) {
        final target = (shelf.type.rawType, targetId);
        if (!pinnedTargets.add(target)) {
          throw FormatException(
            '$shelfPath duplicates pinned target "${shelf.type.rawType}" '
            'with targetId "$targetId".',
          );
        }
      }
    }
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MySpaceLayout &&
            other.schemaVersion == schemaVersion &&
            _listsEqual(other.shelves, shelves);
  }

  @override
  int get hashCode => Object.hash(schemaVersion, Object.hashAll(shelves));
}

String _readNonBlankString(Object? value, String path) {
  if (value is! String) {
    throw FormatException('$path must be a string.');
  }
  if (value.trim().isEmpty) {
    throw FormatException('$path must be a non-empty string.');
  }
  if (value.trim() != value) {
    throw FormatException(
      '$path must not contain leading or trailing whitespace.',
    );
  }
  return value;
}

String? _readNullableNonBlankString(Object? value, String path) {
  if (value == null) {
    return null;
  }
  return _readNonBlankString(value, path);
}

Map<String, dynamic> _readJsonObject(Object? value, String path) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    if (value.keys.any((key) => key is! String)) {
      throw FormatException('$path must contain only string keys.');
    }
    return value.map(
      (key, nestedValue) => MapEntry(key as String, nestedValue),
    );
  }
  throw FormatException('$path must be a JSON object.');
}

void _validateExactKeys(
  Map<String, dynamic> json,
  Set<String> expectedKeys,
  String path,
) {
  final actualKeys = json.keys.toSet();
  final missingKeys = expectedKeys.difference(actualKeys).toList()..sort();
  if (missingKeys.isNotEmpty) {
    throw FormatException(
      '$path is missing required key(s): ${missingKeys.join(', ')}.',
    );
  }

  final unknownKeys = actualKeys.difference(expectedKeys).toList()..sort();
  if (unknownKeys.isNotEmpty) {
    throw FormatException(
      '$path contains unknown key(s): ${unknownKeys.join(', ')}.',
    );
  }
}

bool _listsEqual<T>(List<T> left, List<T> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
