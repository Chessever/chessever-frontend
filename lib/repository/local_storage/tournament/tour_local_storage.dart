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

  Future<void> fetchAndSaveTournament(String groupId) async {
    try {
      final tours = await ref
          .read(tourRepositoryProvider)
          .getTourByGroupId(groupId);

      final toursEncoded = _encodeMyToursList(tours);
      await ref
          .read(sharedPreferencesRepository)
          .setStringList(getPathId(groupId), toursEncoded);
    } catch (error, _) {
      rethrow;
    }
  }

  String getPathId(String id) => '${_LocalTourStorage.tour.name}$id';

  Future<List<Tour>> getToursBasedOnGroupId(String groupId) async {
    try {
      await fetchAndSaveTournament(groupId);
      final tourStringList = await ref
          .read(sharedPreferencesRepository)
          .getStringList(getPathId(groupId));

      final firstBatch = _decodeMyToursList(tourStringList);

      return firstBatch;
    } catch (e) {
      return <Tour>[];
    }
  }

  Future<List<Tour>> getTours(String groupId) async {
    try {
      return ref.read(tourRepositoryProvider).getTourByGroupId(groupId);
    } catch (e, _) {
      return <Tour>[];
    }
  }
}

List<String> _encodeMyToursList(List<Tour> tours) =>
    tours.map(_encoder).toList();

List<Tour> _decodeMyToursList(List<String> tourStringList) =>
    tourStringList
        .map<Tour>((reelsString) => Tour.fromJson(_decoder(reelsString)))
        .toList();

String _encoder(Tour tour) => json.encode(tour.toJson());

Map<String, dynamic> _decoder(String tourString) =>
    json.decode(tourString) as Map<String, dynamic>;
