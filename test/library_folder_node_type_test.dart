import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _folderJson({String? nodeType}) {
  return {
    'id': 'folder-1',
    'user_id': 'user-1',
    'name': 'Study',
    'color': '#0FB4E5',
    'icon': 'folder',
    'order_index': 0,
    'created_at': '2026-05-30T00:00:00Z',
    'updated_at': '2026-05-30T00:00:00Z',
    'parent_id': null,
    if (nodeType != null) 'node_type': nodeType,
  };
}

void main() {
  test('LibraryFolder defaults legacy rows to database node type', () {
    final folder = LibraryFolder.fromSupabase(_folderJson());

    expect(folder.nodeType, LibraryFolder.nodeTypeDatabase);
    expect(folder.isDatabase, isTrue);
    expect(folder.isFolder, isFalse);
    expect(
      folder.toSupabaseInsert()['node_type'],
      LibraryFolder.nodeTypeDatabase,
    );
  });

  test('LibraryFolder preserves folder node type through map and copyWith', () {
    final folder = LibraryFolder.fromSupabase(
      _folderJson(nodeType: LibraryFolder.nodeTypeFolder),
    );

    expect(folder.nodeType, LibraryFolder.nodeTypeFolder);
    expect(folder.isFolder, isTrue);
    expect(folder.toSupabaseMap()['node_type'], LibraryFolder.nodeTypeFolder);

    final renamed = folder.copyWith(name: 'Openings');
    expect(renamed.nodeType, LibraryFolder.nodeTypeFolder);
    expect(renamed.isDatabase, isFalse);
  });
}
