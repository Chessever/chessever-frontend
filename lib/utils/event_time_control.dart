/// Broadcast / game time-control categories used by the home Filter popup.
///
/// The chips store `{standard, rapid, blitz}`. The database mixes `standard`
/// with `classical`, and Blitz events are sometimes tagged `bullet`. Matching
/// is by bucket so every surface (home list, search, smart-event fetch) agrees.
enum TimeControlBucket { classical, rapid, blitz }

/// Maps a stored or UI time-control token onto a filter chip.
TimeControlBucket? timeControlBucketFor(String? raw) {
  final value = raw?.trim().toLowerCase();
  if (value == null || value.isEmpty) return null;
  switch (value) {
    case 'standard':
    case 'classical':
      return TimeControlBucket.classical;
    case 'rapid':
      return TimeControlBucket.rapid;
    case 'blitz':
    case 'bullet':
      return TimeControlBucket.blitz;
    default:
      return null;
  }
}

Set<TimeControlBucket> timeControlBucketsFor(Iterable<String> tokens) {
  return {
    for (final token in tokens)
      if (timeControlBucketFor(token) case final bucket?) bucket,
  };
}

/// Selecting every Time Control chip is the same as selecting none: do not
/// hide unknown or untagged events.
bool selectsEveryTimeControlBucket(Iterable<String> tokens) {
  return timeControlBucketsFor(tokens).containsAll(TimeControlBucket.values);
}

/// Whether [timeControl] satisfies the popup's Time Control chips.
///
/// Unknown / empty values pass when no chip is selected, or when every chip
/// is selected. A partial selection (e.g. Blitz only) still drops them.
bool broadcastMatchesTimeControlFilter(
  String? timeControl,
  Iterable<String> requestedFormats,
) {
  final buckets = timeControlBucketsFor(requestedFormats);
  if (buckets.isEmpty || buckets.containsAll(TimeControlBucket.values)) {
    return true;
  }
  final actual = timeControlBucketFor(timeControl);
  if (actual == null) return false;
  return buckets.contains(actual);
}

/// Both casings PostgREST equality needs for `group_broadcasts.time_control`.
///
/// Empty when [requestedFormats] selects every bucket (or none) — callers
/// should then skip event-level time-control scoping.
List<String> postgrestTimeControlValues(Iterable<String> requestedFormats) {
  if (selectsEveryTimeControlBucket(requestedFormats)) return const [];
  final values = <String>{};
  void addBothCases(String token) {
    values.add(token);
    if (token.isEmpty) return;
    values.add('${token[0].toUpperCase()}${token.substring(1)}');
  }

  for (final bucket in timeControlBucketsFor(requestedFormats)) {
    switch (bucket) {
      case TimeControlBucket.classical:
        addBothCases('standard');
        addBothCases('classical');
      case TimeControlBucket.rapid:
        addBothCases('rapid');
      case TimeControlBucket.blitz:
        addBothCases('blitz');
        addBothCases('bullet');
    }
  }
  return values.toList(growable: false);
}
