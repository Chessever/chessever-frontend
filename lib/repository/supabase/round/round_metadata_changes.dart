import 'package:collection/collection.dart';

/// Suppresses ingestion/heartbeat updates that cannot change a Round model.
/// Keep these columns in sync with Round.fromJson. Old Realtime records may
/// contain only the primary key, so compare consecutive *new* records instead.
class RoundMetadataChanges {
  static const columns = [
    'id',
    'slug',
    'tour_id',
    'tour_slug',
    'name',
    'created_at',
    'starts_at',
    'url',
  ];
  final _snapshots = <String, List<Object?>>{};

  bool accept(Map<String, dynamic> record, {required bool deleted}) {
    final id = record['id']?.toString();
    if (id == null) return true;
    if (deleted || !columns.every(record.containsKey)) {
      // Deletes and incomplete payloads must still reconcile over HTTP.
      _snapshots.remove(id);
      return true;
    }
    final snapshot = [for (final column in columns) record[column]];
    final previous = _snapshots[id];
    _snapshots[id] = snapshot;
    return previous == null ||
        !const ListEquality<Object?>().equals(previous, snapshot);
  }

  /// Reconnects must reconcile changes that happened while disconnected.
  void reset() => _snapshots.clear();
}
