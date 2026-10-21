import 'package:chessever2/repository/supabase/fetch_all_pages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Trello #1263: the calendar's year reads used one capped request ordered
  // by date, so a year past the cap lost its tail, which is every upcoming
  // event. A whole year has to come back, however many pages it takes.
  test('reads every page until a short one, past one page', () async {
    final source = List.generate(2537, (i) => i);
    final offsets = <int>[];

    final rows = await fetchAllPages<int>((offset, limit) async {
      offsets.add(offset);
      return source.skip(offset).take(limit).toList();
    }, keyOf: (row) => row);

    expect(rows, source);
    expect(offsets, [0, 1000, 2000]);
  });

  test('an exact multiple of the page size still ends', () async {
    final source = List.generate(2000, (i) => i);

    final rows = await fetchAllPages<int>(
      (offset, limit) async => source.skip(offset).take(limit).toList(),
      keyOf: (row) => row,
    );

    expect(rows, hasLength(2000));
  });

  test('a row repeated across pages comes back once', () async {
    // A row inserted mid-read shifts the next page by one.
    final pages = {
      0: [1, 2, 3],
      3: [3, 4],
    };

    final rows = await fetchAllPages<int>(
      (offset, limit) async => pages[offset] ?? const [],
      keyOf: (row) => row,
      pageSize: 3,
    );

    expect(rows, [1, 2, 3, 4]);
  });
}
