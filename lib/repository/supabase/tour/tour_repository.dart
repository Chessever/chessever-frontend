import 'package:chessever2/repository/supabase/base_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final tourRepositoryProvider = AutoDisposeProvider<TourRepository>((ref) {
  return TourRepository();
});

class TourRepository extends BaseRepository {
  // Fetch all tours with pagination and sorting
  Future<List<Tour>> getTours({
    int? limit,
    int? offset,
    String orderBy = 'created_at',
    bool ascending = false,
  }) async {
    return handleApiCall(() async {
      PostgrestTransformBuilder<PostgrestList> query =
          supabase.from('tours').select();

      query = query.order(orderBy, ascending: ascending);

      if (limit != null) {
        query = query.limit(limit);
      }

      if (offset != null) {
        query = query.range(offset, offset + (limit ?? 50) - 1);
      }

      final response = await query;
      return (response as List).map((json) => Tour.fromJson(json)).toList();
    });
  }

  // Fetch tour by ID
  Future<Tour> getTourById(String id) async {
    return handleApiCall(() async {
      final response =
          await supabase.from('tours').select().eq('id', id).single();

      return Tour.fromJson(response);
    });
  }

  // Fetch tour by slug
  Future<Tour> getTourBySlug(String slug) async {
    return handleApiCall(() async {
      final response =
          await supabase.from('tours').select().eq('slug', slug).single();

      return Tour.fromJson(response);
    });
  }

  // Fetch tours by tier
  Future<List<Tour>> getToursByTier(int tier, {int? limit}) async {
    return handleApiCall(() async {
      var query = supabase
          .from('tours')
          .select()
          .eq('tier', tier)
          .order('created_at', ascending: false);

      if (limit != null) {
        query = query.limit(limit);
      }

      final response = await query;
      return (response as List).map((json) => Tour.fromJson(json)).toList();
    });
  }

  // Search tours by name
  Future<List<Tour>> searchToursByName(String searchQuery) async {
    return handleApiCall(() async {
      final response = await supabase
          .from('tours')
          .select()
          .ilike('name', '%$searchQuery%')
          .order('created_at', ascending: false);

      return (response as List).map((json) => Tour.fromJson(json)).toList();
    });
  }

  // Get tours that are currently active (based on dates)
  Future<List<Tour>> getActiveTours() async {
    return handleApiCall(() async {
      final now = DateTime.now();
      final response = await supabase
          .from('tours')
          .select()
          .order('created_at', ascending: false);

      final tours =
          (response as List).map((json) => Tour.fromJson(json)).toList();

      // Filter tours that have current date within their date range
      return tours.where((tour) {
        return tour.dates.any(
          (date) =>
              date.isAfter(now.subtract(Duration(days: 1))) &&
              date.isBefore(now.add(Duration(days: 1))),
        );
      }).toList();
    });
  }

  // Get recent tours
  Future<List<Tour>> getRecentTours({int limit = 10}) async {
    return handleApiCall(() async {
      final response = await supabase
          .from('tours')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);

      return (response as List).map((json) => Tour.fromJson(json)).toList();
    });
  }

  // Get tour with player count
  Future<Map<String, dynamic>> getTourWithStats(String id) async {
    return handleApiCall(() async {
      final tour = await getTourById(id);
      final playerCount = tour.players.length;

      // Get round count
      final roundsResponse = await supabase
          .from('rounds')
          .select('id')
          .eq('tour_id', id);

      final roundCount = (roundsResponse as List).length;

      return {
        'tour': tour,
        'playerCount': playerCount,
        'roundCount': roundCount,
      };
    });
  }
}
