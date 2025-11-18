import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Fetches the image URL for a group broadcast event
/// Returns the first tour's image from the tours table
final eventImageProvider = FutureProvider.autoDispose.family<String?, String>(
  (ref, groupBroadcastId) async {
    try {
      final tourRepo = ref.read(tourRepositoryProvider);
      final tours = await tourRepo.getTourByGroupId(groupBroadcastId);

      if (tours.isNotEmpty && tours.first.image != null) {
        return tours.first.image;
      }
      return null;
    } catch (e) {
      debugPrint('[EventImageProvider] Error fetching image for $groupBroadcastId: $e');
      return null;
    }
  },
);
