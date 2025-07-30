import 'dart:convert';

import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final tourLocalStorageProvider = Provider<_TourLocalStorage>(
  (ref) => _TourLocalStorage(ref),
);

enum _LocalTourStorage { tour }

class _TourLocalStorage {
  _TourLocalStorage(this.ref);

  final Ref ref;

  Future<void> fetchAndSaveTournament() async {
    try {
      final tours = await ref.read(tourRepositoryProvider).getTournaments();

      final toursEncoded = _encodeMyReelsList(tours);
      await ref
          .read(sharedPreferencesRepository)
          .setStringList(_LocalTourStorage.tour.name, toursEncoded);
    } catch (error, _) {
      rethrow;
    }
  }

  Future<List<Tour>> getTours() async {
    try {
      final tourStringList = await ref
          .read(sharedPreferencesRepository)
          .getStringList(_LocalTourStorage.tour.name);

      if (tourStringList.isEmpty) {
        await fetchAndSaveTournament();
        return getTours();
      }

      final firstBatch = _decodeMyReelsList(tourStringList);

      return firstBatch;
    } catch (e) {
      return <Tour>[];
    }
  }

  Future<List<Tour>> refresh() async {
    try {
      await fetchAndSaveTournament();
      final tourStringList = await ref
          .read(sharedPreferencesRepository)
          .getStringList(_LocalTourStorage.tour.name);
      if (tourStringList.isNotEmpty) {
        return _decodeMyReelsList(tourStringList);
      } else {
        await fetchAndSaveTournament();
        final tourStringList = await ref
            .read(sharedPreferencesRepository)
            .getStringList(_LocalTourStorage.tour.name);
        return _decodeMyReelsList(tourStringList);
      }
    } catch (error, _) {
      return <Tour>[];
    }
  }

  Future<List<Tour>> searchToursByName(String query) async {
    try {
      final tours = await getTours();

      if (query.isEmpty) {
        return tours;
      }

      final queryLower = query.toLowerCase().trim();

      // Create a list of tours with their relevance scores
      final List<MapEntry<Tour, double>> tourScores = [];

      for (final tour in tours) {
        double score = 0.0;

        // 🔍 PRIMARY: Use `search` field if available
        if (tour.search != null && tour.search!.isNotEmpty) {
          for (final term in tour.search!) {
            final termLower = term.toLowerCase();

            if (termLower == queryLower) {
              score += 120.0; // Exact match
              break;
            } else if (termLower.startsWith(queryLower)) {
              score += 100.0;
            } else if (termLower.contains(queryLower)) {
              score += 80.0;
            }
          }
        }

        // 🔄 FALLBACK: Search in `name`
        final nameLower = tour.name.toLowerCase();
        if (nameLower.contains(queryLower)) {
          if (nameLower.startsWith(queryLower)) {
            score += 60.0;
          } else {
            score += 40.0;
          }
        }

        // 🔄 FALLBACK: Search in `location`
        final locationLower = tour.info.location?.toLowerCase() ?? '';
        if (locationLower.contains(queryLower)) {
          if (locationLower.startsWith(queryLower)) {
            score += 30.0;
          } else {
            score += 20.0;
          }
        }

        // 🔄 FALLBACK: Search in `players`
        final players = tour.players;
        for (final playerMap in players) {
          final playerName = playerMap['name']?.toString().toLowerCase() ?? '';
          if (playerName.contains(queryLower)) {
            if (playerName.startsWith(queryLower)) {
              score += 15.0;
            } else {
              score += 10.0;
            }
          }
        }

        if (score > 0) {
          tourScores.add(MapEntry(tour, score));
        }
      }

      tourScores.sort((a, b) => b.value.compareTo(a.value));
      const maxResults = 20;
      return tourScores.take(maxResults).map((e) => e.key).toList();
    } catch (e, _) {
      return <Tour>[];
    }
  }
}

List<String> _encodeMyReelsList(List<Tour> tours) =>
    tours.map(_encoder).toList();

List<Tour> _decodeMyReelsList(List<String> tourStringList) =>
    tourStringList
        .map<Tour>((reelsString) => Tour.fromJson(_decoder(reelsString)))
        .toList();

String _encoder(Tour tour) => json.encode(tour.toJson());

Map<String, dynamic> _decoder(String tourString) =>
    json.decode(tourString) as Map<String, dynamic>;

List<Tour> decodeToursInIsolate(List<String> jsonStrings) {
  return jsonStrings.map<Tour>((e) {
    final decoded = json.decode(e) as Map<String, dynamic>;
    return Tour.fromJson(decoded);
  }).toList();
}
