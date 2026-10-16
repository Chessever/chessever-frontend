import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:flutter_test/flutter_test.dart';

/// Trimmed copy of production row `SdWy7cp9` (Russian Blitz Championship
/// 2026). Its `info.players` was written as the int 171, which threw in
/// `TourInfo.fromJson` and left the whole event on an endless shimmer.
Map<String, dynamic> _russianBlitzRow() => {
  'id': 'SdWy7cp9',
  'name': 'Russian Blitz Championship 2026',
  'slug': 'russian-blitz-championship-2026',
  'created_at': '2026-10-14T21:08:28.776+00:00',
  'url':
      'https://lichess.org/broadcast/russian-blitz-championship-2026/SdWy7cp9',
  'tier': 5,
  'dates': ['2026-10-16T11:00:00+00:00'],
  'info': {
    'tc': '3 min + 2 sec / move',
    'fideTc': 'blitz',
    'format': '13-round Swiss',
    'players': 171,
    'location': 'Sochi',
    'timeZone': 'Europe/Moscow',
    'roundCount': 13,
    'schedule': [
      {'round': 1, 'startsAt': 1792148400000},
    ],
  },
  'players': [
    {'name': 'Player A', 'fed': 'RUS', 'rating': 2700, 'played': 0},
  ],
  'search': ['Russian Blitz Championship 2026'],
  'group_broadcast_id': 'russian_blitz_championship_2026',
  'avg_elo': 2534,
};

void main() {
  test('numeric info.players does not break Tour.fromJson', () {
    final tour = Tour.fromJson(_russianBlitzRow());
    expect(tour.id, 'SdWy7cp9');
    expect(tour.info.players, '171');
    expect(tour.info.format, '13-round Swiss');
    expect(tour.players.single.name, 'Player A');
  });

  test('any wrongly-typed info field degrades instead of throwing', () {
    final row = _russianBlitzRow()
      ..['info'] = {
        'tc': 180,
        'format': ['Swiss', 13],
        'website': {'url': 'x'},
        'standingsSource': true,
        'teamTable': 'yes',
      };
    final tour = Tour.fromJson(row);
    expect(tour.info.tc, '180');
    expect(tour.info.format, 'Swiss, 13');
    expect(tour.info.website, isNull);
    expect(tour.info.teamTable, isNull);
  });

  test('missing or malformed info, dates and players are tolerated', () {
    final row = _russianBlitzRow()
      ..['info'] = null
      ..['dates'] = ['2026-10-16T11:00:00+00:00', 'not a date', null]
      ..['players'] = [
        42,
        {'name': 'Player B', 'fed': 7},
      ];
    final tour = Tour.fromJson(row);
    expect(tour.dates, hasLength(1));
    expect(tour.players.single.federation, '7');
  });

  test('listFromJson skips an unreadable row and keeps the rest', () {
    final tours = Tour.listFromJson([
      _russianBlitzRow(),
      {'id': 'broken'},
      'garbage',
    ]);
    expect(tours.map((t) => t.id), ['SdWy7cp9']);
  });
}
