typedef NotationId = String; // e.g., "0/2/0"

class NotationPointerHelper {
  static NotationId fromPointer(List<int> pointer) => pointer.join('/');

  static List<int> toPointer(NotationId id) =>
      id.isEmpty ? <int>[] : id.split('/').map(int.parse).toList();

  static NotationId child(NotationId parent, int index) =>
      parent.isEmpty ? '$index' : '$parent/$index';
}

