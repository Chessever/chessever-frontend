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
      final tours = await ref.read(tourRepositoryProvider).getTours();
      final toursEncoded = _encodeMyReelsList(tours);
      await ref
          .read(sharedPreferencesRepository)
          .setStringList(_LocalTourStorage.tour.name, toursEncoded);
    } catch (error, _) {}
  }

  Future<List<Tour>> getTours() async {
    try {
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

        // Search in tournament name (highest weight)
        final nameLower = tour.name.toLowerCase();
        if (nameLower.contains(queryLower)) {
          if (nameLower.startsWith(queryLower)) {
            score += 100.0; // Exact start match gets highest score
          } else {
            score += 80.0; // Contains match gets high score
          }
        } else {
          // Check for partial word matches in name
          final nameWords = nameLower.split(' ');
          for (final word in nameWords) {
            if (word.startsWith(queryLower)) {
              score += 60.0;
            } else if (word.contains(queryLower)) {
              score += 40.0;
            }
          }
        }

        // Search in location (medium weight)
        final locationLower = tour.info.location?.toLowerCase() ?? '';
        if (locationLower.isNotEmpty) {
          if (locationLower.contains(queryLower)) {
            if (locationLower.startsWith(queryLower)) {
              score += 50.0;
            } else {
              score += 30.0;
            }
          } else {
            // Check for partial word matches in location
            final locationWords = locationLower.split(' ');
            for (final word in locationWords) {
              if (word.startsWith(queryLower)) {
                score += 25.0;
              } else if (word.contains(queryLower)) {
                score += 15.0;
              }
            }
          }
        }

        // Search in notable players (lower weight)
        final players = tour.notablePlayers;
        for (final player in players) {
          final playerLower = player.toLowerCase();
          if (playerLower.contains(queryLower)) {
            if (playerLower.startsWith(queryLower)) {
              score += 20.0;
            } else {
              score += 10.0;
            }
          } else {
            // Check for partial word matches in player names
            final playerWords = playerLower.split(' ');
            for (final word in playerWords) {
              if (word.startsWith(queryLower)) {
                score += 15.0;
              } else if (word.contains(queryLower)) {
                score += 8.0;
              }
            }
          }
        }

        // Only include tours with a minimum relevance score
        if (score > 0) {
          tourScores.add(MapEntry(tour, score));
        }
      }

      // Sort by relevance score (highest first) and return the tours
      tourScores.sort((a, b) => b.value.compareTo(a.value));

      // Return only the most relevant results (top matches)
      const maxResults = 20; // Adjust this number as needed
      final relevantTours =
          tourScores.take(maxResults).map((entry) => entry.key).toList();

      return relevantTours;
    } catch (error, _) {
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
