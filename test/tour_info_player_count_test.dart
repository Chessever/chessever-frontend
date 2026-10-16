import 'dart:convert';
import 'dart:io';

import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Russian Rapid 2026 parses a numeric participant count', () {
    // Production metadata and one roster entry; the full roster is unnecessary.
    final json =
        jsonDecode(
              File(
                'test/fixtures/russian_rapid_2026_tour.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final tour = Tour.fromJson(json);

    expect(tour.id, 'yv058ZKo');
    expect(tour.info.players, '158');
    expect(tour.players.single.name, 'Dubov, Daniil');
    expect(tour.players.single.score, 8.5);
    expect(Tour.fromJson(tour.toJson()).info.players, '158');
  });

  test('participant descriptions and absent counts remain supported', () {
    for (final value in ['158', '80 players', '', null]) {
      final info = TourInfo.fromJson({'players': value});
      expect(info.players, value);
      expect(TourInfo.fromJson(info.toJson()).players, value);
    }
  });
}
