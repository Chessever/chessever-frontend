// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'library_folder.dart';

class LibraryFolderMapper extends ClassMapperBase<LibraryFolder> {
  LibraryFolderMapper._();

  static LibraryFolderMapper? _instance;
  static LibraryFolderMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = LibraryFolderMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'LibraryFolder';

  static String _$id(LibraryFolder v) => v.id;
  static const Field<LibraryFolder, String> _f$id = Field('id', _$id);
  static String _$userId(LibraryFolder v) => v.userId;
  static const Field<LibraryFolder, String> _f$userId = Field(
    'userId',
    _$userId,
  );
  static String _$name(LibraryFolder v) => v.name;
  static const Field<LibraryFolder, String> _f$name = Field('name', _$name);
  static String _$color(LibraryFolder v) => v.color;
  static const Field<LibraryFolder, String> _f$color = Field('color', _$color);
  static String _$icon(LibraryFolder v) => v.icon;
  static const Field<LibraryFolder, String> _f$icon = Field('icon', _$icon);
  static int _$orderIndex(LibraryFolder v) => v.orderIndex;
  static const Field<LibraryFolder, int> _f$orderIndex = Field(
    'orderIndex',
    _$orderIndex,
  );
  static DateTime _$createdAt(LibraryFolder v) => v.createdAt;
  static const Field<LibraryFolder, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );
  static DateTime _$updatedAt(LibraryFolder v) => v.updatedAt;
  static const Field<LibraryFolder, DateTime> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
  );
  static String? _$shareToken(LibraryFolder v) => v.shareToken;
  static const Field<LibraryFolder, String> _f$shareToken = Field(
    'shareToken',
    _$shareToken,
    opt: true,
  );
  static String? _$ownerDisplayName(LibraryFolder v) => v.ownerDisplayName;
  static const Field<LibraryFolder, String> _f$ownerDisplayName = Field(
    'ownerDisplayName',
    _$ownerDisplayName,
    opt: true,
  );
  static String? _$parentId(LibraryFolder v) => v.parentId;
  static const Field<LibraryFolder, String> _f$parentId = Field(
    'parentId',
    _$parentId,
    opt: true,
  );
  static bool _$isSubscribed(LibraryFolder v) => v.isSubscribed;
  static const Field<LibraryFolder, bool> _f$isSubscribed = Field(
    'isSubscribed',
    _$isSubscribed,
    opt: true,
    def: false,
  );

  @override
  final MappableFields<LibraryFolder> fields = const {
    #id: _f$id,
    #userId: _f$userId,
    #name: _f$name,
    #color: _f$color,
    #icon: _f$icon,
    #orderIndex: _f$orderIndex,
    #createdAt: _f$createdAt,
    #updatedAt: _f$updatedAt,
    #shareToken: _f$shareToken,
    #ownerDisplayName: _f$ownerDisplayName,
    #parentId: _f$parentId,
    #isSubscribed: _f$isSubscribed,
  };

  static LibraryFolder _instantiate(DecodingData data) {
    return LibraryFolder(
      id: data.dec(_f$id),
      userId: data.dec(_f$userId),
      name: data.dec(_f$name),
      color: data.dec(_f$color),
      icon: data.dec(_f$icon),
      orderIndex: data.dec(_f$orderIndex),
      createdAt: data.dec(_f$createdAt),
      updatedAt: data.dec(_f$updatedAt),
      shareToken: data.dec(_f$shareToken),
      ownerDisplayName: data.dec(_f$ownerDisplayName),
      parentId: data.dec(_f$parentId),
      isSubscribed: data.dec(_f$isSubscribed),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static LibraryFolder fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<LibraryFolder>(map);
  }

  static LibraryFolder fromJson(String json) {
    return ensureInitialized().decodeJson<LibraryFolder>(json);
  }
}

mixin LibraryFolderMappable {
  String toJson() {
    return LibraryFolderMapper.ensureInitialized().encodeJson<LibraryFolder>(
      this as LibraryFolder,
    );
  }

  Map<String, dynamic> toMap() {
    return LibraryFolderMapper.ensureInitialized().encodeMap<LibraryFolder>(
      this as LibraryFolder,
    );
  }

  LibraryFolderCopyWith<LibraryFolder, LibraryFolder, LibraryFolder>
  get copyWith => _LibraryFolderCopyWithImpl<LibraryFolder, LibraryFolder>(
    this as LibraryFolder,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return LibraryFolderMapper.ensureInitialized().stringifyValue(
      this as LibraryFolder,
    );
  }

  @override
  bool operator ==(Object other) {
    return LibraryFolderMapper.ensureInitialized().equalsValue(
      this as LibraryFolder,
      other,
    );
  }

  @override
  int get hashCode {
    return LibraryFolderMapper.ensureInitialized().hashValue(
      this as LibraryFolder,
    );
  }
}

extension LibraryFolderValueCopy<$R, $Out>
    on ObjectCopyWith<$R, LibraryFolder, $Out> {
  LibraryFolderCopyWith<$R, LibraryFolder, $Out> get $asLibraryFolder =>
      $base.as((v, t, t2) => _LibraryFolderCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class LibraryFolderCopyWith<$R, $In extends LibraryFolder, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? id,
    String? userId,
    String? name,
    String? color,
    String? icon,
    int? orderIndex,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? shareToken,
    String? ownerDisplayName,
    String? parentId,
    bool? isSubscribed,
  });
  LibraryFolderCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _LibraryFolderCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, LibraryFolder, $Out>
    implements LibraryFolderCopyWith<$R, LibraryFolder, $Out> {
  _LibraryFolderCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<LibraryFolder> $mapper =
      LibraryFolderMapper.ensureInitialized();
  @override
  $R call({
    String? id,
    String? userId,
    String? name,
    String? color,
    String? icon,
    int? orderIndex,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? shareToken = $none,
    Object? ownerDisplayName = $none,
    Object? parentId = $none,
    bool? isSubscribed,
  }) => $apply(
    FieldCopyWithData({
      if (id != null) #id: id,
      if (userId != null) #userId: userId,
      if (name != null) #name: name,
      if (color != null) #color: color,
      if (icon != null) #icon: icon,
      if (orderIndex != null) #orderIndex: orderIndex,
      if (createdAt != null) #createdAt: createdAt,
      if (updatedAt != null) #updatedAt: updatedAt,
      if (shareToken != $none) #shareToken: shareToken,
      if (ownerDisplayName != $none) #ownerDisplayName: ownerDisplayName,
      if (parentId != $none) #parentId: parentId,
      if (isSubscribed != null) #isSubscribed: isSubscribed,
    }),
  );
  @override
  LibraryFolder $make(CopyWithData data) => LibraryFolder(
    id: data.get(#id, or: $value.id),
    userId: data.get(#userId, or: $value.userId),
    name: data.get(#name, or: $value.name),
    color: data.get(#color, or: $value.color),
    icon: data.get(#icon, or: $value.icon),
    orderIndex: data.get(#orderIndex, or: $value.orderIndex),
    createdAt: data.get(#createdAt, or: $value.createdAt),
    updatedAt: data.get(#updatedAt, or: $value.updatedAt),
    shareToken: data.get(#shareToken, or: $value.shareToken),
    ownerDisplayName: data.get(#ownerDisplayName, or: $value.ownerDisplayName),
    parentId: data.get(#parentId, or: $value.parentId),
    isSubscribed: data.get(#isSubscribed, or: $value.isSubscribed),
  );

  @override
  LibraryFolderCopyWith<$R2, LibraryFolder, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _LibraryFolderCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

