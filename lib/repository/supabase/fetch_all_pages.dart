/// Rows asked for per request while reading a whole range. At or under the
/// PostgREST `max-rows` cap, so a full page always means there may be more.
const supabaseReadPageSize = 1000;

/// Reads pages of [pageSize] from [fetchPage] until one comes back short,
/// and returns every row once. A row inserted mid-read can shift the next
/// page by one, so rows already seen (by [keyOf]) are dropped.
///
/// [fetchPage] must order by a unique key (or break ties on one), otherwise
/// offset paging can skip or repeat rows.
Future<List<T>> fetchAllPages<T>(
  Future<List<T>> Function(int offset, int limit) fetchPage, {
  required Object Function(T row) keyOf,
  int pageSize = supabaseReadPageSize,
}) async {
  final rows = <Object, T>{};
  var offset = 0;
  while (true) {
    final page = await fetchPage(offset, pageSize);
    for (final row in page) {
      rows.putIfAbsent(keyOf(row), () => row);
    }
    if (page.length < pageSize) return rows.values.toList(growable: false);
    offset += page.length;
  }
}
