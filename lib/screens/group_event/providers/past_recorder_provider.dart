import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../repository/local_storage/unified_favorites/unified_favorites_provider.dart';
import '../../../widgets/event_card/starred_provider.dart';
import '../model/tour_event_card_model.dart';

final pastEventsUiReorderProvider =
    Provider.family<List<GroupEventCardModel>, List<GroupEventCardModel>>((
      ref,
      originalList,
    ) {
      final starred = ref.watch(starredProvider);
      final unifiedAsync = ref.watch(favoriteEventsProvider);
      final unified = unifiedAsync.maybeWhen(
        data: (list) => list.map((e) => e['id'] as String).toList(),
        orElse: () => <String>[],
      );

      final allFavorites = <String>{...starred, ...unified};

      final favorited = <GroupEventCardModel>[];
      final nonFavorited = <GroupEventCardModel>[];

      for (final event in originalList) {
        if (allFavorites.contains(event.id)) {
          favorited.add(event);
        } else {
          nonFavorited.add(event);
        }
      }

      return [...favorited, ...nonFavorited];
    });


